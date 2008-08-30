#!/usr/local/bin/python

import ConfigParser
import cgi
import cgitb ; cgitb.enable()
import codecs
import cookielib
import datetime
import inspect
import md5
import os
import re
import sys
import urllib
import urllib2
import urlparse

import feedparser

try:
    import sqlite3 as sqlite
except:
    from pysqlite2 import dbapi2 as sqlite

version="0.4"

def feedcat(d,fd):
    def cdata(s):
        return '<![CDATA[%s]]>' % s.replace("]]>","]]]]><[!CDATA[>")
    fd = codecs.getwriter('utf_8')(fd)
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

def http_output(d):
    sys.stdout.write("Content-Type: application/xml; charset=utf-8\r\n\r\n")
    feedcat(d,sys.stdout)

def entry( title , link=None , id_=None ,content=None , updated=None , author=None ):
    if updated is None: updated = datetime.datetime.utcnow()
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
    content = re.sub(
        r'(<a[^>]+href=")([^"]*)"' ,
        lambda m:m.group(1) +
        urlparse.urljoin(link, m.group(2)) +
        '"',
        content
    )
    content = re.sub(
        r'''(<img[^>]+src=['"])([^"']*)(["'])''' ,
        lambda m:m.group(1) +
        urlparse.urljoin(link, m.group(2)) +
        m.group(3) ,
        content
    )
    return content

def match2stamp(matchObj):
    if matchObj :
        dic = matchObj.groupdict()
        stamp = datetime.datetime(
            int(dic.get("year",datetime.datetime.now().year) ),
            int(dic["month"]) ,
            int(dic["day"]) ,
            int(dic.get("hour",0)),
            int(dic.get("minute",0)) ,
            int(dic.get("second",0)) )
    else:
        stamp = datetime.datetime.now()
    stamp += datetime.timedelta( hours=-9 )
    return stamp

def feednm2cachefn(feedname):
    return feedname + ".cache"

