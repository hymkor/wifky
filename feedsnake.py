#!/usr/local/bin/python

import ConfigParser
import cgi
import cgitb
import cookielib
from datetime import datetime,timedelta
import inspect
try:
    import hashlib
except:
    import md5 as hashlib
import os
import re
import string
import StringIO
import sys
import urllib
import urllib2
import urlparse

try:
    import wsgiref.simple_server
    has_wsgiref = True
except:
    has_wsgiref = False

try:
    import feedparser
    has_feedparser = True
except:
    has_feedparser = False

try:
    import sqlite3 as sqlite
except:
    from pysqlite2 import dbapi2 as sqlite

version="0.5"
user_agents='FeedSnake.py/%s' % version
config_default={}

def err():
    """ for compatibility between Python 2.4 and 3.0"""
    return sys.exc_info()[1]

class Die(Exception):
    def __init__(self,message="",**kwarg):
        self.message=message
        self.info={ 
            "Status":"500 Internal Server Error" ,
            "Content-Type:":"text/html" ,
        }
        for key,val in kwarg.iteritems():
            self.info[ key.capitalize() ] = val
    def die(self,wsgi):
        wsgi.start( 
            self.info.get("Status","200 OK") ,
            self.info.items()
        )
        wsgi.write("<html><body>\n")
        if "Status" in self.info:
            wsgi.write("<h1>%s</h1>\n" % cgi.escape(self.info["Status"]))
        if self.message:
            wsgi.write( cgi.escape(self.message) )
        wsgi.write("\n</body></html>\n")

class ConfigError(Die):
    def __init__(self,message):
        Die.__init__(self, status="500 Configuration Error" , message=message)
class SiteError(Die):
    def __init__(self,message):
        Die.__init__(self, status="502 Bad Gateway" , message=message)

class WSGI(object):
    def __init__(self,environ,start_response):
        self.buf = []
        self.environ = environ
        self.start_response = start_response
    def __iter__(self):
        return self.buf.__iter__()
    def start(self,status="200 OK",header=[ ("Content-Type","text/html") ] ):
        self.start_response(status,header)
    def write(self,s):
        self.buf.append(s)
    def __getitem__(self,key):
        return self.environ[key]
    def get(self,key,default=None):
        return self.environ.get(key,default)
    def __contain__(self,key):
        return key in self.environ

re_script = re.compile(r"<script[^>]*>.*?</script>",re.DOTALL|re.IGNORECASE)
def cdata(s):
    return '<![CDATA[%s]]>' % \
        re_script.sub("",s).replace("]]>","]]]]><[!CDATA[>")

def feedcat(d):
    def output(t):
        fd.write(t.strip()+"\r\n")

    yield '<?xml version="1.0" encoding="UTF-8" ?>'
    yield '<rdf:RDF'
    yield ' xmlns="http://purl.org/rss/1.0/"'
    yield ' xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"'
    yield ' xmlns:content="http://purl.org/rss/1.0/modules/content/"'
    yield ' xmlns:dc="http://purl.org/dc/elements/1.1/"'
    yield ' xml:lang="ja">'
    yield '<channel rdf:about="%s">' % cgi.escape(d["feed"]["link"])
    for tag,key in (
        ("title","title"),
        ("link","link"),
        ("description","description"),
    ):
        value = d["feed"].get(key)
        if value :
            yield "<%s>%s</%s>" % ( tag, cgi.escape(value),tag )

    yield '<items>'
    yield '<rdf:Seq>'

    for e in d["entries"]:
        id1 = e.get("id") or e.get("link")
        if id1:
            yield '  <rdf:li rdf:resource="%s" />' % cgi.escape(id1)

    yield '</rdf:Seq>'
    yield '</items>'
    yield '</channel>'

    for e in d["entries"]:
        id1 = e.get("id") or e.get("link")
        if id1 is None:
            continue
        yield '<item rdf:about="%s">' % cgi.escape(id1)
        for tag,key in (
            ("title","title") ,
            ("link","link") ,
            ("lastBuildDate","updated") ,
            ("author","author") ,
            ("dc:author","author") ,
            ("dc:creator","author") ,
            ("dc:date","updated"),
        ):
            value = e.get(key)
            if value:
                yield "<%s>%s</%s>" % (tag,cgi.escape(e[key]),tag)

        for t in e.get("tags") or e.get("category") or []:
            yield "<category>%s</category>" % cgi.escape(t.term)

        value = e.get("description")
        if value:
            yield('<description>%s</description>' % cdata(value) )

        for c in e.get("content",[]):
            value = c.get("value")
            if value:
                yield '<content:encoded>%s</content:encoded>' % cdata(value)

        yield '</item>'

    yield "</rdf:RDF>"

