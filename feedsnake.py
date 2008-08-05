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
        output('  <rdf:li rdf:resource="%s" />' % cgi.escape(e["id"]))

    output('</rdf:Seq>')
    output('</items>')
    output('</channel>')

    for e in d["entries"]:
        output( '<item rdf:about="%s">' % cgi.escape(e["id"]) )
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

def import_contents(d, cachefn=None ,coding="utf8", pattern=None):
    cache = {}
    new_cache = {}

    if cachefn:
        try:
            fd = file(cachefn)
            cache = pickle.load( fd )
            fd.close()
        except:
            pass
    if pattern :
        pattern = re.compile(pattern,re.DOTALL)

    for e in d["entries"]:
        if e["link"] in cache:
            content = cache[e["link"]]
        else:
            content = d.urlopen(e["link"]).read().decode(coding)
            if pattern:
                m = pattern.search( content )
                if m :
                    content = m.group(1).strip()
        if content:
            e.setdefault("content",[]).append({ "value":content })
            e["description"] = content
            new_cache[e["link"]] = content

    if cachefn:
        fd = file(cachefn,"w")
        pickle.dump( new_cache , fd )
        fd.close()

def reject(d,pattern):
    pattern = re.compile(pattern)
    d["entries"] = filter( lambda e:not pattern.search(e["title"]) , d["entries"] )

def recentonly(d,days):
    start_dt = datetime.datetime.today() - datetime.timedelta(days)
    d["entries"] = [  e
                 for  e in d["entries"]
                  if  "updated_parsed" in e 
                 and  datetime.datetime( *e["updated_parsed"][:6] ) >= start_dt
    ]

class feed_not_found(dict):
    def __init__(self,config):
        self["entries"] = []
        self["feed"] = {
            "link":"http://example.com",
            "title":"Feed not found!",
            "description":"feed not found.",
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
        cookiejar = cookielib.CookieJar()
        self.cookie_processor = urllib2.HTTPCookieProcessor(cookiejar)
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

feed_class = {
    "feed":norm_feed ,
    "mixi":mixi_feed ,
}

def interpret( config ):
    classname = config.get("class","feed")
    if "@" in classname :
        classname,plugin = classname.split("@",2)
        execfile(plugin+".py",globals(),locals())

    d = feed_class.get(classname, feed_not_found)( config )

    if "reject" in config:
        reject(d,config["reject"])

    recentonly(d,3)

    if "import" in config:
        import_contents( d ,
                         config.get("cache") ,
                         config.get("htmlcode","utf8") ,
                         config["import"] )
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
    print "</ul></body></html>"

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
