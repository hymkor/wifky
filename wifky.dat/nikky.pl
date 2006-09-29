package wifky::nikky;

# use strict; use warnings;

my $version='0.19 ($Date: 2006/09/29 16:33:05 $)';
my ($nextday , $prevday , $nextmonth , $prevmonth , $startday , $endday );
my $ss_terminater=(%main::ss ? $main::ss{terminator} : 'terminator');
my $ss_copyright =(%main::ss ? $main::ss{copyright}  : 'copyright footer');

$main::inline_plugin{'nikky.pl_version'} = sub{ "nikky.pl $version" };
$main::inline_plugin{lastdiary}=\&lastdiary;
$main::inline_plugin{olddiary}=\&olddiary;
$main::inline_plugin{newdiary}=\&newdiary;
$main::inline_plugin{recentdiary}=\&recentdiary;
$main::inline_plugin{referer}=\&referer;
$main::inline_plugin{calender}= \&calender;
$main::inline_plugin{prevday}=\&prevday;
$main::inline_plugin{nextday}=\&nextday;
$main::inline_plugin{prevmonth}=\&prevmonth;
$main::inline_plugin{nextmonth}=\&nextmonth;
$main::inline_plugin{startday}=\&startday;
$main::inline_plugin{endday}=\&endday;
$main::inline_plugin{a_nikky} = sub {
    qq(<a href="$main::me?a=nikky">) .  join(' ',@_[1..$#_]) . '</a>';
};
$main::inline_plugin{nikky_comment} = sub {
    $main::form{p} =~ /^\(\d\d\d\d\.\d\d.\d\d\)/ ? &main::plugin_comment(@_) : '';
};
$main::inline_plugin{nikky_referer} = sub {
    $main::form{p} =~ /^\(\d\d\d\d\.\d\d.\d\d\)/ ? &wifky::nikky::referer(@_) : '';
};

$main::action_plugin{rss} = \&action_rss ;
$main::action_plugin{new} = \&action_newdiary;
$main::action_plugin{nikky} = \&action_nikky ;
$main::action_plugin{date} = \&action_date;

exists $main::form{date} and $main::form{a}='date';

if( &main::is('nikky_front') && 
    !exists $main::form{a} && !exists $main::form{p} )
{
    $main::form{a} = 'nikky';
}

if( $main::form{a} eq 'date' || $main::form{a} eq 'nikky' ){
    @main::menubar = grep( $_ !~ /Edit/ , @main::menubar );
}

$main::preferences{"Plugin: nikky.pl $version"}= [
    { desc=>'Author'                   
    , name=>'nikky_author' , size=>20 },
    { desc=>'Print diary as FrontPage'    
    , name=>'nikky_front' , type=>'checkbox'} ,
    { desc=>'Days of top diary'            
    , name=>'nikky_days', size=>1 },
    { desc=>'1-section to 1-rss-item'      
    , name=>'nikky_rssitemsize' , type=>'checkbox' } ,
    { desc=>'RSS description' 
    , name=>'nikky_rss_description' , size=>30 } ,
    { desc=>'insert hh:mm into title'      
    , name=>'nikky_insert_hhmm' , type=>'checkbox' } ,

    { desc=>'Symbol of start day link'  
    , name=>'nikky_symbolstartdaylink' , size=>2 },
    { desc=>'Symbol of previous month link'
    , name=>'nikky_symbolprevmonthlink', size=>2 },

    { desc=>'Symbol of previous day link'  
    , name=>'nikky_symbolprevdaylink', size=>2 },
    { desc=>'Symbol of next day link'      
    , name=>'nikky_symbolnextdaylink', size=>2 },
    { desc=>'Symbol of next month link'    
    , name=>'nikky_symbolnextmonthlink', size=>2 },
    { desc=>'Symbol of end day link'      
    , name=>'nikky_symbolenddaylink' , size=>2 } ,

    { desc=>'Print month with English'     
    , name=>'nikky_calendertype' , type=>'checkbox' },
];


### RSS Feed ###
push( @main::html_header ,
    qq(<link rel="alternate" type="application/rss+xml"
        title="RSS" href="$main::me?a=rss">) );

unshift( @main::copyright ,
    qq(Powered by nikky.pl ${version}
    <a href="$main::me?a=rss" style="border-width:1px;border-color:white;border-style:solid;font-size:small;font-weight:bold;text-decoration:none;background-color:darkorange;color:white;font-style:normal">RSS</a><br>)
);

### Next/Prev bar ###
&set_nextprev;

sub nikky_core{
    my $days = shift;
    my @list=&main::ls_core( { r=>1 } , '(????.??.??)*' );
    my @tm=localtime(time+24*60*60);
    my $tomorrow=sprintf('(%04d.%02d.%02d)',1900+$tm[5],1+$tm[4],$tm[3]);
    @list = grep( $_->{title} lt $tomorrow && -f $_->{fname} , @list );
    splice(@list,$days) if $#list > $days;
    splice(@list,10) if $#list > 10;
    &concat_article( @list );
}

sub nikky_core_r{
    my $days = shift;
    my @list = reverse &main::ls_core( { number=>$days } , '(????.??.??)*' );
    splice(@list,10) if $#list > 10;
    &concat_article( @list );
}

sub nikky_core_n{
    my $days = shift;
    my @list=&main::ls_core( { r=>1 , number=>$days } , '(????.??.??)*' );
    splice(@list,10) if $#list > 10;
    &concat_article( @list );
}

sub action_date{
    my $ymd=$main::form{date};
    my @list=&main::ls_core({},sprintf('(%2s.%2s.%2s)*',unpack('A4A2A2',$ymd)));

    &main::print_header( userheader=>'YES' );
    &concat_article( @list );
    &main::puts(qq(<div class="$ss_copyright">),@::copyright,'</div>');
    &main::print_sidebar_and_footer;
}

sub concat_article{
    my $h = ( $main::version ge '1.1' || &main::is('cssstyle') ? 2 : 1 );
    foreach my $p (@_){
        next unless -f $p->{fname};
        my $pagename=$p->{title};
        &main::puts('<div class="day">');
        &main::putenc('<h%d><a href="%s">%s</a></h%d><div class="body">',
                    $h , &main::title2url( $pagename ) , $pagename , $h );
        local $main::form{p} = $pagename;
        &main::print_page( title=>$pagename );
        &main::puts('</div></div>');
        &main::print_page( title=>'Footer' , class=>$ss_terminater );
    }
}

sub lastdiary{
    local $main::inline_plugin{lastdiary}=sub{};
    local $main::print='';
    &nikky_core($#_ >= 1 ? $_[1] : 3);
    $main::print;
}

sub olddiary{
    local $main::inline_plugin{olddiary}=sub{};
    local $main::print='';
    &nikky_core_r($#_ >= 1 ? $_[1] : 3);
    $main::print;
}

sub newdiary{
    local $main::inline_plugin{newdiary}=sub{};
    local $main::print='';
    &nikky_core_n($#_ >= 1 ? $_[1] : 3);
    $main::print;
}

sub action_nikky{
    &main::print_header( userheader=>'YES' );
    &nikky_core($main::config{nikky_days} || 3);
    &main::puts(qq(<div class="$ss_copyright">),@::copyright,'</div>');
    &main::print_sidebar_and_footer;
}

sub recentdiary{
    my ($session,$day)=@_;
    my @list=&main::ls_core({ r=>1 , number=>$day } , '(????.??.??)*' );
    if( $#list >= 0 ){
        "<ul>\r\n" . join('' , map( sprintf('<li><a href="%s">%s</a></li>',
                                &main::title2url($_->{title}) ,
                                &main::enc($_->{title}) ) , @list ))
        . "</ul>\r\n";
    }else{
        '';
    }
}

sub referer{
    my $session=shift;
    my @exclude=@_;
    my @title=($main::form{p} || 'FrontPage' , 'referer.txt' );
    my $ref=$ENV{'HTTP_REFERER'};

    my @lines=split(/\n/,&main::read_object(@title));
    if( $ref && $ref !~ /$main::me\?[aq]=/ &&
        grep(index($ref,$_) >= 0 , @exclude) <= 0 )
    {
        my $found=0;
        foreach my $line ( @lines ){
            my ($cnt,$site)=split(/\t/,$line,2);
            if( $site eq $ref ){
                $found = 1;
                $line = sprintf("%4d\t%s",$cnt + 1,$site);
                last;
            }
        }
        $found or push(@lines,sprintf("%4d\t%s",1,$ref));
        unless( $::referer_written ){
            &main::write_object(@title,join("\n",reverse sort @lines));
            $::referer_written = 1;
        }
    }
    if( $#lines >= 0 ){
        '<div class="referer"><ul class="referer">' .
        join("\r\n",reverse sort map('<li>'.&main::enc($_).'</li>',@lines) ) .
        '</ul></div>';
    }else{
        '';
    }
};

sub action_rss{
    my $URL=$main::me='http://'.$ENV{'HTTP_HOST'}.$ENV{'SCRIPT_NAME'};
    my $articles=5;
    $main::inline_plugin{comment} = sub { '' };

    %::enclist = (
        'lp' => '&#40;' ,
        'rp' => '&#41;' ,
        'lb' => '&#91;' ,
        'rb' => '&#93;' ,
        'll' => '&#40;&#40;' ,
        'rr' => '&#41;&#41;' ,
        'vl' => '&#124;' ,
    );
    my @pagelist = &main::ls_core( { r=>1 , number=>$articles } , '(????.??.??)*' );

    my $last_modified=0;
    foreach my $p (@pagelist){
        next unless -f $p->{fname};
        my $tm=(stat($p->{fname}))[9];
        $last_modified < $tm and $last_modified = $tm;
        $p->{timestamp} = $tm;

        my $attachment = {};
        foreach my $attach ( &main::list_attachment($p->{title}) ){
            my $e_attach = &main::enc( $attach );
            my $url=sprintf('http://%s%s?p=%s&amp;f=%s' ,
                    $ENV{'HTTP_HOST'} ,
                    $ENV{'SCRIPT_NAME'} ,
                    &main::percent( $p->{title} ) ,
                    &main::percent( $attach )
            );
            $attachment->{ $e_attach } = {
                name => $attach ,
                url  => $url ,
                tag  => $attach =~ /\.(png|gif|jpg|jpeg)$/i
                        ? qq(<img src="${url}" alt="${e_attach}">)
                        : qq(<a href="${url}" title="${e_attach}">${e_attach}</a>) ,
            };
        }
        $p->{attachment} = $attachment;
    }

    printf qq{Content-Type: application/rss+xml; charset=%s\r\n} , $main::charset ;
    printf qq{Last-Modified: %s\r\n\r\n} , &stamp_format($last_modified);
    printf qq{<?xml version="1.0" encoding="%s" ?>\r\n} , $main::charset ;
    print  qq{<rdf:RDF\r\n};
    print  qq{ xmlns="http://purl.org/rss/1.0/"\r\n};
    print  qq{ xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"\r\n};
    print  qq{ xmlns:dc="http://purl.org/dc/elements/1.1/"\r\n};
    print  qq{ xml:lang="ja">\r\n};
    printf qq{<channel rdf:about="%s?a=rss">\r\n} , $URL;
    printf qq{<title>%s</title>\r\n} , &main::enc($main::config{sitename});
    printf qq{<link>%s</link>\r\n} , $URL;
    printf qq{<description>%s</description>\r\n}
            , &main::enc($main::config{nikky_rss_description}) ;
    printf qq{<items>\r\n};
    printf qq{<rdf:Seq>\r\n};

    ### read title list ###
    my @topics;
    foreach my $p (@pagelist){
        my $text = &main::enc( &main::read_object($p->{title}) );

        $text =~ s!^\s*\&lt;pre&gt;(.*?\n)\s*\&lt;/pre&gt;|^\s*8\&lt;(.*?\n)\s*\&gt;8|`(.)`(.*?)`\3`!
                      defined($4)
                    ? &main::verb('<tt class="pre">'.&main::cr2br($4).'</tt>')
                    : "\n\n<pre>".&main::verb($1||$2)."</pre>\n\n"
                !gesm;
        local $/="\n\n";

        my $title=undef;
        my $pageurl = &main::percent($p->{title});
        my $id=0;
        my $desc=[];

        if( &main::is('nikky_rssitemsize') ){
            ### 1 section to 1 rssitem ###

            foreach my $frag ( split(/\r?\n\r?\n/,$text) ){
                if( $frag =~ /^\s*&lt;&lt;(?!&lt;)(.*)&gt;&gt;\s*$/s ||
                    $frag =~ /^!!!(.*)$/s )
                {
                    if( scalar(@{$desc}) > 0 ){
                        push(@topics ,
                            $id == 0 ? +{
                                page  => $p->{title} ,
                                url   => sprintf('%s?p=%s',$URL,$pageurl),
                                title => $p->{title} ,
                                timestamp => $p->{timestamp},
                                desc  => $desc ,
                                attachment => $p->{attachment} ,
                            } : +{
                                page  => $p->{title} ,
                                url   => sprintf('%s?p=%s#p%d',$URL,$pageurl,$id),
                                title => $title ,
                                timestamp => $p->{timestamp},
                                desc  => $desc ,
                                attachment => $p->{attachment} ,
                            }
                        );
                    }
                    ++$id;
                    $title = &main::preprocess($1,{ attachment=>{} } );
                    $title =~ s|\a((?:[0-9a-f][0-9a-f])*)\a|pack('h*',$1)|ges;
                    $title =~ s/\<[^\>]*\>\s*//g;
                    $desc = [];
                }
                push(@{$desc}, $frag );
            }
            if( scalar(@{$desc}) > 0 ){
                push(@topics ,
                    $id == 0 ? +{
                        page  => $p->{title} ,
                        url   => sprintf('%s?p=%s',$URL,$pageurl),
                        title => $p->{title} ,
                        timestamp => $p->{timestamp},
                        desc  => $desc ,
                        attachment => $p->{attachment} ,
                    } : +{
                        page  => $p->{title} ,
                        url   => sprintf('%s?p=%s#p%d',$URL,$pageurl,$id),
                        title => $title ,
                        timestamp => $p->{timestamp},
                        desc  => $desc ,
                        attachment => $p->{attachment} ,
                    }
                );
            }
        }else{
            ### blog-mode ( 1 page to 1 rss-item) ###
            push(@topics , +{
                    page  => $p->{title} ,
                    url   => sprintf('%s?p=%s',$URL,$pageurl),
                    title => $p->{title} ,
                    timestamp => $p->{timestamp},
                    desc  => [ $text ] ,
                    attachment => $p->{attachment} ,
                } 
            );
        }
    }

    ### write list ###
    print map(qq(<rdf:li rdf:resource=").$_->{url}.qq("/>\n),@topics);

    print "</rdf:Seq>\r\n";
    print "</items>\r\n";
    print "</channel>\r\n";

    ### write description ###
    foreach my $t (@topics){
        my @tm=gmtime($t->{timestamp});
        printf qq{<item rdf:about="%s">\r\n}, $t->{url};
        printf qq{<title>%s</title>\r\n} , &main::enc($t->{title});
        printf qq{<link>%s</link>\r\n} , $t->{url};
        printf qq{<lastBuildDate>%s</lastBuildDate>\r\n}
            ,&stamp_format( $t->{timestamp} );
        printf qq{<pubDate>%s</pubDate>\r\n}
            , &stamp_format( $t->{timestamp} );
        printf qq{<author>%s</author>\r\n}
            , &main::enc($main::config{'nikky_author'});
        printf qq{<dc:creator>%s</dc:creator>\r\n}
            , &main::enc($main::config{'nikky_author'});
        printf qq{<dc:date>%04d-%02d-%02dT%02d:%02d:%02d+00:00</dc:date>\r\n}
            , $tm[5]+1900,$tm[4]+1,@tm[3,2,1,0] ;
        for(my $s=$t->{title} ; $s =~ /\[([^\]]+)\]/ ; $s=$' ){
            print "<category>$1</category>\r\n";
        }
        local $main::print='';
        print  '<description><![CDATA[';
        &main::syntax_engine(
            join("\n\n",@{$t->{desc}}) ,
            { title => $t->{title} , attachment => $t->{attachment} }
        );
        &main::flush;
        print  "]]></description>\r\n</item>\r\n";
    }
    print "</rdf:RDF>\r\n";
    exit(0);
};

sub quote1{
    my ($session,$a,$f)=@_;
    my @params;
    while( $#{$a} >= 0 && (my $t=shift(@{$a})) ne ')' ){
        push(@params, $t eq '(' ?  &quote1($session,$a) : $t);
    }
    my $name=shift(@params);
    $f || ( exists $main::inline_plugin{$name}
            ? &{$main::inline_plugin{$name}}($session,@params)
            : 'Plugin Not Found!' );
}

sub quote{
    my ($session,$a,$f)=@_;
    my $t=shift(@{$a});
    if( $t && $t eq '(' ){
        quote1($session,$a,$f)
    }else{
        $f || $t;
    }
}

sub set_nextprev{
    my $p=$main::form{p};
    if( exists $main::form{date} ){
        $p = sprintf('(%04s.%02s.%02s)',unpack('A4A2A2',$main::form{date}) );
    }elsif( ! defined($p) || $p !~ /^\(\d\d\d\d.\d\d.\d\d\)/ ){
        my @tm=localtime(time);
        $p = sprintf( "(%04d.%02d.%02d)\xFF", 1900+$tm[5], 1+$tm[4], $tm[3] );
    }
    my $cur=&main::title2fname($p);
    my $month_first=&main::title2fname( substr($p,0,9).'01)' );
    my $month_end=&main::title2fname( substr($p,0,9).'31)\xFF' );

    foreach my $t ( grep( /^822303/ , &main::list_page() ) ){
        if( $t lt $cur && ( !defined($prevday) || $t gt $prevday ) ){
            $prevday = $t;
        }elsif( $t gt $cur && ( !defined($nextday) || $t lt $nextday ) ){
            $nextday = $t;
        }
        if( $t lt $month_first && ( !defined($prevmonth) || $t gt $prevmonth ) ){
            $prevmonth = $t;
        }
        if( $t gt $month_end && ( !defined($nextmonth) || $t lt $nextmonth ) ){
            $nextmonth = $t;
        }
    }
    if( $prevday ){
        $prevday = &main::title2url(&main::fname2title($prevday));
        push(@main::html_header,qq(<link rel="prev" href="${prevday}">));
    }
    unshift(@main::menubar,&prevday);
    if( $nextday ){
        $nextday= &main::title2url(&main::fname2title($nextday));
        push(@main::html_header,qq(<link rel="next" href="${nextday}">));
    }
    push(@main::menubar,&nextday);

    $prevmonth &&= &main::title2url(&main::fname2title($prevmonth));
    $nextmonth &&= &main::title2url(&main::fname2title($nextmonth));

    ### Startday
    my ($day) = &main::ls_core( { number=>1 }, '(????.??.??)*' );
    $startday = &main::title2url( $day->{title} );

    ### Endday
    ($day) = &main::ls_core( { r=>1, number=>1 }, '(????.??.??)*' );
    $endday   = &main::title2url( $day->{title} );
}

sub date_anchor{
    my ($xxxxday,$date_url,$default_mark,$symbol)=@_;
    $symbol ||= &main::enc($main::config{"nikky_symbol${xxxxday}link"}||$default_mark);
    !$symbol ? ''
    : $date_url 
    ? qq(<a href="${date_url}">${symbol}</a>) 
    : qq(<span class="no${xxxxday}">$symbol</span>) ;
}

sub prevday  { &date_anchor('prevday'  ,$prevday   ,'<' , $_[1]); }
sub nextday  { &date_anchor('nextday'  ,$nextday   ,'>' , $_[1]); }
sub prevmonth{ &date_anchor('prevmonth',$prevmonth ,'<<', $_[1]); }
sub nextmonth{ &date_anchor('nextmonth',$nextmonth ,'>>', $_[1]); }
sub startday { &date_anchor('startday' ,$startday  ,'|' , $_[1]); }
sub endday   { &date_anchor('endday'   ,$endday    ,'|' , $_[1]); }

sub action_newdiary{
    my @tm = localtime;
    &main::print_header( divclass=>'max' );
    my $default_title=sprintf('(%04d.%02d.%02d)' ,
         $tm[5]+1900,$tm[4]+1,$tm[3] );
    if( &main::is('nikky_insert_hhmm') ){
        $default_title .= sprintf(' %02d:%02d',$tm[2],$tm[1]);
    }

    &main::putenc('<form action="%s" method="post"
        ><h1>Create Page</h1><p
        ><input type="hidden" name="a" value="edt"
        ><input type="text" name="p" value="%s" size="40"
        ><input type="submit"></p></form>'
        , $main::me , $default_title );
    &main::print_footer;
}

sub query_wday { ### query week day.
    my ($y,$m) = @_;
    my ($zy,$zm)=( $m<=2 ? ($y-1,12+$m) : ($y,$m) );

    ( $zy + int($zy/4) - int($zy/100) + int($zy/400) + int((13*$zm+ 8)/5)+1)%7;
}

sub query_days_in_month{
    my ($y,$m) = @_;
    my @mdays = (0,31,
          $y % 400 == 0 ? 29
        : $y % 100 == 0 ? 28
        : $y %   4 == 0 ? 29
        : 28 ,
    ,31,30,31,30   ,   31,31,30,31,30,31);

    $mdays[ $m ];
}

sub put_1day{
    my ($tag,$y,$m,$d,$wday,$today,$thismonth,$buffer)=@_;
    $$buffer .= sprintf('<%s align="right" class="%s%s">' ,
            $tag ,
            ( qw(Sun Mon Tue Wed Thu Fri Sat) )[$wday] ,
            $today eq $d ? ' Today' : '' );

    if( exists $thismonth->{$d} ){
        $$buffer .= sprintf('<a href="%s?date=%04d%02d%02d">%s</a>'
                        , $main::me , $y , $m , $d , $d);
    }else{
        $$buffer .= $d;
    }
    $$buffer .= "</$tag> ";
}

sub query_current_month{
    my @r;
    if( defined($main::form{p}) &&
        $main::form{p} =~ /^\((\d\d\d\d)\.(\d\d)\.(\d\d)\)/ ){
        @r=($1,$2,$3);
    }elsif( defined($main::form{date}) && 
        $main::form{date} =~ /^(\d\d\d\d)(\d\d)(\d\d)$/ ){
        @r=($1,$2,$3);
    }else{
        my ($y,$m,$today)=(localtime)[5,4,3];
        @r=($y + 1900 , $m+1 , $today );
    }
    $r[2] =~ s/^0//;
    @r;
}

sub calender{
    my $session=shift;
    my ($y,$m,$today) = &query_current_month();
    my $mode;
    while( defined(my $argv = shift) ){
        if( $argv =~ /^\d\d$/ ){
            $m = $argv;
            $today = 0; # never match number
        }elsif( $argv =~ /^\d\d\d\d$/ ){
            $y = $argv;
            $today = 0; # never match number
        }else{
            $mode = $argv;
        }
    }
    my $wday = &query_wday($y,$m);
    my $max_mdays = &query_days_in_month($y,$m);

    my %thismonth = map{ 
        my $d=substr($_->{title},9,2); $d =~ s/^0//; ($d,$_);
    } &main::ls_core( {} , sprintf('(%04d.%02d.??)*',$y,$m));

    my $title;
    if( &main::is('nikky_calendertype') ){
        $title = sprintf('%s %d' ,
                    (qw(January Feburary March April May June
                        July August September October November December)
                    )[$m-1] , $y );
    }else{
        $title = sprintf('%d/%d',$y,$m);
    }

    if( defined($mode) && $mode eq 'f' ) {
        my $buffer = sprintf(
            '<div class="calender_flat"><span class="calender_header">%s%s %s/</span>'
            , &startday()
            , $main::inline_plugin{prevmonth}->($session)
            , $title 
        );
        foreach my $d (1..$max_mdays){
            &put_1day('span',$y,$m,$d,$wday,$today,\%thismonth,\$buffer);
            $wday = ($wday + 1) % 7;
        }
        $buffer . sprintf( '<span class="calender_footer">%s%s</span></div>'
            , $main::inline_plugin{nextmonth}->($session)
            , &endday()
        );
    }else{
        my $buffer = sprintf(
            '<table class="calender"><caption>%s%s %s %s%s</caption><tr nowrap>%s'
            , &startday()
            , $main::inline_plugin{prevmonth}->($session)
            , $title
            , $main::inline_plugin{nextmonth}->($session)
            , &endday()
            , '<td></td>'x $wday
        );
        foreach my $d (1..$max_mdays){
            if( $wday >= 7 ){
                $buffer .= "</tr>\n<tr nowrap>" ; $wday = 0;
            }
            &put_1day('td',$y,$m,$d,$wday,$today,\%thismonth,\$buffer);
            ++$wday;
        }
        $buffer . '<td></td>'x( 7-$wday ) . '</tr></table>';
    }
}


sub stamp_format{
    sprintf("%s, %02d %s %04d %s GMT",
        (split(/\s+/,gmtime( $_[0] )))[0,2,1,4,3]);
}

1;
