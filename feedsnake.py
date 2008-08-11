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

version="0.1"

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

error_cnt=0
def insert_message_as_feed(d,message):
    global error_cnt
    error_cnt += 1
    d["entries"].insert(0,
        {
            "title":"Feed Error! [%d]" % error_cnt ,
            "id":"http://example.com/#%d" % error_cnt ,
            "author":"FeedSnake System" ,
            "description": message ,
            "content":[ {"value":message} ] ,
        }
    )

def import_contents(d, config):
    cachefn = config.get("cache") 
    coding  = config.get("htmlcode")
    pattern = config["import"]

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
            "Invalid Regular Expression '%s'" % cgi.escape(pattern) 
        )
        return

    cache_fail_cnt = 0

    for e in d["entries"]:
        link = e["link"]
        if link in cache:
            content = cache[link]
        else:
            cache_fail_cnt += 1
            content = d.urlopen(link).read()
            try:
                if coding is None:
                    m = re.search(r'<meta[^>]*?\bcharset=([^"]+)"',content,re.IGNORECASE)
                    if m:
                        coding = m.group(1).lower()
                    else:
                        coding = "utf8"

                content = content.decode(coding)
                m = pattern.search( content )
                if m :
                    content = m.group(1).strip()
                else:
                    continue
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
            except UnicodeDecodeError:
                content = u""

        if content:
            e.setdefault("content",[]).append({ "value":content })
            e["description"] = content
            new_cache[link] = content

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

def exclude(d,pattern):
    try:
        pattern = re.compile(pattern)
    except:
        insert_message_as_feed(d,
            "Invalid Regular Expression '%s'" %
                cgi.escape(pattern) 
        )
        return

    d["entries"] = filter( lambda e:not pattern.search(e["title"]) , d["entries"] )
       

class error_feed(dict):
    def __init__(self,config,message="feed not found."):
        self["entries"] = []
        self["feed"] = {
            "link":"http://example.com",
            "title":"Feed Error!",
            "description":message ,
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
        exclude(d,config["exclude"])

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

def be_silent():
    print "Content-Type: text/html"
    print ""
    print "<html><body></body></html>"

def main(inifname=None,index=True):
    config = ConfigParser.ConfigParser()
    if inifname is None:
        inifname = re.sub( r"\.py$", ".ini" , inspect.getfile(main) )
    os.chdir( os.path.dirname(inifname) or "." )
    config.read( inifname )

    feedname = os.getenv("QUERY_STRING")
    if feedname and config.has_section(feedname) :
        interpret( dict( config.items(feedname) ) )
    elif index:
        menu(config)
    else:
        be_silent()

if __name__ == '__main__':
    main()
