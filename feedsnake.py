#!/usr/local/bin/python

import ConfigParser
import cgi
import cgitb ; cgitb.enable()
import codecs
import cookielib
from datetime import datetime,timedelta
import inspect
import md5
import os
import re
import string
import StringIO
import sys
import urllib
import urllib2
import urlparse

import feedparser

try:
    import sqlite3 as sqlite
except:
    from pysqlite2 import dbapi2 as sqlite

version="0.5"
user_agents='FeedSnake.py/%s' % version 

def feedcat(d,fd):
    def cdata(s):
        return '<![CDATA[%s]]>' % s.replace("]]>","]]]]><[!CDATA[>")
    def output(t):
        fd.write(t.strip()+"\r\n")

    output('<?xml version="1.0" encoding="UTF-8" ?>')
    output('<rdf:RDF')
    output(' xmlns="http://purl.org/rss/1.0/"')
    output(' xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"')
    output(' xmlns:content="http://purl.org/rss/1.0/modules/content/"')
    output(' xmlns:dc="http://purl.org/dc/elements/1.1/"')
    output(' xml:lang="ja">')
    output('<channel rdf:about="%s">' % cgi.escape(d["feed"]["link"]) )
    for tag,key in (
        ("title","title"),
        ("link","link"),
        ("description","description"),
    ):
        value = d["feed"].get(key)
        if value :
            output("<%s>%s</%s>" % ( tag, cgi.escape(value),tag ))

    output('<items>')
    output('<rdf:Seq>')

    for e in d["entries"]:
        id1 = e.get("id") or e.get("link")
        if id1:
            output('  <rdf:li rdf:resource="%s" />' % cgi.escape(id1))

    output('</rdf:Seq>')
    output('</items>')
    output('</channel>')

    for e in d["entries"]:
        id1 = e.get("id") or e.get("link")
        if id1 is None:
            continue
        output( '<item rdf:about="%s">' % cgi.escape(id1) )
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
                output("<%s>%s</%s>" % (tag,cgi.escape(e[key]),tag))

        for t in e.get("tags") or e.get("category") or []:
            output("<category>%s</category>" % cgi.escape(t.term))

        value = e.get("description")
        if value:
            output('<description>%s</description>' % cdata(value) )

        for c in e.get("content",[]):
            value = c.get("value")
            if value:
                output('<content:encoded>%s</content:encoded>' % cdata(value) )

        output('</item>')

    output("</rdf:RDF>")

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

