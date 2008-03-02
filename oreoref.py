import os
import sys
import cgi
import urllib
import UserDict
import random
import time
import re
import md5
import cPickle as pickle

### Logger ###
debug = False

if debug :
    import logging
    logging.basicConfig(level=logging.DEBUG,
                        format='%(asctime)s %(levelname)s %(message)s',
                        filename=sys.argv[0]+".log" ,
                        filemode='a' )
else:
    class DummyLogger(object):
        def info(*args):pass
        def debug(*args):pass
    logging = DummyLogger()

def geteuid():
    try:
        return os.geteuid()
    except AttributeError:
        return 0

### datafile ###

class MkdirLockError(StandardError):
    pass

class IronShelve(UserDict.DictMixin):
    def __init__(self,filename):
        self._filename = filename
        self._modify   = False
        try:
            f = file( self._filename + ".p" , "r" )
            self._data = pickle.load( f )
            f.close()
        except:
            self._data = {}
    
    def commit(self):
        if not self._modify :
            return

        ### File lock ###
        lockfn = self._filename + ".LOCK"

        ### Drop expired lock.###
        try:
            if os.stat(lockfn).st_mtime < time.time() - 300 :
                # expired lock exists 
                os.rmdir(lockfn)
        except OSError: # lock file not found.
            pass

        ### Get Lock ###
        for i in 1,2,3,4,5:
            try:
                os.mkdir(lockfn)
                break
            except OSError:
                time.sleep(1)
                continue
        else: ### try over ###
            raise MkdirLockError();

        ### Write file ###
        try:
            f = file(self._filename+".p","w")
            pickle.dump( self._data , f )
            f.close()
        finally:
            ### Release Lock ###
            os.rmdir(lockfn)

    def __getitem__(self,key):
        return self._data[ key ]
    def __setitem__(self,key,val):
        self._modify = True
        self._data[ key ] = val
    def __delitem__(self,key):
        self._modify = True
        del self._data[ key ]
    def __contain__(self,key):
        return key in self._data
    def __iter__(self):
        return iter(self._data)

class UserData(IronShelve):
    """ Permanent object class like shelve,
        but not write data when empty.
    """
    def __init__(self,user,workdir=None):
        self.user = user
        if not workdir :
            # Whenever 'pin.d' is a symbolic link,
            # 'pin.d/.' is always directory.
            workdir = re.sub(r"\.[a-z]*$",".d",sys.argv[0])
            if not os.path.isdir(workdir):
                if os.stat(sys.argv[0]).st_uid == geteuid() :
                    os.mkdir(workdir,0700)
                else:
                    os.mkdir(workdir,0777)
        filename = os.path.join(
            workdir ,
            re.sub("[^a-zA-Z0-9]",lambda M:"%%%02x"%ord(M.group(0)),user)
        )
        IronShelve.__init__(self,filename)

    def _shadow(self,password):
        m = md5.new(self.user)
        m.update("\n")
        m.update(password)
        return m.digest()

    def auth(self,password):
        if self.user == None :
            logging.info('auth failed : self.user == None')
            return False
        try:
            shadow = self._shadow(password)
            if shadow == self["shadow"]:
                return True
            else:
                logging.info('auth failed : unmatched(%s/%s)' ,
                             shadow , self["shadow"] )
                return False
        except KeyError:
            return password == "newuser"

    def chpasswd(self,password):
        self["shadow"] = self._shadow(password)

### Display Parts ###
def Cookie():
    return dict([ pair.split("=")
        for pair in re.split(r"; *",os.getenv("HTTP_COOKIE",""))
        if "=" in pair ])

def MyURL():
    return "http://"+os.getenv("HTTP_HOST","[HTTP_HOST") + \
           os.getenv("SCRIPT_NAME","[SCRIPT_NAME]")

def put_cookie(key,val):
    print 'Set-Cookie: %s=%s; expires=Tue, 1-Jan-2030 00:00:00 GMT; path=%s' \
        % ( urllib.quote_plus(key) , 
            urllib.quote_plus(val) ,
            os.getenv("SCRIPT_NAME","") )

def del_cookie(key):
    print 'Set-Cookie: %s=; expires=Fri, 31-Dec-1999 23:59:59 GMT; path=%s' \
        % ( urllib.quote_plus(key) , os.getenv("SCRIPT_NAME","") )

def transfer_url(url):
    print 'Content-type: text/html'
    print ''
    print '<html><head>'
    print '<title>Moving...</title>'
    if not debug:
        print '<meta http-equiv="refresh" content="0;URL=%s">' % cgi.escape(url)
    print '</head>'
    print '<body><a href="%s">Wait or Click Here</a></body>' % cgi.escape(url)
    print '</html>'

class Application(object):
    def __init__(self,form=None,data=None):
        self.myurl  = MyURL()
        self.form   = form
        self.data   = data
    
    def _action_nop(self) :
        return True

    def default(self):
        pass

    def run(self,cmdstr):
        method = getattr(
                self ,
                "action_" + cmdstr ,
                self._action_nop )
        return method()

