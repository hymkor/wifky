# from feedcat import *

class open_skip(sns_feed):
    def __init__(self,config):
        sns_feed.__init__(self,config)
        u = self.urlopen(config["index"])
        html = u.read().decode("utf8")
        u.close()

        entries = []
        for block in re.finditer(r'<div class="page_line">(.*?</div>)\s*</div>',html,re.DOTALL):
            b = block.group(1)
            entry = {}

            m = re.search(r'<div class="page_from"><a[^>]+>(.*?)</a>',b,re.DOTALL)
            if m:
                entry["author"] = m.group(1)

            m = re.search(r'<div class="page_date">(?P<month>\d\d)/(?P<day>\d\d) (?P<hour>\d\d):(?P<minute>\d\d)</div>',b,re.DOTALL)
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

            m = re.search(r'<div class="page_title">.*?<a href="(?P<url>[^"]+)"[^>]*>(?P<title>[^<]*)</a>',b,re.DOTALL)
            if m:
                entry["link"] = entry["id"] = \
                    urlparse.urljoin(config["index"], m.group("url") )
                entry["title"] = m.group("title")
            entries.append(entry)
        self["feed"] = {
            "link":"http://www.openskip.org/demo/",
            "title":"dummy title",
            "description":"dummy description",
        }
        self["entries"] = entries

feed_class[ "skip" ] = open_skip
