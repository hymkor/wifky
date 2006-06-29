package nikky;

# use strict; use warnings;

my $version='0.17.0 ($Date: 2006/06/29 15:55:02 $)';
my $nextday;
my $prevday;
my $nextmonth;
my $prevmonth;

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
$main::inline_plugin{a_nikky} = sub {
    qq(<a href="$main::me?a=nikky">) .  join(' ',@_[1..$#_]) . '</a>';
};
$main::inline_plugin{nikky_comment} = sub {
    $main::form{p} =~ /^\(\d\d\d\d\.\d\d.\d\d\)/ ? &main::plugin_comment(@_) : '';
};
$main::inline_plugin{nikky_referer} = sub {
    $main::form{p} =~ /^\(\d\d\d\d\.\d\d.\d\d\)/ ? &nikky::referer(@_) : '';
};

$main::action_plugin{rss} = \&action_rss ;
$main::action_plugin{newdiary} = \&action_newdiary;
$main::action_plugin{nikky} = \&action_nikky ;
$main::action_plugin{date} = \&action_date;

exists $main::form{date} and $main::form{a}='date';

if( exists $main::config{nikky_front}  &&
    $main::config{nikky_front} eq 'OK' &&
    !exists $main::form{a}             &&
    !exists $main::form{p} )
{
    $main::form{a} = 'nikky';
}

$main::preferences{'Plugin: nikky.pl'}= [
    { desc=>'Author' , type=>'text' , name=>'nikky_author' , size=>20 },
    { desc=>'Print diary as FrontPage' , type=>'checkbox' ,
        name=>'nikky_front' } ,
    { desc=>'Days of top diary' , type=>'text' , name=>'nikky_days', size=>1 },
    { desc=>'1-section to 1-rss-item' , type=>'checkbox' , name=>'nikky_rssitemsize' } ,
    { desc=>'Symbol of prev day link' , type=>'text' , name=>'nikky_symbolprevdaylink', size=>2 },
    { desc=>'Symbol of next day link' , type=>'text' , name=>'nikky_symbolnextdaylink', size=>2 },
    { desc=>'Symbol of prev month link' , type=>'text' , name=>'nikky_symbolprevmonthlink', size=>2 },
    { desc=>'Symbol of next month link' , type=>'text' , name=>'nikky_symbolnextmonthlink', size=>2 },
    { desc=>'Print symbol, if "prevday link" and "nextday link" terminate.' , type=>'checkbox' , name=>'nikky_daylinkterminate' } ,
    { desc=>'Print symbol, if "prevmonth link" and "nextmonth link" terminate.' , type=>'checkbox' , name=>'nikky_monthlinkterminate' } ,
];


### RSS Feed ###
push( @main::html_header ,
    qq(<link rel="alternate" type="application/rss+xml"
        title="RSS" href="$main::me?a=rss">) );

unshift( @main::copyright ,
    qq(Powered by nikky.pl ${version}
    <a href="$main::me?a=rss" style="border-width:1px;border-color:white;border-style:solid;font-size:small;font-weight:bold;text-decoration:none;background-color:darkorange;color:white;font-style:normal">RSS</a><br>)
);

grep( (/New/ and $_=qq(<a href="$main::me?a=newdiary">New</a>) )
    , @main::menubar );

### Next/Prev bar ###
&set_nextprev;

sub nikky_core{
    my $days = shift;
    my @list=&main::ls_core( { r=>1 } , '(????.??.??)*' );
    my @tm=localtime(time+24*60*60);
    my $tomorrow=sprintf('(%04d.%02d.%02d)',1900+$tm[5],1+$tm[4],$tm[3]);
    @list = grep( $_->{title} lt $tomorrow , @list );
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
    &main::puts('<div class="'.$main::ss{copyright}.'">',@::copyright,'</div>');
    &main::print_sidebar_and_footer;
}

sub concat_article{
    my $h = (exists $main::config{cssstyle} && $main::config{cssstyle} eq 'OK'
                ? 2 : 1);
    foreach my $p (@_){
        my $pagename=$p->{title};
        &main::puts('<div class="day">');
        &main::putenc('<h%d><a href="%s">%s</a></h%d><div class="body">',
                    $h , &main::title2url( $pagename ) , $pagename , $h );
        local $main::form{p} = $pagename;
        &main::print_page( title=>$pagename );
        &main::puts('</div></div>');
        &main::print_page( title=>'Footer' , class=>$main::ss{terminator} );
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
    &main::puts('<div class="'.$main::ss{copyright}.'">',@::copyright,'</div>');
    &main::print_sidebar_and_footer;
}

sub recentdiary{
    my ($session,$day)=@_;
    my @list=&main::ls_core({ r=>1 , number=>$day } , '(????.??.??)*' );
    if( $#list >= 0 ){
        "<ul>\n" . join('' , map( sprintf('<li><a href="%s">%s</a></li>',
                                &main::title2url($_->{title}) ,
                                &main::enc($_->{title}) ) , @list ))
        . "</ul>\n";
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
    my $URL=$main::me=
        sprintf('http://%s%s', $ENV{'HTTP_HOST'} , $ENV{'SCRIPT_NAME'} );
    my $RSS="$URL?a=rss";
    my $articles=5;
    $main::inline_plugin{comment} = sub { '' };

    %::enclist = (
        'lp'       => '&#40;' ,
        'rp'       => '&#41;' ,
        'lb'       => '&#91;' ,
        'rb'       => '&#93;' ,
        'll'       => '&#40;&#40;' ,
        'rr'       => '&#41;&#41;' ,
        'vl'       => '&#124;' ,
    );
    my $sitename=$main::config{sitename};

    ### read page list ###
    my @pagelist = map(
        { fname=>$_ , title=> &main::fname2title($_) }
        , &main::list_page()
    );
    @pagelist = sort{ $a->{title} cmp $b->{title} }
        grep( $_->{title} =~ /^\(\d\d\d\d\.\d\d\.\d\d\)/ , @pagelist );
    splice(@pagelist,0,-$articles);

    my $last_modified=0;
    foreach my $p (@pagelist){
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

    print  "Content-Type: application/rss+xml; charset=EUC-JP\n";
    printf "Last-Modified: %s\n\n",&stamp_format($last_modified);

    print qq(<?xml version="1.0" encoding="EUC-JP" ?>
<rdf:RDF
  xmlns="http://purl.org/rss/1.0/"
  xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
  xmlns:dc="http://purl.org/dc/elements/1.1/"
  xml:lang="ja">
 <channel rdf:about="${RSS}">
  <title>${sitename}</title>
  <link>${URL}</link>
  <description>${sitename}</description>
  <items>
   <rdf:Seq>
);

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

        if( $main::config{'nikky_rssitemsize'} && 
            $main::config{'nikky_rssitemsize'} ne 'NG' )
        {
            ### 1 section to 1 rssitem ###

            foreach my $frag ( split(/\r?\n\r?\n/,$text) ){
                if( $frag =~ /^\s*&lt;&lt;(?!&lt;)(.*)&gt;&gt;\s*$/s ||
                    $frag =~ /^!!!(.*)$/s )
                {
                    if( scalar(@{$desc}) > 0 ){
                        unshift(@topics ,
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
                unshift(@topics ,
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
            unshift(@topics , +{
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

    print "</rdf:Seq>\n";
    print "</items>\n";
    print "</channel>\n";

    ### write description ###
    foreach my $t (@topics){
        printf qq(<item rdf:about="%s">\n),$t->{url} ;
        printf "<title>%s</title>\n"
                , &main::enc($t->{title}) ;
        printf qq(<link>%s</link>\n),$t->{url} ;
        for(my $s=$t->{title} ; $s =~ /\[([^\]]+)\]/ ; $s=$' ){
            print "<category>$1</category>\n";
        }
        printf "<lastBuildDate>%s</lastBuildDate>\n"
                , &stamp_format( $t->{timestamp} );
        printf "<pubDate>%s</pubDate>\n"
                , &stamp_format( $t->{timestamp} );
        printf "<author>%s</author>\n"
                , $main::config{'nikky_author'} || $sitename;
        printf "<dc:creator>%s</dc:creator>\n"
                , $main::config{'nikky_author'} || $sitename;
        my @tm=gmtime($t->{timestamp});
        printf "<dc:date>%04d-%02d-%02dT%02d:%02d:%02d+00:00</dc:date>\n"
                , $tm[5]+1900,$tm[4]+1,@tm[3,2,1,0] ;
        local $main::print='';
        print  '<description><![CDATA[';
        &main::syntax_engine(
            join("\n\n",@{$t->{desc}}) ,
            { title => $t->{title} , attachment => $t->{attachment} }
        );
        &main::flush;
        print  "]]></description>\n</item>\n";
    }
    print "</rdf:RDF>\n";
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
    foreach my $t ( &main::list_page() ){
        next if $t !~ /^822303/;
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
        push(@main::html_header,qq(<link rel="prevday" href="${prevday}">));
    }
    unshift(@main::menubar,&prevday);
    if( $nextday ){
        $nextday= &main::title2url(&main::fname2title($nextday));
        push(@main::html_header,qq(<link rel="nextday" href="${nextday}">));
    }
    push(@main::menubar,&nextday);
    if( $prevmonth ){
        $prevmonth = &main::title2url(&main::fname2title($prevmonth));
        push(@main::html_header,qq(<link rel="prevmonth" href="${prevmonth}">));
    }
    unshift(@main::menubar,&prevmonth);
    if( $nextmonth ){
        $nextmonth= &main::title2url(&main::fname2title($nextmonth));
        push(@main::html_header,qq(<link rel="nextmonth" href="${nextmonth}">));
    }
    push(@main::menubar,&nextmonth);
}

sub prevday{
    my $symbol = $main::config{nikky_symbolprevdaylink} || '&lt;&lt;';
    $prevday ? qq(<a href="${prevday}">).$symbol.'</a>'
    : ( $main::config{'nikky_daylinkterminate'} &&
        $main::config{'nikky_daylinkterminate'} ne 'NG'
	? $symbol : ''
    );
}

sub nextday{
    my $symbol = $main::config{nikky_symbolnextdaylink} || '&gt;&gt;';
    $nextday ? qq(<a href="${nextday}">).$symbol.'</a>'
    : ( $main::config{'nikky_daylinkterminate'} &&
        $main::config{'nikky_daylinkterminate'} ne 'NG'
	? $symbol : ''
    );
}

sub prevmonth{
    my $symbol = $main::config{nikky_symbolprevmonthlink} || '&lt;-';
    $prevmonth ? qq(<a href="${prevmonth}">).$symbol.'</a>'
    : ( $main::config{'nikky_monthlinkterminate'} &&
        $main::config{'nikky_monthlinkterminate'} ne 'NG'
	? $symbol : ''
    );
}

sub nextmonth{
    my $symbol = $main::config{nikky_symbolnextmonthlink} || '-&gt;';
    $nextmonth ? qq(<a href="${nextmonth}">).$symbol.'</a>'
    : ( $main::config{'nikky_monthlinkterminate'} &&
        $main::config{'nikky_monthlinkterminate'} ne 'NG'
	? ($_[1] || '&lt;-') : ''
    );
}

sub action_newdiary{
    my @tm = localtime;
    &main::print_header( divclass=>'max' );
    &main::putenc(qq(<form action="%s" method="post"
        ><h1>Create Page</h1><p
        ><input type="hidden" name="a" value="edt"
        ><input type="text" name="p" value="(%04d.%02d.%02d)" size="40"
        ><input type="submit"></p></form>)
        , $main::me , $tm[5]+1900,$tm[4]+1,$tm[3] );
    &main::print_footer;
}

sub calender{
    my ($y,$m,$today);
    if( defined($main::form{p}) &&
        $main::form{p} =~ /^\((\d\d\d\d)\.(\d\d)\.(\d\d)\)/ ){
        ($y,$m,$today)=($1,$2,$3);
    }elsif( defined($main::form{date}) && 
        $main::form{date} =~ /^(\d\d\d\d)(\d\d)(\d\d)$/ ){
        ($y,$m,$today)=($1,$2,$3);
    }else{
        ($y,$m,$today)=(localtime)[5,4,3];
        $y += 1900 ; ++$m; $today = sprintf('%02d',$today);
    }
    my ($zy,$zm)=( $m<=2 ? ($y-1,12+$m) : ($y,$m) );

    my $wday=(   $zy + int($zy/4) - int($zy/100) + int($zy/400)
                + int((13*$zm+ 8)/5)+1)%7;
    my @mdays = (0,31,
          $y % 400 == 0 ? 29
        : $y % 100 == 0 ? 28
        : $y %   4 == 0 ? 29
        : 28 ,
    ,31,30,31,30   ,   31,31,30,31,30,31);

    my $r=&main::title2fname(sprintf('(%04d.%02d.',$y,$m));
    my %thismonth= map(
        (substr($_,9,2),$_) ,
        map(  &main::fname2title($_)
            , grep(substr($_,0,18) eq $r , &main::list_page() )
        )
    );

    my $buffer = sprintf(
        '<table class="calender"><caption>%s%s %d/%02d %s%s</caption><tr>%s'
	, &prevmonth
	, &prevday
        , $y
        , $m
	, &nextday
	, &nextmonth
        , '<td>'x($wday%7)
    );
    for(my $d=1;$d<=$mdays[$m];++$d){
        $buffer .= "</tr>\n<tr>" if $wday == 0 && $d > 1;
        my $title = sprintf('(%04d.%02d.%02d)',$y,$m,$d);
        my $D=sprintf('%02d',$d);
        $buffer .= sprintf('<td align="right" class="%s%s">' ,
                ( qw(Sun Mon Tue Wed Thu Fri Sat) )[$wday] ,
                $today eq $D ? ' Today' : '' );

        if( exists $thismonth{$D} ){
            $buffer .= sprintf('<a href="%s?date=%04d%02d%02d">%s</a></td>'
                                , $main::me , $y , $m , $d , $d);
        }else{
            $buffer .= qq($d</td>);
        }
        $wday = ($wday + 1) % 7;
    }
    $buffer . '<td></td>'x((7-$wday)%7) . '</tr></table>';
}

sub stamp_format{
    sprintf("%s, %02d %s %04d %s GMT",
        (split(/\s+/,gmtime( $_[0] )))[0,2,1,4,3]);
}

1;