def entry( title , link=None , id_=None ,content=None , updated=None , author=None ):
    if updated is None: updated = datetime.utcnow()
    if content :        content = content.strip()
    return {
        "title":title ,
        "id":id_ or link ,
        "link":link ,
        "author":author ,
        "description":content ,
        "content":[ {"value":content} ] ,
        "updated": updated.isoformat() ,
        "updated_parsed":updated.timetuple() ,
    }

def insert_message(d,message):
    error_cnt = d["error_cnt"] = d.get("error_cnt",0) + 1
    d["entries"].insert(0,
        entry(
            title="Feed Error! [%d]" % error_cnt ,
            link="http://example.com/#%d" % error_cnt ,
            author="FeedSnake System" ,
            content=message ,
        )
    )

re_ahref  = re.compile(r'(<a[^>]+href=")([^"]*)"', re.DOTALL | re.IGNORECASE)
re_imgsrc = re.compile(r'''(<img[^>]+src=['"])([^"']*)(["'])''',re.DOTALL|re.IGNORECASE)

def rel2abs_paths( link , content ):
    content = re_ahref.sub(
        lambda m:m.group(1) + urlparse.urljoin(link, m.group(2)) + '"', content
    )
    content = re_imgsrc.sub(
        lambda m:m.group(1) + urlparse.urljoin(link, m.group(2)) + m.group(3) , content
    )
    return content

def match2stamp(matchObj):
    if matchObj :
        dic = matchObj.groupdict()
        try:
            stamp = datetime(
                int(dic.get("year",datetime.now().year) ),
                int(dic["month"]) ,
                int(dic["day"]) ,
                int(dic.get("hour",0)),
                int(dic.get("minute",0)) ,
                int(dic.get("second",0)) )
            if stamp > datetime.now() + timedelta(days=1) :
                stamp = datetime(
                    int(dic.get("year",datetime.now().year) )-1,
                    int(dic["month"]) ,
                    int(dic["day"]) ,
                    int(dic.get("hour",0)),
                    int(dic.get("minute",0)) ,
                    int(dic.get("second",0)) )
        except KeyError:
            stamp = datetime.now()
    else:
        stamp = datetime.now()
    stamp += timedelta( hours=-9 )
    return stamp

def import_contents(browser , d , config , cursor ):
    try:
        max_entries = int(config.get("max_entries","5"))
    except ValueError:
        raise ConfigError(
            "Invalid Entry number :max_entries='%s'"
            % config["max_entries"] )
    del d["entries"][max_entries:]

    pattern = config["import"]
    template_re = string.Template( pattern )
    comment = config.get("comment")

    if comment:
        try:
            comment = re.compile(comment,re.DOTALL)
        except:
            raise ConfigError(
                "Invalid Regular Expression 'comment=%s'" %
                comment
            )

    cache_fail_cnt = 0

    ext_entries=[]
    for e in d.get("entries") or []:
        link = e["link"]

        cursor.execute("select content from t_cache where url=:url" , (link,) )
        for rs in cursor:
            pageall = rs[0]
        else:
            cache_fail_cnt += 1
            try:
                u = browser(re.sub(r"#[^#]*$","",link))
            except urllib2.URLError:
                raise SiteError("%s: url cound not open(%s)" % (link,str(err())))
            pageall = guess_coding(config,u.read())
            u.close()

            cursor.execute("insert or replace into t_cache "
                           "values(:url,:feedname,:content,:update_dt)" ,
                ( link , config["feedname"] , pageall , hoursago(0) )
            )

        ### main contents ###

        parsed_link = urlparse.urlparse(link)
        pattern1 = template_re.safe_substitute(
                        {
                            "url":link ,
                            "scheme":parsed_link[0] ,
                            "netloc":parsed_link[1] ,
                            "path":parsed_link[2] ,
                            "parameters":parsed_link[3],
                            "query":parsed_link[4] ,
                            "fragment":parsed_link[5] ,
                        }
        )
        try:
            m = re.search( pattern1 , pageall , re.DOTALL )
            if m :
                content = rel2abs_paths( link , m.group(1).strip() )
                e.setdefault("content",[]).append({ "value":content })
                e["description"] = content
            else :
                e["description"] = "not found: " + cgi.escape(pattern1)
        except:
            raise ConfigError("Invalid Regular Expression: %s" % pattern1)

        if comment :
            try:
                for i,m in enumerate(comment.finditer(pageall)):
                    ext_entries.append(
                        entry(
                            title="Comment #%d for %s" % ( 1+i , e.get("title","") ) ,
                            link=link + "#" + m.group("id") ,
                            author = m.group("author") ,
                            content = m.group("content") ,
                            updated = match2stamp(m) ,
                        )
                    )
            except IndexError:
                raise ConfigError(
                        "Invalid regular-expression(IndexError) for comment: "
                        "It needs (?P<id>..) , (?P<content>..) , "
                        "(?P<author>..) , (?P<month>..) , and (?<day>..)"
                    )

    d["entries"].extend(ext_entries)

    d["feed"]["description"] = "%s\nnew %d articles imported" % (
            d["feed"].get("description","") , cache_fail_cnt )

