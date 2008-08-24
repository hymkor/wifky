class beta_feed(norm_feed):
    def __init__(self,config):
        home = config["index"]
        fd = urllib.urlopen(home)
        html = fd.read()
        m = re.search(r'<meta[^>]*?\bcharset=([^"]+)"',html,re.IGNORECASE)
        if m :
            coding=m.group(1).lower()
        else :
            coding="utf8"
        html = html.decode( coding )

        fd.close()
        if "feed_title" in config:
            title = config["feed_title"]
        else :
            m = re.search(r'<title>(.*?)</title>',html)
            if m:
                title = m.group(1)
            else :
                title = "Feed of " + home

        entries = []
        for m in re.finditer( config["inline"].decode("utf8") , html , re.DOTALL ):
            entries.append(
                Feed.entry( 
                    link=urlparse.urljoin( home , m.group("url") ) ,
                    title=re.sub(r'<[^>]*>','',m.group("title")) ,
                    content=Feed.rel2abs_paths( home , m.group("content") ),
                    author="zakkicho" ,
                )
            )

        self["entries"] = entries
        self["feed"] = {
            "link":home ,
            "title":title ,
            "description":"" ,
        }

feed_class["beta"] = beta_feed
