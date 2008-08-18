#!/usr/local/bin/python

import ConfigParser
import cPickle as pickle
import cgi
import cgitb ; cgitb.enable()
import codecs
import cookielib
import datetime
import inspect
import os
import re
import sys
import urllib
import urllib2
import urlparse

import feedparser

version="0.3"

def feedcat(d,fd):
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
        if key in d["feed"]:
            output("<%s>%s</%s>" % ( tag, cgi.escape( d["feed"][key] ),tag ))

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
            if key in e :
                output("<%s>%s</%s>" % (tag,cgi.escape(e[key]),tag))

        for t in e.get("tags") or e.get("category") or []:
            output("<category>%s</category>" % cgi.escape(t.term))

        if "description" in e:
            output('<description><![CDATA[%s]]></description>' % e["description"] )

        for c in e.get("content",[]):
            if c["value"]:
                output('<content:encoded><![CDATA[%s]]></content:encoded>' % c["value"] )

        output('</item>')

    output("</rdf:RDF>")

def http_output(d):
    sys.stdout.write("Content-Type: application/xml; charset=utf-8\r\n\r\n")
    feedcat(d,sys.stdout)

def entry( title , link , author , content , updated=None ):
    if updated is None:
        updated = datetime.utcnow()
    return {
        "title":title ,
        "id":link ,
        "link":link , 
        "author":author ,
        "description":content ,
        "content":[ {"value":content} ] ,
        "updated": updated.isoformat() ,
        "updated_parsed":updated.timetuple() ,
    }

error_cnt=0
def insert_message_as_feed(d,message):
    global error_cnt
    error_cnt += 1
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
        r'(<a[^>]+href=")([^."]*)"' ,
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