class UserApplication(Application):
    charset="Shift_JIS"

    def print_h1(self):
        pass
    def print_man(self):
        pass
    def print_title(self):
        pass
    def print_message(self):
        print self.message

    def __init__(self,form):
        self.message = ""
        self.cookie  = Cookie()
        self.user = form.getfirst("_user",self.cookie.get("user",None))
        if self.user == None :
            Application.__init__(self,form,None)
        else:
            data = UserData(self.user)
            Application.__init__(self,form,data)
        
    def run(self,cmdstr=None):
        if cmdstr == None:
            cmdstr = self.form.getfirst("a","")
        if cmdstr != "sig":
            if self.data == None :
                logging.debug("run: self.data == None")
                return self.action_siq()
            server_session_id = self.data.get("session","[None]")
            client_session_id = self.cookie.get("session","[None]")
            if server_session_id != client_session_id :
                logging.debug("run: server_session_id=%s"%server_session_id)
                logging.debug("run: client_session_id=%s"%client_session_id)
                return self.action_siq()
        result = Application.run(self,cmdstr)
        if isinstance(result,str):
            self.message = "<div>%s</div>" % result
        if result :
            self.default()
        try:
            if self.data != None :
                self.data.commit()
        except MkdirLockError:
            pass
        return result

    def action_sig(self): ### Sign In ###
        user = self.form.getfirst("_user",None)
        if not self.data.auth(self.form.getfirst("_password","")):
            return self.action_siq()
        session_key = "%f" % random.random()
        put_cookie("session",session_key)
        put_cookie("user",user)
        self.data["session"] = session_key
        self.data.commit()
        if self.form.getfirst("_password",None) == "newuser" :
            return \
               "<h2>Warning!</h2><p>Your password is still '<b>newuser</b>'," + \
               'Please <a href="%s?a=chq">change</a> it as soon as posibble.</p>' % \
               self.myurl
        return True

    def action_chg(self): ### Change Password ###
        if not self.data.auth(self.form.getfirst("password","")):
            del_cookie("user")
            transfer_url(self.myurl)
            return False
        ### New password ###
        new1 = self.form.getfirst("password1","")
        new2 = self.form.getfirst("password2","")
        if new1 != new2 :
            return "Failed to change Password."
        self.data.chpasswd(new1)
        self.data.commit()
        return "Succeeded to change Password."

    def form_redirect(self):
        for key in self.form:
            if key[0] != "_":
                print '<input type="hidden" name="%s" value="%s" />' % \
                    ( cgi.escape(key) , cgi.escape(self.form.getfirst(key)) )
        if ("a" in self.form) and ("_a" not in self.form) :
            print '<input type="hidden" name="_a" value="%s" />' % \
                self.form.getfirst("a")
    
    def action_siq(self): ### Sign form ###
        del_cookie("user")
        del_cookie("session")
        print 'Content-Type: text/html; charset=%s' % UserApplication.charset
        print ''
        print '<html><head>'
        self.print_title()
        print '</head><body>'
        self.print_h1()
        self.print_man()
        self.print_message()

        print '<h2>Sign-in</h2>'
        print '<form action="%s" method="POST">' % self.myurl
        print     '<input type="hidden" name="a" value="sig" />'
        print     '<div>User:<input type="text" name="_user" value="" /></div>'
        print     '<div>Password:<input type="password" name="_password" value="" />'
        print '</div>'
        self.form_redirect()
        print     '<input type="submit" value="sign-in" />'
        print '</form>'

        print '<h2>New User</h2>'
        print '<form action="%s" method="POST">' % self.myurl
        print     '<input type="hidden" name="a" value="sig" />'
        print     '<div>User:<input type="text" name="_user" value="" /></div>'
        print     '<input type="hidden" name="_password" value="newuser" /></div>'
        print     '<input type="submit" value="create" />'
        self.form_redirect()
        print '</form>'
        print '</body></html>'
        return False

    def action_chq(self): ### Change Password form ###
        user = self.cookie["user"]
        print 'Content-Type: text/html; charset=%s' % UserApplication.charset
        print ''
        print '<html><head>'
        self.print_title()
        print '</head><body>'
        self.print_h1()
        print '<h2>Change Password</h2>'
        print '<form action="%s" method="POST">' % self.myurl
        print    '<div style="font-weight:bold">%s:</div>' % cgi.escape(user)
        print    '<input type="hidden" name="a" value="chg" />'
        print    '<div>Old password:<input type="password" name="password" /></div>'
        print    '<div>New password:<input type="password" name="password1" /></div>'
        print    '<div>(confirm): <input type="password" name="password2" /></div>'
        print    '<input type="submit" value="change" />'
        print '</form>'
        print '</body></html>'
        return False

    def print_menubar(self,*args):
        print 'Hello,<b>%s</b>' % cgi.escape( self.user )
        dem = '&gt;&gt;'
        for itr in (("Sign Out","siq") , ("Change Password","chq") ) , args :
            for i in itr:
                print ' %s <a href="%s?a=%s">%s</a>' \
                    % ( dem ,  self.myurl , i[1] , i[0] )
                dem = "|"