def deny(d,key,patterns):
    patterns = patterns.split()
    newentry = []
    for e in d["entries"]:
        for p in patterns:
            if p in e[key]:
                break
        else:
            newentry.append( e )
    d["entries"] = newentry

def accept(d,key,patterns):
    patterns = patterns.split()
    newentry = []
    for e in d["entries"]:
        for p in patterns:
            if p in e[key]:
                newentry.append( e )
                break
    d["entries"] = newentry

def login(config):
    def parse_param(text):
        loginpost = re.split(r"[\s\;\&\?]+",text)
        url = loginpost.pop(0)
        param = {}
        for e in loginpost:
            p = e.split("=",2)
            param[ p[0] ] = p[1]
        return url,param
    cookiejar = cookielib.CookieJar()
    cookie_processor = urllib2.HTTPCookieProcessor( cookiejar )
    opener = urllib2.build_opener( cookie_processor )
    opener.addheaders = [ ('User-agent', user_agents )]

    if "loginpost" in config:
        loginurl,param = parse_param( config["loginpost"])
        opener.open(
            loginurl , urllib.urlencode( param )
        ).close()
    elif "login" in config:
        loginurl,param = parse_param( config["login"])
        opener.open(
            "%s?%s" % ( loginurl , urllib.urlencode( param ))
        ).close()
    return lambda *url:opener.open(*url)

def nologin(config):
    opener = urllib2.build_opener()
    opener.addheaders = [ ('User-agent', user_agents )]
    return lambda *url:opener.open(*url)

def hoursago(n=0):
    dt = datetime.utcnow()
    if n:
        dt -= timedelta(hours=n)
    return dt.strftime("%Y%m%d%H%M%S")

def ymdhms2datetime(dt): ### for Python 2.4 which does not have no datetime.strptime() ###
    return datetime(
        year   = int(dt[ 0: 4],10) ,
        month  = int(dt[ 4: 6],10) ,
        day    = int(dt[ 6: 8],10) ,
        hour   = int(dt[ 8:10],10) ,
        minute = int(dt[10:12],10) ,
        second = int(dt[12:14],10) ,
    )

def guess_coding(config,html):
    if "htmlcode" in config:
        coding = config["htmlcode"]
        try:
            return html.decode( coding )
        except UnicodeDecodeError:
            raise ConfigError("HTML is not written with '%s'" % coding)
    else:
        m = re.search(r'<meta[^>]*?\bcharset=([^"]+)"',html,re.IGNORECASE|re.DOTALL)
        if m :
            coding=m.group(1).lower()
            try:
                return html.decode( coding )
            except UnicodeDecodeError:
                raise SiteError(
                    "Decode Error. Meta-tag specified wrong encoding(%s)"
                    % coding )
        else :
            coding="utf8"
            try:
                return html.decode( coding )
            except UnicodeDecodeError:
                raise ConfigError("not found meta tag. need htmlcode= in feedsnake.ini")

def html2feed(browser,config):
    index = config["index"]
    try:
        html = guess_coding( config , browser(index).read() )
    except urllib2.URLError:
        raise SiteError("%s: url cound not open(%s)" % (index,str(err())))

    if "feed_title" in config:
        title = config["feed_title"].decode("utf8")
    else :
        m = re.search(r'<title[^>]*>(.*?)</title>',html,re.DOTALL|re.IGNORECASE)
        if m:
            title = m.group(1).replace("&lt;","<")\
                    .replace("&gt;",">").replace("&amp;","&")
        else :
            title = "Feed of " + index

    d = {
        "feed":{
            "link":index ,
            "title":title ,
            "description":"",
        }
    }

    entries = []
    pattern_str = config.get(
        'inline' ,
        r'<a[^>]+?href="(?P<url>[^"]*)"[^>]*>(?P<title>.*?)</a>'
    ).decode("utf8")
    re_pattern = re.compile( pattern_str , re.DOTALL|re.IGNORECASE )

    for m in re_pattern.finditer( html ):
        try:
            title = re.sub(r'<[^>]*>','',m.group("title"))
        except IndexError:
            raise ConfigError("(?P<title>...) is undefined in inline=...")
        if not title :
            continue

        if u"(?P<content>" in pattern_str:
            content = rel2abs_paths( index , m.group("content") )
        else:
            content = None

        if "(?P<url>" in pattern_str:
            id_ = link = urlparse.urljoin(index , m.group("url")).replace("&amp;","&")
        elif not content:
            continue
        else:
            link = index
            id_ = hashlib.md5( content.encode("utf8") ).hexdigest()

        entries.append(
            entry(
                id_ = id_ ,
                link = link ,
                title = title ,
                content = content ,
                updated = match2stamp(m) ,
            )
        )
    d["entries"] = entries
    return d

