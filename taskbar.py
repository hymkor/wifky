#!/usr/bin/env python
# -*- coding:utf8 -*-

import cgi
import cgitb; cgitb.enable()
import datetime
import re
import itertools
import csv
import sys
import cStringIO as StringIO
import oreoref

def _sort_by_start_date(x,y):
    return cmp(x[0],y[0])

def _sort_by_date(x,y):
    return cmp(y[1].get("update_dt",datetime.datetime.min) , 
               x[1].get("update_dt",datetime.datetime.min) )

def _sort_by_priority(x,y):
    return  cmp(x[1]["priority"],y[1]["priority"])

def _sort_by_deadline(x,y):
    return  cmp(x[1].get("deadline") or datetime.date.max ,
                y[1].get("deadline") or datetime.date.max )

sort_by_start_date = _sort_by_start_date
sort_by_date       = _sort_by_date

def sort_by_priority(x,y):
    return  _sort_by_priority(x,y) \
         or _sort_by_deadline(x,y) \
         or sort_by_date(x,y)

def sort_by_deadline(x,y):
    return  _sort_by_deadline(x,y) \
         or _sort_by_priority(x,y) \
         or sort_by_date(x,y)

sort_option = {
    "1": ( sort_by_date       , "last date" ) ,
    "2": ( sort_by_priority   , "priority"  ) ,
    "3": ( sort_by_start_date , "start date") ,
    "4": ( sort_by_deadline   , "deadline"  ) ,
}

priority_option = {
    "1": "top",
    "2": "second",
    "3": "third",
    "4": "normal",
    "5": "bottom",
}

def select_option( name , options , default , display=(lambda x:x) ):
    print '<select name="%s">' % name
    for i in sorted( options.keys() ):
        print '<option value="%s"%s>%s</option>' % (
            i,
            (""," selected")[ i == default ],
            display(options[i]) )
    print '</select>'

def split_tag_and_title(title):
    tags = []
    tag_pattern = re.compile(r'\s*\[([^\]]+)\]')
    while True:
        m = tag_pattern.match(title)
        if not m:
            return (title,tags)
        tags.append( m.group(1) )
        title = title[m.end():]

def youbi(d):
    return ("&#26085;","&#26376;","&#28779;","&#27700;",
            "&#26408;","&#37329;","&#22303;","&#26085;")[ d.isoweekday() ]

def autolink(s):
    return re.sub(r"(s?https?|ftp)://[-\w.!~*\'();/?:@&=+$,%#]+",
               r'<a href="\g<0>" target="_blank">\g<0></a>',s)

