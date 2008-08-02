#!/usr/local/bin/python

import cgi
import cgitb ; cgitb.enable()
import codecs
import datetime
import ConfigParser
import os
import re
import sys
import urllib
import urllib2
import cookielib

import feedparser

def feedcat(d,fd):
    fd = codecs.getwriter('utf_8')(fd)
    def output(t):
        print >>fd,t

    output('<?xml version="1.0" encoding="UTF-8" ?>')
    output('<rdf:RDF')
    output(' xmlns="http://purl.org/rss/1.0/"')
    output(' xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"')
    output(' xmlns:content="http://purl.org/rss/1.0/modules/content/"')
    output(' xmlns:dc="http://purl.org/dc/elements/1.1/"')
    output(' xml:lang="ja">')
    output('<channel rdf:about="%s">' % d["feed"]["link"] )
    for tag,key in (
        ("title","title"),
        ("link","link"),
        ("description","description"),
    ):
        if key in d["feed"]:
            output("<%s>%s</%s>" % (tag,d["feed"][key],tag))

    output('<items>')
    output('<rdf:Seq>')

    for e in d["entries"]:
        output('  <rdf:li rdf:resource="%(id)s" />' % e)

    output('</rdf:Seq>')
    output('</items>')
    output('</channel>')

    for e in d["entries"]:
        output( '<item rdf:about="%(id)s">' % e )
        for tag,key in (
            ("title","title") ,
            ("link","link") ,
            ("lastBuildDate","updated") ,
            ("author","author") ,
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
    sys.stdout.write("Content-Type: application/rss+xml; charset=utf-8\n\n")
    feedcat(d,sys.stdout)

def import_contents(d, coding="utf8", pattern=None):
    if pattern :
        pattern = re.compile(pattern,re.DOTALL)
    for e in d["entries"]:
        content = d.urlopen(e["link"]).read().decode(coding)
        if pattern:
            m = pattern.search( content )
            if m :
                content = m.group(1).strip()
        if content:
            e.setdefault("content",[]).append({ "value":content })
            e["description"] = content

def reject(d,pattern):
    pattern = re.compile(pattern)
    d["entries"] = filter( lambda e:not pattern.search(e["title"]) , d["entries"] )

def recentonly(d,days):
    start_dt = datetime.datetime.today() - datetime.timedelta(days)
    d["entries"] = [
        e for e in d["entries"]
           if datetime.datetime( *e["updated_parsed"][:6] ) >= start_dt
    ]

class norm_feed(dict):
    def __init__(self,config):
        dict.__init__(self,feedparser.parse( config["feed"] ) )
    def urlopen(self, *url ):
        return urllib.urlopen( *url )

class sns_feed(dict):
    def __init__(self):
        cookiejar = cookielib.CookieJar()
        self.cookie_processor = urllib2.HTTPCookieProcessor(cookiejar)
        self.opener = urllib2.build_opener( self.cookie_processor )
    def urlopen(self, *url ):
        return self.opener.open( *url )
    def parse(self, url):
        return feedparser.parse(url,handlers=[self.cookie_processor])

class mixi_feed(sns_feed):
    def __init__(self,config):
        sns_feed.__init__(self)
        email,passwd = config["mixi"].split(":")

        self.urlopen(
                "http://mixi.jp/login.pl" ,
                urllib.urlencode(
                    { "next_url":"/home.pl" , 
                      "email":email ,
                      "password":passwd 
                    }
                )
        ).close()

        self.update( self.parse(config["feed"]) )

def interpret( config ):
    if "mixi" in config:
        d = mixi_feed( config )
    else:
        d = norm_feed( config )
    recentonly(d,2)
    if "reject" in config:
        reject(d,config["reject"])

    if "import" in config:
        import_contents( d ,
                         config.get("htmlcode","utf8") ,
                         config["import"] )
    http_output(d)

def menu(config):
    print "Content-Type: text/html"
    print ""
    print "<html>"
    print "<title>FeedCat</title>"
    print "<body><h1>FeedCat</h1>"
    print "<ul>"
    for e in config.sections():
        print '<li><a href="%s?%s">%s</a>' % (
            os.getenv("SCRIPT_NAME") ,
            cgi.escape(e) ,
            cgi.escape(e)
        )
        print '<ul>'
        for f in config.items(e):
            print '<li>%s=%s</li>' %(
                cgi.escape(f[0]) ,
                cgi.escape(f[1]) ,
            )
        print '</ul></li>'
    print "</body></html>"

def main(inifname):
    config = ConfigParser.ConfigParser()
    config.read( inifname )
    feedname = os.getenv("QUERY_STRING")
    if feedname and config.has_section(feedname) :
        interpret( dict( config.items(feedname) ) )
    else:
        menu(config)

if __name__ == '__main__':
    main( re.sub(r"\.\w+$" , ".ini" , sys.argv[0]) )