feed_processor_list = {}

def feed_processor(func):
    feed_processor_list[ func.func_name ] = func
    return func

def ddl( cursor ):
    try:
        cursor.execute("""
            create table t_cache (
                url       text primary key ,
                feedname  text ,
                content   text ,
                update_dt text not null
            )
        """)
    except sqlite.OperationalError:
        pass
    try:
        cursor.execute("""
            create table t_output (
                feedname  text primary key ,
                content   text ,
                update_dt text not null
            )
        """)
    except sqlite.OperationalError:
        pass
    try:
        cursor.execute("""
            create table t_siteinfo (
                feedname    text primary key ,
                url         text not null ,
                title       text ,
                description text
            );
        """)
    except sqlite.OperationalError:
        pass

def interpret( conn , config , wsgi ):
    if "forward" in config:
        raise Die(
            status="304 Moved." ,
            location=config["forward"] ,
        )

    cursor = conn.cursor()
    ddl(cursor)
    conn.commit()

    cursor.execute(
        "select content from t_output where feedname = :feedname "
        " and update_dt > :start" ,
        ( config["feedname"] , hoursago(1) )
    )
    for rs in cursor :
        wsgi.start( "200 OK" ,
            [ ("Content-Type","application/xml; charset=utf-8") ]
        )
        wsgi.write(rs[0].encode("utf8"))
        wsgi.write("\n")
        cursor.close()
        conn.close()
        return

    if "login" in config  or  "loginpost" in config:
        try:
            browser = login(config)
        except urllib2.URLError:
            raise SiteError("url cound not open(%s)" % err())
    else:
        browser = nologin(config)

    if "class" in config:
        classname = config["class"]
        if "@" in classname :
            classname,plugin = classname.split("@",2)
            execfile(plugin+".py",globals(),locals())
        try:
            d = feed_processor_list[ classname ](browser,config,conn)
        except IOError:
            raise ConfigError("Can not load feed class '%s'" % classname )
    elif "feed" in config:
        if not has_feedparser :
            raise ConfigError(
                "Please install Universal Feed Parser "
                "(http://www.feedparser.org/) "
                "to read RSS/Atom Feeds"
            )
        try:
            xml = browser( config["feed"] ).read()
        except urllib2.URLError:
            raise SiteError("%s: url cound not open(%s)" % (config["feed"],str(err())))
        d = feedparser.parse( xml )
    elif "index" in config:
        d = html2feed(browser,config)
    else:
        raise ConfigError("not found item feed= or index=")

    if "feed" not in d  or "link" not in d["feed"]:
        raise ConfigError("Can not find the feed.")

    for key in "author","title","link":
        if key in config:
            try:
                accept(d,key,config[key].decode("utf8"))
            except UnicodeDecodeError:
                raise ConfigError("UnicodeDecodeError on %s=.." % key)
        if "x"+key in config:
            try:
                deny(d,key,config["x"+key].decode("utf8"))
            except UnicodeDecodeError:
                raise ConfigError("UnicodeDecodeError on x%s=.." % key)

    if "import" in config:
        import_contents(browser , d, config , cursor)

    ### Expire cache ###
    expire_dt = hoursago(7*24)
    cursor.execute("delete from t_cache  where update_dt < :expire_dt" ,(expire_dt,))
    cursor.execute("delete from t_output where update_dt < :expire_dt" ,(expire_dt,))

    ### update site info ###
    cursor.execute("insert or replace into t_siteinfo "
                   "values(:feedname,:url,:title,:description)" ,
        ( config["feedname"] ,
          d["feed"]["link"] ,
          d["feed"].get("title","no title") ,
          d["feed"].get("description","") ,
        )
    )

    ### Save feed into cache ###
    buffer = StringIO.StringIO()
    for line in feedcat( d ):
        buffer.write( line.strip() + "\r\n" )
    buffer = buffer.getvalue()
    cursor.execute("insert or replace into t_output "
                   "values(:feedname,:content,:update_dt)" ,
        ( config["feedname"] , buffer , hoursago(0) )
    )
    conn.commit()

    wsgi.start(
        '200 OK' ,
        [ ("Content-Type","application/xml; charset=utf-8") ]
    )
    wsgi.write(buffer.encode("utf8"))

