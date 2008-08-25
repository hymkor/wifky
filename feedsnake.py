#!/usr/local/bin/python

import ConfigParser
import cPickle as pickle
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

version="0.4"

class Feed(dict):
    def __init__(self,*argv):
        dict.__init__(self,*argv)
        self.error_cnt = 0

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

    def http_output(self):
        sys.stdout.write("Content-Type: application/xml; charset=utf-8\r\n\r\n")
        self.feedcat(sys.stdout)

    @staticmethod
    def entry( title , link=None , id_=None ,content=None , updated=None , author=None ):
        if updated is None:
            updated = datetime.datetime.utcnow()
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
        d.error_cnt += 1
        d["entries"].insert(0,
            Feed.entry(
                title="Feed Error! [%d]" % d.error_cnt ,
                link="http://example.com/#%d" % d.error_cnt ,
                author="FeedSnake System" ,
                content=message ,
            )
        )

    @staticmethod
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

    @staticmethod
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

    @staticmethod
    def feednm2cachefn(feedname):
        return feedname + ".cache"

    def import_contents(d, config):
        try:
            max_entries = int(config.get("max_entries","5"))
        except ValueError:
            d.insert_message("Invalid Entry number '%s'" % config["max_entries"] )
            max_entries = 5
        del d["entries"][max_entries:]

        cachefn = Feed.feednm2cachefn(config["feedname"])
        coding  = config.get("htmlcode")
        pattern = config["import"]
        comment = config.get("comment")

        cache = {}
        new_cache = {}

        try:
            fd = file(cachefn)
            cache = pickle.load( fd )
            fd.close()
        except:
            pass
        try:
            pattern = re.compile(pattern,re.DOTALL)
        except:
            d.insert_message(
                "Invalid Regular Expression 'import=%s'" % 
                                cgi.escape(pattern) )
            return
        if comment:
            try:
                comment = re.compile(comment,re.DOTALL)
            except:
                d.insert_message(
                    "Invalid Regular Expression 'comment=%s'" %
                    cgi.escape(comment)
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
            new_cache[link] = pageall
            new_cache[link,"mark"] = e.get("_comment_cnt")

            ### main contents ###
            m = pattern.search( pageall )
            if m :
                content = Feed.rel2abs_paths( link , m.group(1).strip() )
                e.setdefault("content",[]).append({ "value":content })
                e["description"] = content

            if comment :
                try:
                    for i,m in enumerate(comment.finditer(pageall)):
                        ext_entries.append(
                            Feed.entry(
                                title="Comment #%d for %s" % ( 1+i , e.get("title","") ) ,
                                link=link + "#" + m.group("id") ,
                                author = m.group("author") ,
                                content = m.group("content") ,
                                updated = Feed.match2stamp(m) ,
                            )
                        )
                except IndexError:
                    d.insert_message(
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
                d.insert_message(
                    "could not update cache file '%s'" %
                    cgi.escape(cachefn)
                )

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

class error_feed(Feed):
    def __init__(self,config,message="feed not found."):
        Feed.__init__(self)
        self["entries"] = []
        self["feed"] = {
            "link":"http://example.com",
            "title":"Feed Error!",
            "description":message ,
        }

class NormFeed(Feed):
    def __init__(self,config):
        Feed.__init__(self,feedparser.parse( config["feed"] ) )
    def urlopen(self, *url ):
        return urllib.urlopen( *url )

class SnsFeed(Feed):
    def __init__(self,config):
        def parse_param(text):
            loginpost = re.split(r"[\s\;\&\?]+",text)
            url = loginpost.pop(0)
            param = {}
            for e in loginpost:
                p = e.split("=",2)
                param[ p[0] ] = p[1]
            return url,param

        Feed.__init__(self)
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

class LoginFeed(SnsFeed):
    def __init__(self,config):
        SnsFeed.__init__(self,config)
        self.update( self.parse(config["feed"]) )

def DefaultFeed(config):
    if "login" in config  or  "loginpost" in config:
        if "feed" in config:
            return LoginFeed(config)
        elif "index" in config:
            return LoginInlineFeed(config)
    else:
        if "feed" in config:
            return NormFeed(config)
        elif "index" in config:
            return InlineFeed(config)
    return error_feed(config)

class InlineFeed(NormFeed):
    def __init__(self,config):
        index = config["index"]
        fd = self.urlopen(index)
        html = fd.read()
        m = re.search(r'<meta[^>]*?\bcharset=([^"]+)"',html,re.IGNORECASE|re.DOTALL)
        if m :
            coding=m.group(1).lower()
        elif "htmlcode" in config:
            coding=config["htmlcode"]
        else :
            coding="utf8"
        html = html.decode( coding )
        fd.close()

        if "feed_title" in config:
            title = config["feed_title"]
        else :
            m = re.search(r'<title>(.*?)</title>',html,re.DOTALL|re.IGNORECASE)
            if m:
                title = m.group(1)
            else :
                title = "Feed of " + index

        self["feed"] = {
            "link":index ,
            "title":title ,
            "description":"" ,
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
                content = Feed.rel2abs_paths( index , m.group("content") )
            else:
                content = None

            if "(?P<url>" in pattern_str:
                id_ = link = urlparse.urljoin( index , m.group("url") )
            elif not content:
                continue
            else:
                link = None
                id_ = md5.new( content.encode(coding) ).hexdigest()

            entries.append(
                Feed.entry( 
                    id_ = id_ ,
                    link = link ,
                    title = title ,
                    content = content
                )
            )

        self["entries"] = entries

class LoginInlineFeed(SnsFeed,InlineFeed):
    def __init__(self,config):
        SnsFeed.__init__(self,config)
        InlineFeed.__init__(self,config)

feed_class = {
    "feed":NormFeed ,
    "mixi":LoginFeed ,
    "index":InlineFeed ,
    "default":DefaultFeed ,
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
        d = error_feed( config , "Can not load feed class '%s'" % cgi.escape(classname) )
    except Exception,e:
        d = error_feed( config , cgi.escape(str(e)) )

    for key in "author", "title":
        if key in config:
            try:
                d.accept(key,config[key].decode("utf8"))
            except UnicodeDecodeError:
                d.insert_message("UnicodeDecodeError on %s=.." % key)
        if "x"+key in config:
            try:
                d.deny(key,config["x"+key].decode("utf8"))
            except UnicodeDecodeError:
                d.insert_message("UnicodeDecodeError on x%s=.." % key)

    if "import" in config:
        d.import_contents( config )
    d.http_output()

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
        cachefn = Feed.feednm2cachefn(feedname[1:])
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