def import_contents(browser , d , config , conn ):
    try:
        max_entries = int(config.get("max_entries","5"))
    except ValueError:
        insert_message(d,"Invalid Entry number '%s'" % config["max_entries"] )
        max_entries = 5
    del d["entries"][max_entries:]

    coding  = config.get("htmlcode")
    pattern = config["import"]
    comment = config.get("comment")

    cursor = conn.cursor()

    try:
        pattern = re.compile(pattern,re.DOTALL)
    except:
        insert_message(d,
            "Invalid Regular Expression 'import=%s'" % 
                            cgi.escape(pattern) )
        return
    if comment:
        try:
            comment = re.compile(comment,re.DOTALL)
        except:
            insert_message(d,
                "Invalid Regular Expression 'comment=%s'" %
                cgi.escape(comment)
            )
            comment = None

    cache_fail_cnt = 0

    ext_entries=[]
    for e in d.get("entries") or []:
        link = e["link"]
        pageall = None
        for rs in select_cache(cursor,link):
            pageall = rs[1]

        if pageall is None:
            cache_fail_cnt += 1
            u = browser(link)
            pageall = u.read()
            u.close()
            if coding is None:
                m = re.search(r'<meta[^>]*?\bcharset=([^"]+)"',pageall,re.IGNORECASE)
                if m:
                    coding = m.group(1).lower()
                else:
                    coding = "utf8"
            try:
                pageall = pageall.decode(coding)
            except UnicodeDecodeError:
                pageall = u""
            
            insert_cache(cursor,link,pageall)
            conn.commit()

        ### main contents ###
        m = pattern.search( pageall )
        if m :
            content = rel2abs_paths( link , m.group(1).strip() )
            e.setdefault("content",[]).append({ "value":content })
            e["description"] = content

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
                insert_message(d,
                    cgi.escape(
                        "Invalid regular-expression(IndexError) for comment: "
                        "It needs (?P<id>..) , (?P<content>..) , "
                        "(?P<author>..) , (?P<month>..) , and (?<day>..)"
                    )
                )
                comment = None

    d["entries"].extend(ext_entries)

    d["feed"]["description"] = "%s (cache failed %d times)" % (
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

def error_feed(message="feed not found."):
    return {
        "entries":[],
        "feed":{
            "link":"http://example.com",
            "title":"Feed Error!",
            "description":message ,
        }
    }

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
    cookie_processor = urllib2.HTTPCookieProcessor(cookiejar)
    opener  = urllib2.build_opener( cookie_processor )
    browser = lambda *url:opener.open(*url)

    if "loginpost" in config:
        url,param = parse_param(config["loginpost"])
        browser( url , urllib.urlencode( param ) ).close()
    elif "login" in config:
        url,param = parse_param(config["login"])
        browser( "%s?%s" % ( url , urllib.urlencode( param )) ).close()
    return browser

def ymdhms():
    return datetime.datetime.utcnow().strftime("%Y%m%d%H%M%S")

def select_cache(cursor,url):
    for rs in cursor.execute("select * from t_cache where url=?",(url,)):
        yield rs

def update_cache(cursor,url,html):
    cursor.execute("update t_cache set content=? , update_dt=? where url = ?" ,
        (html,ymdhms(),url) 
    )
def insert_cache(cursor,url,html):
    cursor.execute("insert into t_cache values(?,?,?)" ,
        (url,html,ymdhms() )
    )

def keep_cache(cursor,url,html):
    pass

def is_enough_new(dt):
    return dt > ( datetime.datetime.utcnow() 
                - datetime.timedelta(hours=1)
                ).strftime("%Y%m%d%H%M%S")

def html2feed(browser,config,conn):
    index = config["index"]

    cursor = conn.cursor()

    cache_fail_cnt = 0
    cache_action = insert_cache
    update_dt = ymdhms()
    prev_html = ""
    for rs in select_cache(cursor,index):
        if is_enough_new(rs[2]):
            html = rs[1]
            update_dt = rs[2]
            cache_action = keep_cache
            break
        else:
            ### Cache is Old ###
            prev_html = rs[1]
            update_dt = rs[2]
            cache_action = update_cache
    else:
        ### Cache does not hit. ###
        cache_fail_cnt += 1
        fd    = browser(index)
        html  = fd.read()
        fd.close()

        m = re.search(r'<meta[^>]*?\bcharset=([^"]+)"',html,re.IGNORECASE|re.DOTALL)
        if m :
            coding=m.group(1).lower()
        elif "htmlcode" in config:
            coding=config["htmlcode"]
        else :
            coding="utf8"
        html = html.decode( coding )

    if html != prev_html :
        update_dt = ymdhms()

    if "feed_title" in config:
        title = config["feed_title"]
    else :
        m = re.search(r'<title>(.*?)</title>',html,re.DOTALL|re.IGNORECASE)
        if m:
            title = m.group(1)
        else :
            title = "Feed of " + index

    d = {
        "feed":{
            "link":index ,
            "title":title ,
            "description":"(cache failed %d times)" % cache_fail_cnt
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
            id_ = link = urlparse.urljoin( index , m.group("url") )
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
                updated = datetime.datetime.strptime(update_dt,"%Y%m%d%H%M%S")
            )
        )
    d["entries"] = entries

    cache_action(cursor,index,html)
    conn.commit()

    return d

def read_feed( conn , browser , url ):
    cursor = conn.cursor()
    for rs in select_cache( cursor , url ):
        if is_enough_new(rs[2]) :
            xml = rs[1].decode("base64")
        else:
            fd = browser( url )
            xml = fd.read()
            fd.close()
            update_cache( cursor , url , xml.encode("base64") )
            conn.commit()
        break
    else:
        ### Cache does not hit ###
        fd = browser( url )
        xml = fd.read()
        fd.close()
        insert_cache( cursor , url , xml.encode("base64") )
        conn.commit()
    return xml

feed_processor_list = {}

def feed_processor(func):
    feed_processor_list[ func.func_name ] = func
    return func

def interpret( config ):
    if "login" in config  or  "loginpost" in config:
        browser = login(config)
    else:
        browser = urllib.urlopen

    conn = sqlite.connect("feedsnake.db")

    if "class" in config:
        classname = config["class"]
        if "@" in classname :
            classname,plugin = classname.split("@",2)
            execfile(plugin+".py",globals(),locals())
        try:
            d = feed_processor_list[ classname ](browser,config)
        except IOError:
            d = error_feed( "Can not load feed class '%s'" % cgi.escape(classname) )
        except Exception,e:
            d = error_feed( cgi.escape(str(e)) )
    elif "feed" in config:
        xml = read_feed( conn , browser , config["feed"] )
        d = feedparser.parse( xml )
    elif "index" in config:
        d = html2feed(browser,config,conn)
    else:
        d = error_feed()

    if "feed" not in d  or "link" not in d["feed"]:
        d = error_feed( "Can not find the feed." )

    for key in "author", "title":
        if key in config:
            try:
                accept(d,key,config[key].decode("utf8"))
            except UnicodeDecodeError:
                insert_message(d,"UnicodeDecodeError on %s=.." % key)
        if "x"+key in config:
            try:
                deny(d,key,config["x"+key].decode("utf8"))
            except UnicodeDecodeError:
                insert_message(d,"UnicodeDecodeError on x%s=.." % key)

    if "import" in config:
        import_contents(browser , d, config , conn)

    conn.close()

    http_output(d)

def menu(config):
    print 'Content-Type: text/html; charset=utf-8'
    print ''
    print '<html>'
    print '<head>'
    print '<meta http-equiv="Content-Type" content="text/html; charset=utf-8">'
    print '<title>FeedSnake Come On!</title>'
    print '</head>'
    print '<body><h1>FeedSnake Come On!</h1>'
    print '<ul>'
    for e in config.sections():
        print '<li><a href="%s?%s" rel="nofollow">%s</a> ' \
              ' <small>[<a href="%s?-%s" rel="nofollow">x</a>]</small></li>' % (
            os.getenv("SCRIPT_NAME") ,
            cgi.escape(e) ,
            cgi.escape(e) ,
            os.getenv("SCRIPT_NAME") ,
            cgi.escape(e) ,
        )
    print '</ul><p>Generated by feedsnake.py %s</p></body></html>' % version

def die(message=""):
    print "Content-Type: text/html"
    print ""
    print "<html><body>%s</body></html>" % message

def main(inifname=None,index=True):
    configall = ConfigParser.ConfigParser()
    if inifname is None:
        inifname = re.sub( r"\.py$", ".ini" , inspect.getfile(main) )
    os.chdir( os.path.dirname(inifname) or "." )
    try:
        configall.read( inifname )
    except (ConfigParser.ParsingError,ConfigParser.MissingSectionHeaderError):
        die("<b>%s</b>: Invalid configuration(not ini format?)" \
            % cgi.escape(inifname) )
        return

    feedname = os.getenv("QUERY_STRING")
    if feedname and feedname[0] == '-' :
        cachefn = feednm2cachefn(feedname[1:])
        if configall.has_section(feedname[1:]) and os.path.exists(cachefn):
            os.remove(cachefn)
        feedname = None

    if feedname and configall.has_section(feedname) :
        config = dict( configall.items(feedname) )
        config[ "feedname" ] = feedname
        interpret( config )
    elif index:
        menu(configall)
    else:
        die()

if __name__ == '__main__':
    main()