class Application(oreoref.UserApplication):
    manual_url = './doc/index.cgi?p=OreOre+TaskBar'
    def print_h1(self):
        print '<h1 align="center"><a href="%s"' % self.myurl
        print '><img src="/img/OreOreTaskBar.png" alt="OreOre TaskBar!"'
        print 'border="0" /></a></h1>'

    def print_title(self):
        print '<title>- OreOre TaskBar -</title>'

    def print_man(self):
        print '<a href="%s">What is this?</a>' % self.manual_url

    def new_taskid(self):
        n = datetime.datetime.now()
        return "I%04d%02d%02d%02d%02d%02d%06d" % \
            (n.year,n.month,n.day , n.hour,n.minute,n.second , n.microsecond)
    
    def get_curtask(self):
        return self.data.get('curtask',{})
    def set_curtask(self,val):
        self.data['curtask'] = val
        self.data.commit()
    task = property( get_curtask , set_curtask )
        
    def chg_task_status(self,status):
        task = self.task
        for taskid in self.form.getlist("id"):
            if  taskid not in task :
                return "Invalid taskid(%s)" % taskid
            task[ taskid ]["status"] = status
            task[ taskid ]["update_dt"] = datetime.datetime.now()
        self.task = task
        return True

    def action_undo(self):
        return self.chg_task_status(False)

    def action_Complete(self):
        self.chg_task_status(True)
        return "Mission Completed"

    def action_add(self):
        title = self.form.getfirst("title","").strip()
        if len(title) <= 0:
            return True
        task = self.task
        tags = []
        taskid = self.form.getfirst("id",None)
        if not taskid:
            taskid = self.new_taskid()
        
        title,tags = split_tag_and_title(title)

        deadline = self.form.getfirst("deadline") or None
        if deadline :
            try:
                deadline = datetime.date(
                    int(deadline[0:4],10) ,
                    int(deadline[4:6],10) ,
                    int(deadline[6:8],10) )
            except ValueError:
                deadline = None
        
        task[ taskid ] = {
            "title":title ,
            "status":self.form.getfirst("b","Add") == "Complete" ,
            "detail":self.form.getfirst("detail","") ,
            "priority":self.form.getfirst("priority","4") ,
            "update_dt":datetime.datetime.now() ,
            "tags":tags ,
            "deadline":deadline ,
        }
        self.task = task
        return True
    
    def action_cleanup(self):
        newtask = {}
        for taskid,e in self.task.iteritems() :
            if e["status"]==False :
                newtask[taskid] = e
        self.task = newtask
        return 'Done task is cleaned up.'
    
    def action_export(self):
        n = datetime.datetime.now()
        print 'Content-type: text/csv; charset=%s;' % oreoref.UserApplication.charset
        print 'Content-Disposition: attachment; filename="tasklist-%04d%02d%02d.csv"'\
            % ( n.year , n.month , n.day )
        print
        csvout = csv.writer( sys.stdout , 'excel' , lineterminator = "\n" )
        for taskid,e in self.task.iteritems():
            deadline = e.get("deadline")
            if deadline :
                deadline = deadline.strftime("%Y/%m/%d")
            else:
                deadline = ""

            csvout.writerow((
                taskid ,
                e.get("update_dt",datetime.datetime.min).strftime("%Y/%m/%d %H:%M:%S") ,
                e.get("priority","4") ,
                (" ","X")[ e["status"] ],
                "".join([ "[%s]" % t for t in e.get("tags",[]) ]) + e["title"] ,
                e.get("detail","").replace("\r","") ,
                deadline 
            ))
        return False
    
    def action_import(self):
        error_list = []
        success_cnt = 0
        task = self.task
        for row in csv.reader( StringIO.StringIO( self.form.getfirst("data","") ) ):
            ### length check ###
            if len(row) < 5:
                error_list.append( "Too few element: %s" % cgi.escape(",".join(row)) )

            ### Task ID check (0) ###
            taskid = row[0]
            if not re.match(r"I\d{20}",taskid):
                error_list.append( "Bad ID(<b>%s</b>): %s" % \
                    ( cgi.escape(row[0]) , cgi.escape(row[4]) ) )
                continue
            
            ### Update Date ###
            try:
                n = [int(e,10) for e in re.split(r"[/: ]",row[1]) ]
                if len(n) == 5: n.append(59)
                update_dt = datetime.datetime(n[0],n[1],n[2],  n[3],n[4],n[5])
            except (ValueError,IndexError):
                error_list.append( "Date Error(<b>%s</b>): %s" % \
                    ( cgi.escape(row[1]) , cgi.escape(row[4]) ) )
                continue

            ### Conflict ###
            if taskid in task :
                org_dt = task[taskid].get("update_dt",datetime.datetime.min)

                if org_dt > update_dt :
                    error_list.append(
                        "Newer or same data(<b>%s</b>) exist: %s" % (
                            org_dt.strftime("%Y/%m/%d %H:%M:%S") ,
                            cgi.escape( row[4] )
                        )
                    )
                    continue

            ### Title and tags (4) ###
            title,tags = split_tag_and_title( row[4] )

            ### Detail (5) ###
            if len(row) < 6 :
                detail = ""
            else:
                detail = row[5]

            ### Deadline Date (6) ###
            if len(row) < 7 or len(row[6]) <= 0:
                deadline = None
            else:
                n = [int(e,10) for e in row[6].split("/") ]
                if len(n) < 3:
                    error_list.append(
                        "Bad date format for deadline: %s" % cgi.escape( row[6] )
                    )
                deadline = datetime.date(n[0],n[1],n[2])

            ### Append ###
            task[ taskid ] = {
                "title":title ,
                "status": ( row[3] == "X" ) ,
                "detail":re.sub(r"\r*\n","\r\n",detail) ,
                "priority":("4",row[2])[ row[2] in ("1","2","3","4","5") ] ,
                "update_dt":update_dt ,
                "tags":tags ,
                "deadline":deadline ,
            }
            success_cnt += 1

        if "test" not in self.form :
            self.task = task
        
        return (
            "<h2>Import Report</h2>\n"
            "<ul><li>%d task(s) imported.</li>\n"
            "<li>%d task(s) rejected.</li>\n"
            "</ul>\n" % ( success_cnt , len(error_list) )
        )+"\n".join(["<div>%s</div>" % e for e in error_list])
    
    def decorate_title( self , e ):
        """ Create html-text such as "[xxx][yyy] ttttttt"
            xxx and yyy are tags which are linked
        """

        return "".join(['[<a href="%s?tag=%s">%s</a>]' % \
                          (self.myurl,cgi.escape(tag),cgi.escape(tag)) 
                          for tag in e.get("tags",[]) ]) + \
                        '<span class="tasktitle">' + \
                        autolink( cgi.escape(e["title"]) ) + \
                        '</span>'

    def list_task( self , flag , order_by="1" ):
        """ listing tasks
        """
        for taskid,e in \
            sorted( self.task.iteritems() ,
                    sort_option.get( order_by , (sort_by_date,) )[0] ) :

            if e["status"] != flag : continue

            if "tag" not in self.form :
                yield taskid,e
                continue

            for tag in self.form.getlist("tag"):
                if tag in e.get("tags",[]) :
                    yield taskid,e
                    break
    
    def print_tag_hidden_transfer( self ):
        for tag in self.form.getlist("tag"):
            print '<input type="hidden" name="tag" value="%s" />' % cgi.escape(tag)

    def print_detail( self , taskid , e ):
        if e["detail"]:
            print '''<span onClick="JavaScript:doRev('%s_detail')"''' % \
                cgi.escape(taskid)
            print 'class="detailswitch">&#9660;</span>'
            print '<div id="%s_detail" style="display:none" class="detail"' % \
                cgi.escape(taskid)
            print '>%s</div>' % autolink(cgi.escape(e["detail"])).replace("\n","<br />")
        else:
            print '<span id="%s_detail"></span>' % cgi.escape(taskid)
    
    def action_order_by(self):
        order_by = self.form.getfirst("order_by","1")
        if order_by not in sort_option:
            order_by = "1"
        self.data["order_by"] = order_by
        self.data.commit()
        return True

    def default(self):
        print 'Content-Type: text/html; charset=%s;' % oreoref.UserApplication.charset
        print ''
        print '<html><head>'
        self.print_title()

        print '''<script language="JavaScript"><!--
function id2text(id){
   var node=document.getElementById(id);
   return typeof(node.textContent) != 'undefined'
          ? node.textContent : node.innerText ;
}
function show(id){
    document.getElementById(id).style.display='';
}
function hide(id){
    document.getElementById(id).style.display='none';
}
function dialog(n){
    switch(n){
        default: show('newitem');hide('editarea');hide('importarea');break;
        case 1:  hide('newitem');show('editarea');hide('importarea');break;
        case 2:  show('newitem');hide('editarea');show('importarea');break;
    }
}
function doRev(id){
    var node=document.getElementById(id);
    if( node.style.display == 'none' ){
        node.style.display = '';
    }else{
        node.style.display = 'none';
    }
    return undefined;
}
function doEdit(taskid,priority,deadline){
    if( document.edittask.id.value.length <= 0 ){
        hide('addbutton');
        show('updbutton');
        hide('newitem');
        show('editarea');

        document.edittask.id.value = taskid;
        document.edittask.title.value = id2text(taskid+'_title');
        document.edittask.detail.value = id2text(taskid+'_detail');
        document.edittask.priority.value = priority;
        document.edittask.deadline.value = deadline;
    }
    return undefined;
}
function doReset(){
    var taskid=document.edittask.id.value;
    if( taskid.length > 0 ){
        show('addbutton');
        hide('updbutton');
    }
    document.edittask.title.value = '';
    document.edittask.detail.value = '';
    document.edittask.id.value = '';
    document.edittask.deadline.value = '';
    document.edittask.priority.value = '4';

    dialog(0)

    return undefined;
}
function doCleanUp(){
    if( window.confirm('Are you sure to clean all completed tasks') ){
        window.location = '%(myurl)s?a=cleanup';
    }
    return undefined;
}
// -->
</script>
<style type="text/css">
    @media print{
        .printeroff,.detailswitch,.bottomtaskall,div.bottomtask{ display:none }
    }
    .detailswitch{text-decoration:none;font-size:x-small;color:blue;cursor:pointer}

    /* priority */
    div.toptask    {font-size:300%%}
    div.secondtask {font-size:200%%}
    div.thirdtask  {font-size:150%%}
    div.normaltask {}
    div.bottomtask {color:gray}

    /* deadtime */
    div.timeout  span.tasktitle{color:red;font-weight:bold}
    div.today    span.tasktitle{color:#cc00cc;font-weight:bold}
    div.tomorrow span.tasktitle{color:orange;font-weight:bold}
    span.tasktitle{cursor:pointer}

    div.detail{
        margin-left:1cm;
        margin-right:1cm;
        margin-top:1mm;
        margin-bottom:1mm;
        background-color:silver;
        font-size:x-small;
    }
    div.dialog{
        position : absolute;
        z-index : 1000;
        left: 15%%;
        top : 30%%;
        width : 520px;
        border-width:1px 3px 3px 1px;
        border-color:black;
        border-style:solid;
        padding: 5px;
        font-size : 12px;
        background : #fff;
    }
</style>''' % { "myurl":self.myurl }

        print '</head><body>'
        today = datetime.date.today()
        print '<div style="float:right">%04d/%02d/%02d(%s)</div>' \
            % ( today.year , today.month , today.day , youbi(today) )

        print '<div class="printeroff">'
        self.print_menubar( ("Export","export") )
        print '| <a href="#" onClick="JavaScript:dialog(2);return false;">Import</a>'
        print ' | <a href="%s">Manual</a>' % self.manual_url

        self.print_h1()
        self.print_message()

        print '<div id="newitem" style="float:right"><form>'
        print '<input type="button" value="New Item" onClick="JavaScript:dialog(1)" />'
        print '</form></div>'

        ### Import Area ###
        print '<div id="importarea" class="dialog" style="display:none">'
        print '<h2>Import tasks</h2>'
        print   '<form action="%s" method="POST" enctype="multipart/form-data">' \
            % self.myurl
        print   '<input type="hidden" name="a" value="import" />'
        print   '<input type="file" name="data" size="48" />'
        print   '<input type="checkbox" name="test" value="test" />'
        print   '<span style="font-size:x-small">test?</span>'
        print   '<br /><input type="submit" value="Upload" />&nbsp;'
        print   '<input type="button" value="Cancel" onClick="JavaScript:dialog(0)" />'
        print   '</form>'
        print '</div>'

        ### Edit Area ###
        print '<div id="editarea" class="dialog" style="display:none">'
        print '<h2>Edit a task</h2>'
        print '<form action="%s" name="edittask" method="POST">' % cgi.escape(self.myurl)
        print '<div>'
        print    '<input type="hidden" name="id" value="" />'
        print    '<input type="text" name="title" value="" size="60" /><br />'

        print    'Deadline:<select name="deadline">'
        print    '<option value="" selected>None</option>'
        for i in xrange(14):
            d = today + datetime.timedelta(days=i)
            print '<option value="%04d%02d%02d">%02d/%02d (%s)</option>' % (
                d.year ,
                d.month ,
                d.day ,
                d.month ,
                d.day ,
                youbi(d) ,
            )
        print    '</select>'

        print    'Priority:'
        select_option( "priority" , priority_option , "4" , str.upper )
        print    '<input type="hidden" name="a" value="add" />'
        print    '<span id="addbutton">'
        print       '<input type="submit" value="Add" /></span>'
        print    '<span id="updbutton" style="display:none">'
        print       '<input type="submit" value="Update" />'
        print       '<input type="checkbox" name="b" value="Complete" />'
        print       '<span style="font-size:xx-small">Complete?</span>'
        print    '</span>'
        print    '&nbsp;&nbsp;'
        print    '<input type="button" value="Cancel" onClick="JavaScript:doReset()" />'
        print '</div>'
        print '<div style="font-size:x-small;font-weight:bold">memo</div>'
        print '<div>'
        print '<textarea name="detail" rows="5" style="width:100%"></textarea>'
        print '</div>'
        self.print_tag_hidden_transfer()
        print '</form>'
        print '</div><!-- editarea -->'
        print '</div><!-- printeroff area -->'

        print '<h2>Active tasks</h2>'

        print '<form name="currenttask" action="%s" method="POST">' % self.myurl
        print '<div>'

        for taskid,e in self.list_task( False , self.data.get("order_by","1") ):
            style=[ priority_option.get(e.get("priority","4") , "normal")+"task" ]
            
            deadline = e.get("deadline")
            deadline_option = ""
            if deadline :
                if deadline < today :
                    style.append("timeout")
                elif deadline == today :
                    style.append("today")
                elif deadline == today + datetime.timedelta(days=+1):
                    style.append("tomorrow")
                deadline_option = "%04d%02d%02d" % \
                    (deadline.year,deadline.month,deadline.day)

            print '<div class="%s">' % " ".join(style)
            print '<input type="checkbox" name="id" value="%s" />' % (
                cgi.escape(taskid) )
            print '''<span onClick="JavaScript:doEdit('%s','%s','%s');"''' \
                    % ( cgi.escape(taskid) , 
                        cgi.escape(e.get("priority","4")) ,
                        cgi.escape(deadline_option) ) ,
            print 'id="%s_title">%s</span>' % (
                cgi.escape(taskid) ,
                self.decorate_title( e ) 
            )
            if deadline :
                print '<span>&#65374;%02d/%02d(%s)</span>' % (
                    deadline.month , deadline.day , youbi(deadline)
                )
            self.print_detail(taskid,e)
            print '</div>'
            
        self.print_tag_hidden_transfer()
        print '<input type="submit" name="a" value="Complete" class="printeroff" />'
        print '</div>'
        print '</form>'

        ### Sort and Filter Line ###
        print '<form action="%s" method="POST" class="printeroff">' % self.myurl
        print 'order by '
        select_option("order_by", sort_option, self.data.get("order_by","1"),lambda x:x[1])
        print ' / Filter:'
        for tag in reduce(lambda x,y:x | set(y["tags"]) ,
                          self.task.values() , set() ):
            print '<input type="checkbox" name="tag" value="%(tag)s"%(chk)s />%(tag)s' % {
                "tag":cgi.escape(tag) ,
                "chk":(""," checked")[tag in self.form.getlist("tag")] ,
            }

        print '<input type="submit" value="Apply" />'
        print '(<a href="%s">all</a>)'% self.myurl
        print '<input type="hidden" name="a" value="order_by" />'
        print '</form>'

        ### Completed Tasks ###
        print '<h2>Completed tasks</h2>'
        print '<form action="%s" method="POST">' % self.myurl

        print '<dl>'
        for D,G in itertools.groupby(
            self.list_task(True) ,
            lambda x:x[1].get("update_dt",datetime.datetime.min).date() ) :

            print '<dt>%d/%d/%d</dt>' % (D.year,D.month,D.day)
            for taskid,e in G:
                print '<dd style="font-size:x-small">'
                print '<input type="checkbox" name="id" value="%s" />' \
                    % cgi.escape(taskid)
                print '<s>%s</s>' % self.decorate_title(e)
                self.print_detail(taskid,e)
                print '</dd>'
        print '</dl>'
        self.print_tag_hidden_transfer()
        print '<input type="submit" name="a" value="undo" class="printeroff" />'
        print '</form>'
        if "tag" not in self.form :
            print '<p class="printeroff"><a href="#" onClick="JavaScript:doCleanUp()"'
            print '>Clean-up all-finished tasks</a></p>'

        print '</body></html>'

Application( cgi.FieldStorage() ).run()
