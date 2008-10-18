#!/usr/local/bin/python

from datetime import datetime
import re
import sys
import urllib
import email

class WifkyFormNotFound(Exception):pass

class remote_wifky(object):
    def __init__(self,url,pwd=""):
        self.url = url
        self.pwd = pwd

    def get(self,title=None):
        if title is None:
            title = datetime.now().strftime("(%Y.%m.%d)")
        http = urllib.urlopen( self.url ,
            urllib.urlencode(
                { 
                    "signing":"1",
                    "password":self.pwd , 
                    "a":"edt", "p":title.encode("euc-jp") 
                }
            )
        )
        html = http.read()
        http.close()

        m = re.search(r'<input type="hidden" name="orgsrc_y" value="([^"]*)"',html)
        if m:
            orgsrc = m.group(1) \
                .replace("&lt;","<") \
                .replace("&gt;",">") \
                .replace("&quot;",'"') \
                .replace("&#39;","'") \
                .replace("&amp;","&")
            text = orgsrc \
                .replace("^n","\n") \
                .replace("^r","\r") \
                .replace("^t","\t") \
                .replace("^y","^" )
            return text,orgsrc
        else:
            raise WifkyFormNotFound(html)

    def put(self,text,orgsrc="",title=None):
        if title is None:
            title = datetime.now().strftime("(%Y.%m.%d)")
        http = urllib.urlopen( self.url ,
            urllib.urlencode(
                {
                    "signing":"1" ,
                    "password":self.pwd ,
                    "a":"Commit" ,
                    "p":title ,
                    "text_t":text ,
                    "orgsrc_y":orgsrc ,
                    "to_freeze":"1" ,
                }
            )
        )
        response = http.read()
        http.close()
        return response

    def add(self,text,title=None):
        orgsrc = self.get(title)
        return self.put( text=(orgsrc[0].strip() + "\n\n" + text).strip() ,
                  orgsrc=orgsrc[1] ,
                  title=title )

def subject(head):
    head = re.compile(r"=\?ISO-2022-JP\?B\?(.*)\?\=",re.IGNORECASE).sub(
        lambda m:m.group(1).decode("base64") , head 
    ).decode("iso2022jp")

    head = re.compile(ur" *\r?\n[ \t]+",re.DOTALL).sub("",head)

    m = re.search(r"^Subject:\s+(.*)$",head,re.IGNORECASE|re.MULTILINE)
    if m:
        return m.group(1)
    else:
        return ""

def postwifky( fd , url , pwd ):
    head,body = fd.read().split("\n\n",1)
    body = body.decode( "iso2022jp" )
    title = subject(head)
    if title:
        body = u"<<%s>>\n\n%s" % (title,body)

    return remote_wifky( url , pwd ).add( body.encode("euc-jp") )

if __name__ == "__main__":
    if len(sys.argv) == 3 :
        postwifky( sys.stdin , sys.argv[1] , sys.argv[2] )
