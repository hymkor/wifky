@feed_processor
def skip(browser,config):
    http = browser.opener(config["index"])
    html = http.read().decode("utf8")
    http.close()

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
        ur'<div class="page_title">.*?<a href="(?P<url>[^"]+)" ' +
        u'title="\\[\u30B3\u30E1\u30F3\u30C8\\((?P<_comment_cnt>\\d+)\\)[^>]*>' +
        ur'(?P<title>[^<]*)</a>'
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
        stamp = match2stamp(m)
        entry["updated"] = stamp.isoformat()
        entry["updated_parsed"] = stamp.timetuple()

        m = entry_title_pattern.search(b)
        if m:
            entry["link"] = entry["id"] = \
                urlparse.urljoin(config["index"], m.group("url") )
            entry["title"] = m.group("title")
            if "debug" in config:
                entry["title"] += " (Comment:%s)" % m.group("_comment_cnt") 
            entry["_comment_cnt"] = m.group("_comment_cnt")
            entries.append(entry)

    feed = { "link":config["index"] }
        
    if "feed_title" in config:
        feed["title"] = config["feed_title"].decode("utf8")
    else:
        m = feed_title_pattern.search(html)
        if m: 
            feed["title"] = m.group(1)
        else:
            feed["title"] = config["index"]

    d = {
        "feed":feed ,
        "entries":entries ,
    }

    if "import" not in config :
        config["import"] = r'<div id="default_style_area"[^>]*>(.*?)</div>\s*<div id="source_style_area"'
    if "comment" not in config :
        config["comment"] = r'''<div class="board_entry_comment" id='(?P<id>[^']+).*?>(?P<author>[^<]*)</a><span style="font-size: 10px;?">\[(?P<year>\d\d\d\d)/(?P<month>\d\d)/(?P<day>\d\d)-(?P<hour>\d\d):(?P<minute>\d\d)\]</span>.*?<div class="hiki_style">(?P<content>.*?)</div>'''

    return d