def rel2abs_paths( link , content ):
    ahref_pattern = re.compile(
        r'(<a[^>]+href=")([^"]*)"' , re.DOTALL | re.IGNORECASE
    )
    imgsrc_pattern = re.compile(
        r'''(<img[^>]+src=['"])([^"']*)(["'])''' ,
        re.DOTALL | re.IGNORECASE
    )
    content = ahref_pattern.sub(
        lambda m:m.group(1) +
        urlparse.urljoin(link, m.group(2)) +
        '"',
        content
    )
    content = imgsrc_pattern.sub(
        lambda m:m.group(1) +
        urlparse.urljoin(link, m.group(2)) +
        m.group(3) ,
        content
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
        raise ConfigError("Invalid Entry number '%s'" % config["max_entries"] )
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
                cgi.escape(comment)
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
            u = browser(link)
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
            raise ConfigError("Invalid Regular Expression: %s"
                                    % cgi.escape(pattern1))

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

class FeedError(Exception):
    def __init__(self, description , link=None , title="Feed Error!"):
        self.dummyfeed = {
            "entries":[],
            "feed":{
                "link":link or "http://%s%s" %
                    (os.getenv("HTTP_HOST"),os.getenv("SCRIPT_NAME"))   ,
                "title":title ,
                "description":description 
            }
        }
    def __getitem__(self,key):
        return self.dummyfeed[key]

class ConfigError(FeedError):
    def __init__(self,message):
        FeedError.__init__(self,title="Configuration Error",description=message)

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
                raise FeedError(title="HTML Error" ,
                    description="HTML is not written with '%s'."
                                  " meta tag is wrong." % coding)
        else :
            coding="utf8"
            try:
                return html.decode( coding )
            except UnicodeDecodeError:
                raise FeedError(title="HTML Error" ,
                    description="not found meta tag. need htmlcode= in feedsnake.ini")

def html2feed(browser,config):
    index = config["index"]
    html = guess_coding( config , browser(index).read() )

    if "feed_title" in config:
        title = config["feed_title"]
    else :
        m = re.search(r'<title>(.*?)</title>',html,re.DOTALL|re.IGNORECASE)
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
        title = re.sub(r'<[^>]*>','',m.group("title"))
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
            id_ = md5.new( content.encode("utf8") ).hexdigest()

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

def interpret( conn , config ):
    cursor = conn.cursor()
    ddl(cursor)
    conn.commit()

    cursor.execute(
        "select content from t_output where feedname = ?  and update_dt > ?" ,
        ( config["feedname"] , hoursago(1) )
    )
    for rs in cursor :
        sys.stdout.write("Content-Type: application/xml; charset=utf-8\r\n\r\n")
        sys.stdout.write( rs[0].encode("utf8") )
        cursor.close()
        conn.close()
        return

    try:
        if "login" in config  or  "loginpost" in config:
            browser = login(config)
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
                raise ConfigError("Can not load feed class '%s'" % cgi.escape(classname) )
        elif "feed" in config:
            xml = browser( config["feed"] ).read()
            d = feedparser.parse( xml )
        elif "index" in config:
            d = html2feed(browser,config)
        else:
            raise ConfigError("not found item feed= or index=")

        if "feed" not in d  or "link" not in d["feed"]:
            raise ConfigError("Can not find the feed.")

        for key in "author", "title":
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
    except FeedError,err:
        conn.rollback()
        sys.stdout.write(
            "Status: 500 Internal Server Error\r\n"
            "Content-Type: application/xml; charset=utf-8\r\n"
            "\r\n"
        )
        feedcat( err , sys.stdout )
        return

    ### Save feed into cache ###
    buffer = StringIO.StringIO()
    feedcat( d , buffer )
    buffer = buffer.getvalue()
    cursor.execute("insert or replace into t_output "
                   "values(:feedname,:content,:update_dt)" ,
        ( config["feedname"] , buffer , hoursago(0) )
    )
    conn.commit()
    sys.stdout.write("Content-Type: application/xml; charset=utf-8\r\n\r\n")
    sys.stdout.write( buffer.encode("utf8") )

def menu( conn , config):
    cursor = conn.cursor()
    ddl(cursor)
    conn.commit()
    siteinfo = {}
    cursor.execute("select feedname,title from t_siteinfo")
    for rs in cursor:
        siteinfo[ rs[0] ] = rs[1]
    cursor.close()

    print 'Content-Type: text/html; charset=utf-8'
    print ''
    print '<html>'
    print '<head>'
    print '<meta http-equiv="Content-Type" content="text/html; charset=utf-8">'
    print '<title>FeedSnake Come On!</title>'
    print '</head>'
    print '<body><h1>FeedSnake Come On!</h1>'
    print '<ul>'
    for e in sorted( config.sections() ):
        print '<li><a href="%s?%s" rel="nofollow">%s</a></li>' % (
            os.getenv("SCRIPT_NAME") , cgi.escape(e) , 
            cgi.escape( siteinfo.get( e , "("+e+")" ).encode("utf8") )
        )
    print '</ul><p>Generated by feedsnake.py %s</p></body></html>' % version

def die(message="",status=""):
    if status:
        print "Status:",status
    print "Content-Type: text/html"
    print ""
    print "<html><body>"
    if status:
        print "<h1>%s</h1>" % cgi.escape(status)
    if message:
        print cgi.escape(message)
    print "</body></html>"

def main(inifname=None,index=True):
    configall = ConfigParser.ConfigParser()
    if inifname is None:
        inifname = re.sub( r"\.py$", ".ini" , inspect.getfile(main) )
    os.chdir( os.path.dirname(inifname) or "." )
    try:
        configall.read( inifname )
    except (ConfigParser.ParsingError,ConfigParser.MissingSectionHeaderError):
        die( message="<b>%s</b>: Invalid configuration(not ini format?)"
                % cgi.escape(inifname) ,
            status="500 Internal Server Error"
        )
        return

    conn = sqlite.connect("feedsnake.db")
    if not os.getenv("SCRIPT_NAME")  and  len(sys.argv) >= 2 :
        cursor = conn.cursor()
        for feedname in sys.argv[1:]:
            print "Content-Type: text/plain"
            print ""
            cursor.execute(
                "delete from t_output where feedname = :feedname" ,
                (feedname,)
            )
            print "%s: t_output deleted %d record(s)" % (feedname , cursor.rowcount)
            cursor.execute(
                "delete from t_cache where feedname = :feedname" ,
                (feedname,)
            )
            print "%s: t_cache deleted %d record(s)" % (feedname , cursor.rowcount)
        conn.commit()
        cursor.close()
        return

    feedname = os.getenv("QUERY_STRING")

    if feedname:
        if configall.has_section(feedname) :
            config = dict( configall.items(feedname) )
            config[ "feedname" ] = feedname
            try:
                interpret( conn , config )
            except urllib2.URLError,e:
                die(status="502 Bad Gateway", message=repr(e))
            except IOError,e:
                die(status="500 Internal Server Error" , message=repr(e) )
        else:
            die(status="404 Not Found")
    elif index:
        menu( conn , configall)
    else:
        die(status="403 Forbidden")
    conn.close()

if __name__ == '__main__':
    main()