def menu( wsgi , conn , config):
    cursor = conn.cursor()
    ddl(cursor)
    conn.commit()
    siteinfo = {}
    cursor.execute("select feedname,title from t_siteinfo")
    for rs in cursor:
        siteinfo[ rs[0] ] = rs[1]
    cursor.close()

    wsgi.start()
    wsgi.write( '''<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
<title>FeedSnake Come On!</title>
</head>
<body><h1>FeedSnake Come On!</h1>
<ul>''' )
    for e in sorted( config.sections() ):
        try:
            if config.getboolean( e , "hidden" ):
                continue
        except (ValueError,ConfigParser.NoOptionError):
            pass

        wsgi.write( '<li><a href="%s?%s" rel="nofollow">%s</a>\n' % (
                wsgi.get("SCRIPT_NAME") or "/" , cgi.escape(e) ,
                cgi.escape( siteinfo.get( e , "("+e+")" ).encode("utf8")) ) )
        wsgi.write( '<a href="%s?-%s" rel="nofollow">[x]</a></li>\n' % (
                wsgi.get("SCRIPT_NAME") or "/" , cgi.escape(e) ) )
    wsgi.write( '</ul><p>Generated by feedsnake.py %s</p></body></html>\n' % version )

def cacheoff( wsgi , conn , configall , feedname ):
    if configall.has_section(feedname):
        wsgi.start()
        cursor = conn.cursor()
        cursor.execute(
            "delete from t_output where feedname = :feedname" ,
            (feedname,)
        )
        script_name = wsgi.get("SCRIPT_NAME") or "/"
        if "?" in script_name:
            script_name = script_name[:script_name.index("?")]
        wsgi.write("<html><head>\n")
        wsgi.write('<meta http-equiv="refresh" content="1;URL=%s" />\n' 
            % script_name )
        wsgi.write( "</head><body><ul>\n")
        wsgi.write( "<li>%s: t_output deleted %d record(s)</li>\n" %  \
            (feedname , cursor.rowcount) )
        cursor.execute(
            "delete from t_cache where feedname = :feedname" ,
            (feedname,)
        )
        wsgi.write( "<li>%s: t_cache deleted %d record(s)</li>\n" % \
            (feedname , cursor.rowcount) )
        wsgi.write( "</ul></body></html>\n")
        conn.commit()
        return wsgi
    else:
        raise Die(status="404 Not Found",message="section: "+feedname)

def application(
    environ , start_response , 
    inifname=None,
    menuSwitch=True
):
    wsgi = WSGI(environ,start_response)
    try:
        configall = ConfigParser.ConfigParser(config_default)
        if inifname is None:
            inifname = re.sub( r"\.py$", ".ini" , inspect.getfile(application) )
        os.chdir( os.path.dirname(inifname) or "." )
        try:
            configall.read( inifname )
        except (ConfigParser.ParsingError,ConfigParser.MissingSectionHeaderError):
            raise ConfigError(repr(err()))

        conn = sqlite.connect("feedsnake.db")
        feedname = wsgi.get("QUERY_STRING")

        if feedname:
            if feedname[0] == "-" :
                cacheoff( wsgi , conn , configall , feedname[1:] )
            elif configall.has_section(feedname) :
                config = dict( configall.items(feedname) )
                config[ "feedname" ] = feedname
                interpret( conn , config , wsgi )
            else:
                raise Die(status="404 Not Found",message="section: "+feedname)
        elif menuSwitch:
            menu( wsgi , conn , configall)
        else:
            raise Die(status="403 Forbidden")
        conn.close()
    except Die:
        err().die(wsgi)
    return wsgi

def main(**kwarg):
    def _start_response(status,headers):
        print "Status:",status
        for key,val in headers:
            print(key+": "+val)
        print("")

    cgitb.enable()
    for line in application(os.environ,start_response=_start_response,**kwarg):
        print line

if __name__ == '__main__':
    portno = None
    if len(sys.argv) >= 2:
        for e in sys.argv[1:]:
            pair = e.split("=",1)
            if len(pair) >= 2 :
                config_default[ pair[0] ] = pair[1]
            elif re.search(r"^\d+$",e):
                portno = int(e)
    if portno and has_wsgiref:
        wsgiref.simple_server.make_server(
            "",portno,application
        ).serve_forever()
    else:
        main()
