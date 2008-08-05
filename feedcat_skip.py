# from feedcat import *

class open_skip(sns_feed):
    def __init__(self,config):
        sns_feed.__init__(self,config)
        u = self.urlopen(config["index"])
        html = u.read().decode("utf8")
        u.close()

        entry_pattern = re.compile(
            r'<div class="page_line">(.*?</div>)\s*</div>'
            , re.DOTALL)

        entry_author_pattern = re.compile(
            r'<div class="page_from"><a[^>]+>(.*?)</a>'
            , re.DOTALL)

        entry_date_pattern = re.compile(
            r'<div class="page_date">(?P<month>\d\d)/(?P<day>\d\d) ' +
            r'(?P<hour>\d\d):(?P<minute>\d\d)</div>'
            , re.DOTALL )

        entry_title_pattern = re.compile(
            r'<div class="page_title">.*?<a href="(?P<url>[^"]+)"[^>]*>' +
            r'(?P<title>[^<]*)</a>'
            , re.DOTALL )

        feed_title_pattern = re.compile(
            r'<title>(.*?)</title>'
            , re.IGNORECASE )

        entries = []
        for block in entry_pattern.finditer(html):
            b = block.group(1)
            entry = {}

            m = entry_author_pattern.search(b)
            if m:
                entry["author"] = m.group(1)

            m = entry_date_pattern.search(b)
            if m :
                md = m.groupdict()
                dt = datetime.datetime(
                    int(md.get("year",datetime.datetime.now().year) ),
                    int(md["month"]) ,
                    int(md["day"]) ,
                    int(md.get("hour",0)),
                    int(md.get("minute",0)) ,
                    int(md.get("second",0)) )
            else:
                dt = datetime.datetime.now()
            dt += datetime.timedelta( hours=-9 )
            entry["updated"] = dt.isoformat()
            entry["updated_parsed"] = (
                dt.year , dt.month  , dt.day ,
                dt.hour , dt.minute , dt.second ,
                dt.microsecond )

            m = entry_title_pattern.search(b)
            if m:
                entry["link"] = entry["id"] = \
                    urlparse.urljoin(config["index"], m.group("url") )
                entry["title"] = m.group("title")
            entries.append(entry)

        feed = { "link":config["index"] }
            
        m = feed_title_pattern.search(html)
        if m: 
            feed["title"] = m.group(1)
        else:
            feed["title"] = config["index"]

        self["feed"] = feed
        self["entries"] = entries

feed_class[ "skip" ] = open_skip