def import_contents(d, config):
    cachefn = config.get("cache") 
    coding  = config.get("htmlcode")
    pattern = config["import"]
    comment  = config.get("comment")

    cache = {}
    new_cache = {}

    if cachefn:
        try:
            fd = file(cachefn)
            cache = pickle.load( fd )
            fd.close()
        except:
            pass
    try:
        pattern = re.compile(pattern,re.DOTALL)
    except:
        insert_message_as_feed(d,
            "Invalid Regular Expression 'import=%s'" % cgi.escape(pattern) 
        )
        return
    if comment:
        try:
            comment = re.compile(comment,re.DOTALL)
        except:
            insert_message_as_feed(d,
                "Invalid Regular Expression 'comment=%s'" % cgi.escape(comment) 
            )
            comment = None

    cache_fail_cnt = 0

    ext_entries=[]
    for e in d.get("entries") or []:
        link = e["link"]
        if link in cache and cache.get((link,"mark"))==e.get("_comment_cnt") :
            pageall = cache[link]
        else:
            cache_fail_cnt += 1
            u = d.urlopen(link)
            pageall = u.read()
            u.close()
            try:
                if coding is None:
                    m = re.search(r'<meta[^>]*?\bcharset=([^"]+)"',pageall,re.IGNORECASE)
                    if m:
                        coding = m.group(1).lower()
                    else:
                        coding = "utf8"

                pageall = pageall.decode(coding)
            except UnicodeDecodeError:
                content = u""
        new_cache[link] = pageall
        new_cache[link,"mark"] = e.get("_comment_cnt")

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
                insert_message_as_feed(d,
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

    if cache_fail_cnt > 0 and cachefn:
        try:
            fd = file(cachefn,"w")
            pickle.dump( new_cache , fd )
            fd.close()
        except IOError:
            insert_message_as_feed(d,
                "could not update cache file '%s'" %
                cgi.escape(cachefn)
            )

def exclude(d,pattern,key):
    try:
        pattern = re.compile(pattern)
    except:
        insert_message_as_feed(d,
            "Invalid Regular Expression '%s'" %
                cgi.escape(pattern) 
        )
        return
    d["entries"] = [ e for e in d["entries"] if not pattern.search(e[key]) ]
       
def error_feed(config,message="feed not found."):
    return {
        "entries":[],
        "feed":{
            "link":"http://example.com",
            "title":"Feed Error!",
            "description":message ,
        }
    }

class norm_feed(dict):
    def __init__(self,config):
        dict.__init__(self,feedparser.parse( config["feed"] ) )
    def urlopen(self, *url ):
        return urllib.urlopen( *url )

def parse_param(text):
    loginpost = re.split(r"[\s\;\&\?]+",text)
    url = loginpost.pop(0)
    param = {}
    for e in loginpost:
        p = e.split("=",2)
        param[ p[0] ] = p[1]
    return url,param

class sns_feed(dict):
    def __init__(self,config):
        self.cookiejar = cookielib.CookieJar()
        self.cookie_processor = urllib2.HTTPCookieProcessor(self.cookiejar)
        self.opener = urllib2.build_opener( self.cookie_processor )

        if "loginpost" in config:
            url,param = parse_param(config["loginpost"])
            self.urlopen( url , urllib.urlencode( param ) ).close()
        elif "login" in config:
            url,param = parse_param(config["login"])
            self.urlopen( "%s?%s" % ( url , urllib.urlencode( param )) ).close()

    def urlopen(self, *url ):
        return self.opener.open( *url )
    def parse(self, url):
        return feedparser.parse(url,handlers=[self.cookie_processor])

class mixi_feed(sns_feed):
    def __init__(self,config):
        sns_feed.__init__(self,config)
        self.update( self.parse(config["feed"]) )

def default_feed(config):
    if "login" in config  or  "loginpost" in config:
        if "feed" in config:
            return mixi_feed(config)
    else:
        if "feed" in config:
            return norm_feed(config)
    return error_feed(config)

feed_class = {
    "feed":norm_feed ,
    "mixi":mixi_feed ,
    "default":default_feed ,
}

def interpret( config ):
    classname = config.get("class","default")
    try:
        if "@" in classname :
            classname,plugin = classname.split("@",2)
            execfile(plugin+".py",globals(),locals())
        d = feed_class.get(classname, error_feed)( config )
        if "feed" not in d  or "link" not in d["feed"]:
            d = error_feed( config , "Can not find the feed." )
    except IOError:
        d = error_feed( config , "Can not load feed class '%s'" % classname )

    if "exclude" in config:
        exclude(d,config["exclude"],"title")

    try:
        max_entries = int(config.get("max_entries","5"))
    except ValueError:
        insert_message_as_feed(d,"Invalid Entry number '%s'" % config["max_entries"] )
        max_entries = 5
    del d["entries"][max_entries:]

    if "import" in config:
        import_contents( d , config )
    http_output(d)

def menu(config):
    print "Content-Type: text/html"
    print ""
    print "<html>"
    print "<title>FeedSnake Come On!</title>"
    print "<body><h1>FeedSnake Come On!</h1>"
    print "<ul>"
    for e in config.sections():
        print '<li><a href="%s?%s">%s</a></li>' % (
            os.getenv("SCRIPT_NAME") ,
            cgi.escape(e) ,
            cgi.escape(e)
        )
    print "</ul><p>Generated by feedsnake.py %s</p></body></html>" % version

def die(message=""):
    print "Content-Type: text/html"
    print ""
    print "<html><body>%s</body></html>" % message

def main(inifname=None,index=True):
    config = ConfigParser.ConfigParser()
    if inifname is None:
        inifname = re.sub( r"\.py$", ".ini" , inspect.getfile(main) )
    os.chdir( os.path.dirname(inifname) or "." )
    try:
        config.read( inifname )
    except ConfigParser.ParsingError:
        die("<b>%s</b>: Invalid configuration(not ini format?)" \
            % cgi.escape(inifname) )
        return

    feedname = os.getenv("QUERY_STRING")
    if feedname and config.has_section(feedname) :
        interpret( dict( config.items(feedname) ) )
    elif index:
        menu(config)
    else:
        die()

if __name__ == '__main__':
    main()
