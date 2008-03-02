#!/usr/bin/env python
# -*- coding:utf8 -*-

import os
import cgi
import cgitb ; cgitb.enable()
import urllib
from oreoref import *

class PinApplication(UserApplication): 
    manual_url = './doc/index.cgi?p=Onetime+Bookmark+Pin+%21"'
    def print_h1(self):
        print '<h1 align="center"><a href="%s"' % self.myurl
        print '><img src="/img/YourPin.png" border="0"'
        print 'alt="Onetime Bookmark Pin!" /></a></h1>' 
    def print_man(self):
        print '<a href="%s">What is this?</a>' % self.manual_url
    def print_title(self):
        print '<title>- Onetime Bookmark Pin! -</title>'

    def action_add(self): ### append url ###
        url = self.form.getfirst("addurl")
        ttl = self.form.getfirst("addttl",url)

        ### reject this script self ###
        if url == None or self.myurl in url :
            return "None"

        entry = self.data.get("entry",[])

        ### reject duplicate url ###
        if len(entry) > 0 and entry[-1][0] == url :
            return "URL exists."

        entry.append( (url,ttl) )
        self.data["entry"] = entry

        self.data["trashbox"] = \
            [ e for e in self.data.get("trashbox",[]) if e[0] != url ]

        return 'Succeed to append. <a href="#" onClick="JavaScript:closeMe()">close?</a>';

    def action_mov(self): ### goto url ###
        url = self.form.getfirst("url",None)

        entry = self.data.get("entry",[])
        if not entry :
            return "Not found data['entry']"
        no = None
        for i,e in enumerate(entry):
            if e[0] == url :
                no = i
                break
        else:
            return "Not found %s in entry" % cgi.escape(url)
        trashbox = self.data.get("trashbox",[])
        trashbox.append( entry[no] )
        if len(trashbox) > 3 :
            del trashbox[0]
        self.data["trashbox"] = trashbox

        del entry[no]
        self.data["entry"] = entry

        if self.form.getfirst("a","") == "mov" :
            transfer_url(url)
            return False
        else:
            return "Succeeded to remove %s" % cgi.escape(url)
    
    def action_csv(self):
        print 'Content-Type: text/csv; charset=%s' % UserApplication.charset
        print 'Content-Disposition: attachment; filename="export.csv"'
        print ''
        entry = self.data['entry']
        for e in entry:
            print "%s,%s" % (e[0],e[1])

    def default(self):
        newurl = self.form.getfirst('url',os.getenv('HTTP_REFERER'))
        if newurl and self.myurl in newurl :
            newurl = None
        title  = self.form.getfirst('ttl',newurl)
        
        put_cookie("user",self.user)
        print 'Content-type: text/html; chaset=%s' % UserApplication.charset
        print ''
        print '<html><head>'
        self.print_title()
        print '<script language="JavaScript"><!--'
        print "function settitle(){"
        if newurl and ("%u" in newurl) : ### for compatibility with old bookmarklet ###
            print " document.addform.addurl.value=unescape(document.hdnform.url.value);"
        else:
            print " document.addform.addurl.value=document.hdnform.url.value;"
        print " document.addform.addttl.value=unescape(document.hdnform.ttl.value);"
        print "}"
        print "function closeMe(){"
        print "    window.opener = window;"
        print "    var win = window.open(location.href,'_self');"
        print "    win.close();"
        print "}"
        print '// -->'
        print '</script>'
        if newurl :
            print '</head>'
            print '<body onload="settitle()">'
            print '<form name="hdnform">'
            print '<input type="hidden" name="url" value="%s">' % cgi.escape(newurl)
            print '<input type="hidden" name="ttl" value="%s">' % cgi.escape(title)
            print '</form>'
        else:
            print '</head>'
            print '<body>'

        ### Display user name ###
        self.print_menubar( ("Export(CSV)","csv") )
        print ' | <a href="%s">Manual</a>' % PinApplication.manual_url

        ### title ###
        self.print_h1()

        print '<p align="center">To setup your browser, please bookmarking'

        print '''<a href="javascript:window.location='%s?ttl='+escape(document.title)+'&url='+encodeURIComponent(location.href);undefined">Pin!</a> ''' % ( self.myurl )
    ##     print '''(popup version:<a href="javascript:window.open('%s?ttl='+escape(document.title)+'&url='+encodeURIComponent(location.href) , '_blank' , 'resizable=1,scrollbars=1,location=1');undefined">Pin!</a>)''' % self.myurl
        print '</p>'

        self.print_message()

        print '<h2>Add</h2>'
        print '<form name="addform" action="%s" method="POST">' % self.myurl
        print    '<dl><dt compact="compact">URL:</dt>'
        print    '<dd><input type="text" name="addurl" value="" size="80" /></dd>' 
        print    '<dt compact="compact">Title:</dt>'
        print    '<dd><input type="text" name="addttl" value="" size="80" /></dd>'
        print    '<dt><input type="submit" name="Submit" value="Pin!"></dt>'
        print '</dl>'
        print '<input type="hidden" name="a" value="add" />'
        print '</form>'

        print '<h2>Stack</h2>'
        print '<ol>'
        for e in reversed(self.data.get("entry",[])) :
            print '<li>'
            print cgi.escape( e[1] ) 
            print '<a href="%s?a=mov&amp;url=%s">[Pop!]</a>' % (
                self.myurl ,
                urllib.quote_plus( e[0] ) ,
            )
            print '</li>'
        print '</ol>'

        print '<h2>Trashbox</h2>'
        print '<ul>'
        for e,color in zip(reversed(self.data.get("trashbox",[])),("000","444","777")) :
            print '<li><a href="%s" style="color:#%s">%s</a>' % (
                cgi.escape( e[0] ) ,
                color ,
                cgi.escape( e[1] ) ,
            )
            print '<a href="%s?a=add&amp;ttl=%s;url=%s" style="color:#%s">[Restore]</a>'\
                % ( self.myurl ,
                urllib.quote_plus( e[1] ) ,
                urllib.quote_plus( e[0] ) ,
                color )
        print '</ul>'
        print '</body></html>'

if __name__ == '__main__':
    PinApplication( cgi.FieldStorage() ).run()
