package wifky::nikky;

# use strict; use warnings;

$wifky::nikky::template ||= '
    <div class="main">
        <div class="header">
            &{header}
        </div><!-- header -->
        <div class="autopagerize_page_element">
            &{main} <!-- contents and footers -->
        </div>
        <div class="autopagerize_insert_before"></div>
        <div class="footest">
            %{Footest}
        </div>
        <div class="copyright footer">
            &{copyright}
        </div><!-- copyright -->
    </div><!-- main -->
    <div class="sidebar">
    %{Sidebar}
    </div><!-- sidebar -->
    &{message}';

my %nikky;
my @nikky;
my $version='1.1.1_1';
my ($nextday_url , $prevday_url , $nextmonth_url , $prevmonth_url , $startday_url , $endday_url );

if( exists $::menubar{'200_New'} ){
    my @now=localtime();
    if( ref($::menubar{'200_New'})){
        push( @{$::menubar{'200_New'}} ,
            sprintf( q|<a href="%s?a=today" onClick="JavaScript:if(document.newpage.p.value=prompt('Create a new diary','(%04d.%02d.%02d)')){document.newpage.submit()};return false;">Today</a>|,$::me,$now[5]+1900,$now[4]+1,$now[3] )
        );
    }else{
        push( @::body_header , qq|<form name="newdiary" action="$::me" method="post" style="display:none"><input type="hidden" name="p" /><input type="hidden" name="a" value="edt" /></form>| );
        $::menubar{'200_New'} = sprintf( q|<a href="%s?a=newdiary" onClick="JavaScript:if(document.newdiary.p.value=prompt('Create a new diary','(%04d.%02d.%02d)')){document.newdiary.submit()};return false;">New</a>|,$::me,$now[5]+1900,$now[4]+1,$now[3] );
    }
}

$::inline_plugin{'nikky.pl_version'} = sub{ "nikky.pl $version" };
$::inline_plugin{referer}     = \&inline_referer;
$::inline_plugin{prevday}     = \&inline_prevday;
$::inline_plugin{nextday}     = \&inline_nextday;
$::inline_plugin{startday}    = \&inline_startday;
$::inline_plugin{endday}      = \&inline_endday;
$::inline_plugin{a_nikky} = sub {
    qq(<a href="$::me?a=nikky">) .  join(' ',@_[1..$#_]) . '</a>';
};
$::inline_plugin{nikky_comment} = sub {
    (defined $::form{p} && $::form{p} =~ /^\(\d\d\d\d\.\d\d.\d\d\)/ )
    ? &::plugin_comment(@_) : '';
};
$::inline_plugin{nikky_referer} = sub {
    (defined $::form{p} && $::form{p} =~ /^\(\d\d\d\d\.\d\d.\d\d\)/ )
    ? &wifky::nikky::inline_referer(@_) : '';
};

$::form{a}='date' if $::form{date};

if( &::is('nikky_front') &&
    !exists $::form{a} && !exists $::form{p} )
{
    $::form{a} = 'nikky';
}

if( exists $::form{a} && ($::form{a} eq 'date' || $::form{a} eq 'nikky') ){
    delete $::menubar{'300_Edit'};
}

$::inline_plugin{read_more} = sub {
    if( $::form{a} && $::form{a} eq 'rss' ){
        &::anchor('(more...)',{ p=>$::form{p} } ) . '<!--- READ MORE --->';
    }else{
        '';
    }
};

$::preferences{'Nikky Plugin '.$version}= [
    { desc=>'Author'
    , name=>'nikky_author' , size=>20 },
    { desc=>'Print diary as FrontPage'
    , name=>'nikky_front' , type=>'checkbox'} ,
    { desc=>'Days of top diary'
    , name=>'nikky_days', size=>1 },

    { desc=>'RSS: 1-section to 1-rss-item'
    , name=>'nikky_rssitemsize' , type=>'checkbox' } ,
    { desc=>'RSS: description'
    , name=>'nikky_rss_description' , size=>30 } ,
    { desc=>'RSS: Output all articles not only (YYYY.MM.DD)*'
    , name=>'nikky_output_all_articles' , type=>'checkbox' },
    { desc=>'RSS: the number of pages to feed.' 
    , name=>'nikky_rss_feed_num' , size=>2 } ,

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

    { desc=>"RSS Feed ProxyURL (which is displayed instead of $::me?a=rss)" ,
    , name=>'nikky_display_rssurl'    , size=>30 },
];

### RSS Feed ###

my $rssurl = ($::config{'nikky_display_rssurl'} || "$::me?a=rss");

push( @::html_header ,
    qq(<link rel="alternate" type="application/rss+xml"
        title="RSS" href="$rssurl">) );

unshift( @::copyright ,
    qq(<div>Powered by nikky.pl ${version}
    <a href="$rssurl" class="rssurl">[RSS]</a></div>)
);

&init();

sub concat_article{
    # 引数で与えられた「ページ名」を全て Footer 付きで連結して出力する。
    # undef なページ名・本文が存在しないページは無視する。
    foreach my $p (@_){
        next unless defined $p && -f $p->{fname};
        my $pagename=$p->{title};
        &::puts('<div class="day">');
        &::putenc('<h2><span class="title"><a href="%s">%s</a></span></h2><div class="body">',
                    &::title2url( $pagename ) , $pagename );
        local $::form{p} = $pagename;
        &::print_page( title=>$pagename );
        &::puts('</div></div>');
        &::print_page( title=>'Footer' , class=>'terminator' );
    }
}

$::inline_plugin{lastdiary} = sub {
    local $::inline_plugin{lastdiary}=sub{};
    local $::print='';
    my $days = &nvl($_[1],3);
    my @list=&::ls_core( {} , '(????.??.??)*' );
    my @tm=localtime(time+24*60*60);
    my $tomorrow=sprintf('(%04d.%02d.%02d)',1900+$tm[5],1+$tm[4],$tm[3]);
    my @list=grep{ $_->{title} lt $tomorrow && -f $_->{fname} } @list;
    &concat_article( reverse( scalar(@list) > $days ? @list[-($days)..-1] : @list) );

    $::print;
};

$::inline_plugin{olddiary} = sub {
    local $::inline_plugin{olddiary}=sub{};
    local $::print='';
    my $days=&nvl($_[1],3);
    &concat_article( scalar(@nikky) > $days ? @nikky[0..($days-1)] : @nikky );
    $::print;
};

$::inline_plugin{newdiary} = sub {
    local $::inline_plugin{newdiary}=sub{};
    local $::print='';
    my $days=&nvl($_[1],3);
    &concat_article( reverse(scalar(@nikky) > $days ? @nikky[-($days)..-1] : @nikky) );
    $::print;
};

$::inline_plugin{recentdiary} = sub {
    my ($session,$day)=@_;
    my @list=&::ls_core({ r=>1 , number=>$day } , '(????.??.??)*' );
    if( $#list >= 0 ){
        "<ul>\r\n" . join('' , map( sprintf('<li><a href="%s">%s</a></li>',
                                &::title2url($_->{title}) ,
                                &::enc($_->{title}) ) , @list ))
        . "</ul>\r\n";
    }else{
        '';
    }
};

sub inline_referer{
    my $session=shift;
    my @exclude=@_;
    my @title=($::form{p} || 'FrontPage' , 'referer.txt' );
    return '' unless &::object_exists($title[0]);

    my $ref=$ENV{'HTTP_REFERER'};

    my @lines=split(/\n/,&::read_object(@title));
    if( !$wifky::nikky::referer_written &&
        $ref && $ref !~ /$::me\?[ap]=/ &&
        !grep(index($ref,$_) >= 0 , @exclude) )
    {
        foreach my $line ( @lines ){
            my ($cnt,$site)=split(/\t/,$line,2);
            if( $site eq $ref ){
                undef $ref;
                $line = sprintf("%4d\t%s",$cnt + 1,$site);
                last;
            }
        }
        push(@lines,sprintf("%4d\t%s",1,$ref)) if $ref;
        &::write_object(@title,join("\n",reverse sort @lines));
        $wifky::nikky::referer_written = 1;
    }
    if( @lines ){
        '<div class="referer"><ul class="referer">' .
        join("\r\n",reverse sort map('<li>'.&::enc($_).'</li>',@lines) ) .
        '</ul></div>';
    }else{
        '';
    }
};

$::action_plugin{rss}= sub {
    $::me = 'http://' . (
                    defined $ENV{'HTTP_HOST'}
                  ? $ENV{'HTTP_HOST'}
                  : defined $ENV{'SERVER_PORT'} && $ENV{'SERVER_PORT'} != 80
                  ? $ENV{'SERVER_NAME'} . ':' . $ENV{'SERVER_PORT'}
                  : $ENV{'SERVER_NAME'}
            ) . $ENV{'SCRIPT_NAME'};
    $::inline_plugin{comment} = sub { &::plugin_comment(@_,'-f'); };
    my $feed_num = ($::config{nikky_rss_feed_num} || 3);
    my @pagelist;
    if( $::config{nikky_output_all_articles} ){
        @pagelist = &::ls_core( { r=>1 , t=>1 , number=>$feed_num } );
    }else{
        @pagelist = &::ls_core( { r=>1 , number=>$feed_num } , '(????.??.??)*' );
    }

    my $last_modified=0;
    foreach my $p (@pagelist){
        next unless -f $p->{fname};
        my $tm=(stat($p->{fname}))[9];
        $last_modified < $tm and $last_modified = $tm;
        $p->{timestamp} = $tm;

        my $attachment = {};
        foreach my $attach ( &::list_attachment($p->{title}) ){
            my $e_attach = &::enc( $attach );
            my $url=sprintf('%s?p=%s&amp;f=%s' ,
                    $::me ,
                    &::percent( $p->{title} ) ,
                    &::percent( $attach )
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

    printf qq{Content-Type: application/rss+xml; charset=%s\r\n} , $::charset ;
    printf qq{Last-Modified: %s\r\n\r\n} , &stamp_format($last_modified);
    printf qq{<?xml version="1.0" encoding="%s" ?>\r\n} , $::charset ;
    print  qq{<rdf:RDF\r\n};
    print  qq{ xmlns="http://purl.org/rss/1.0/"\r\n};
    print  qq{ xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"\r\n};
    print  qq{ xmlns:content="http://purl.org/rss/1.0/modules/content/"\r\n};
    print  qq{ xmlns:dc="http://purl.org/dc/elements/1.1/"\r\n};
    print  qq{ xml:lang="ja">\r\n};
    printf qq{<channel rdf:about="%s?a=rss">\r\n} , $::me;
    &printag( title       => $::config{sitename} ,
              link        => $::me ,
              description => $::config{nikky_rss_description} );
    printf qq{<items>\r\n};
    printf qq{<rdf:Seq>\r\n};

    ### read title list ###
    my @topics;
    my %session4page;
    foreach my $p (@pagelist){
        my $text = &::enc( &::read_object($p->{title}) );
        my $session=($session4page{ $p->{title} } ||= { $p->{attachment} } );
        &::call_verbatim(\$text,$session);
        &::call_blockquote(\$text,$session) if defined &::call_blockquote;

        my $pageurl = &::percent($p->{title});
        my $id=0;
        my %item = (
            page  => $p->{title} ,
            url   => sprintf('%s?p=%s',$::me,$pageurl),
            title => $p->{title} ,
            timestamp => $p->{timestamp},
            desc  => [] ,
            attachment => $p->{attachment} ,
        );

        if( &::is('nikky_rssitemsize') ){
            ### 1 section to 1 rssitem ###

            foreach my $frag ( split(/\r?\n\r?\n/,$text) ){
                if( $frag =~ /^\s*&lt;&lt;(?!&lt;)(.*)&gt;&gt;\s*$/s ||
                    $frag =~ /^!!!(.*)$/s )
                {
                    push(@topics , { %item } ) if @{$item{desc}};

                    $item{url} = sprintf('%s?p=%s#p%d',$::me,$pageurl,++$id) ;
                    $item{desc} = [];
                    my $title = &::preprocess($1,$session);
                    if( defined &::unverb ){
                        &::unverb( \$title );
                    }else{
                        $title =~ s|\a((?:[0-9a-f][0-9a-f])*)\a|pack('h*',$1)|ges;
                    }
                    $title =~ s/\<[^\>]*\>\s*//g;
                    $item{title} = &::denc($title);
                }
                push(@{$item{desc}}, $frag );
            }
            push(@topics , { %item } ) if @{$item{desc}};
        }else{
            ### blog-mode ( 1 page to 1 rss-item) ###
            $item{desc} = [ $text ] ;
            push(@topics , { %item } );
        }
        while( my ($name,$value)=each %{$p->{attachment}} ){
            next if $name !~ /^comment\./;
            my $id=$';

            $item{url} = sprintf('%s?p=%s#c_%s_%s',$::me,$pageurl,
                                unpack('h*',$p->{title}) ,
                                unpack('h*',$id)) ;
            $item{title} = sprintf('Comment for %s', $p->{title} );
            $item{desc} = [ 
                &::verb(
                    '<dl>' . join("\n",
                        map{
                            my ($dt,$who,$text)=
                                map{ &::enc(&::deyen($_)) } split(/\t/,$_,3);
                            "<dt>$who ($dt)</dt><dd>$text</dd>";
                        } split(/\n/,&::read_object($p->{title},$name) )
                    ) . '</dl>'
                )
            ];
            push(@topics , { %item } );
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
        &printag( title         => $t->{title} ,
                  link          => $t->{url} ,
                  lastBuildDate => &stamp_format( $t->{timestamp} ),
                  pubDate       => &stamp_format( $t->{timestamp} ) ,
                  author        => $::config{nikky_author} ,
                  'dc:creator'  => $::config{nikky_author} ,
                  'dc:date'     => sprintf('%04d-%02d-%02dT%02d:%02d:%02d+00:00' ,
                                , $tm[5]+1900,$tm[4]+1,@tm[3,2,1,0] ) );
        while( $t->{title} =~ /\[([^\]]+)\]/g ){
            print "<category>$1</category>\r\n";
        }
        local $::form{p}=$t->{page};
        local $::print='';
        my $ss=$session4page{$t->{page}} || {};
        $ss->{title} = $t->{page} ;
        $ss->{attachment} ||= {};
        while( my ($key,$val)=each %{$t->{attachment}} ){
            $ss->{attachment}->{$key}  = $val ;
        }

        &::syntax_engine( join("\n\n",@{$t->{desc}}) , $ss ) ;  
        $::print =~ s/<!--- READ MORE --->.*\Z//s;
        
        print  '<description><![CDATA[';
        &::flush;
        print  "]]></description>\r\n<content:encoded><![CDATA[";
        &::flush;
        print  "]]></content:encoded>\r\n</item>\r\n";
    }
    print "</rdf:RDF>\r\n";
    exit(0);
};

## foo=>bar... を <foo>bar</foo> という形式に直して、標準出力に出す.
sub printag{
    my %tags=(@_);
    while( my ($tag,$val)=each %tags){
        printf "<%s>%s</%s>\r\n",$tag,&::enc($val),$tag;
    }
}

sub init{
    ### @nikky,%nikky の初期化 ###
    my $seq=0;
    @nikky = map{
        my $title = $_->{title};
        $_->{seq} = $seq++;
        $nikky{ $_->{title} } = $_;
    } &::ls_core( {} , '(????.??.??)*' );

    my $nextnikky;
    my $prevnikky;
    ### アクションプラグインとしての指定が検出された時
    if( $::form{date} && $::form{date} =~ /^(\d{4})(\d\d)(\d\d)?$/ ){
        if( defined $3 ){ ### date=YYYYMMDD の時
            my $ymd=sprintf('(%4s.%2s.%2s)',$1,$2,$3);
            my @region = grep(substr($_->{title},0,12) eq $ymd, @nikky);
            &set_action_plugin(
                title  => $ymd ,
                action => 'date' ,
                region => \@region ,
                prev   => \$prevnikky ,
                next   => \$nextnikky ,
            );
            $::form{a} = 'date';
        }else{ ### date=YYYYMM の時
            my $ymd=sprintf('(%4s.%2s.',$1,$2);
            my @region=grep(substr($_->{title},0,9) eq $ymd, @nikky);
            &set_action_plugin(
                title  => sprintf('(%04s.%02s)',$1,$2) ,
                action => 'date' ,
                region => \@region ,
                prev   => \$prevnikky ,
                next   => \$nextnikky ,
            );
            $::form{a} = 'date';
        }
    }elsif( exists $::form{a} && $::form{a} eq 'nikky' ){
        # 明示的に a=nikky と指定された時
        my @tm=localtime(time+24*60*60);
        my $tomorrow=sprintf('(%04d.%02d.%02d)',1900+$tm[5],1+$tm[4],$tm[3]);
        my $days = &nvl($::config{nikky_days},3); 
        my @region=grep{ $_->{title} lt $tomorrow } @nikky;
        @region=reverse(scalar(@region) > $days ? @region[-($days) .. -1] : @region);
        &set_action_plugin(
            action => 'nikky' ,
            region => \@region ,
            prev   => \$prevnikky ,
            next   => \$nextnikky ,
        );
    }elsif( exists $::form{p} && exists $nikky{ $::form{p} } ){
        my $seq=$nikky{ $::form{p} }->{seq};
        $prevnikky = $nikky[ $seq - 1 ] if $seq > 0 ;
        $nextnikky = $nikky[ $seq + 1 ] if $seq < $#nikky;
    }else{
        $prevnikky = $nikky[ $#nikky ];
    }

    ### <link>属性に前後関係を記述 ###
    if( $prevnikky ){
        $prevday_url = &::title2url($prevnikky->{title});
        push(@::html_header, sprintf('<link rel="next" href="%s">' , $prevday_url ) );
    }
    if( $nextnikky ){
        $nextday_url = &::title2url($nextnikky->{title});
        push( @::html_header , sprintf('<link ref="prev" href="%s">' ,$nextday_url ) );
    }

    my $p=$::form{p};
    if( exists $::form{date} ){
        $p = sprintf('(%04s.%02s.%02s)',unpack('A4A2A2',$::form{date}) );
    }elsif( ! defined($p) || $p !~ /^\(\d\d\d\d.\d\d.\d\d\)/ ){
        my @tm=localtime(time);
        $p = sprintf( "(%04d.%02d.%02d)\xFF", 1900+$tm[5], 1+$tm[4], $tm[3] );
    }

    ### 月初・月末の URL を作成する.
    my $month_first=substr($p,0,9).'00)';
    my $month_end  =substr($p,0,9).'99)';
    my ($p,$n);
    foreach(@nikky){
        $p   = $_ if $_->{title} lt $month_first;
        $n ||= $_ if $_->{title} gt $month_end  ;
    }
    $prevmonth_url = &::title2url($p->{title}) if $p;
    $nextmonth_url = &::title2url($n->{title}) if $n;
    $::menubar{'050_prevday'} = &inline_prevday();
    $::menubar{'950_nextday'} = &inline_nextday();
    $startday_url = &::title2url($nikky[ 0]->{title}) if @nikky;
    $endday_url   = &::title2url($nikky[-1]->{title}) if @nikky;
}

sub date_anchor{
    my ($xxxxday,$date_url,$default_mark,$symbol)=@_;
    $symbol ||= &::enc($::config{"nikky_symbol${xxxxday}link"}||$default_mark);
    !$symbol ? ''
    : $date_url
    ? qq(<a href="${date_url}">${symbol}</a>)
    : qq(<span class="no${xxxxday}">$symbol</span>) ;
}

sub inline_prevday  { &date_anchor('prevday'  ,$prevday_url ,'<' , $_[1]); }
sub inline_nextday  { &date_anchor('nextday'  ,$nextday_url ,'>' , $_[1]); }

$::inline_plugin{prevmonth} = sub {
    &date_anchor('prevmonth',$prevmonth_url ,'<<', $_[1]); 
};
$::inline_plugin{nextmonth} = sub {
    &date_anchor('nextmonth',$nextmonth_url ,'>>', $_[1]);
};
sub inline_startday { &date_anchor('startday' ,$startday_url  ,'|' , $_[1]); }
sub inline_endday   { &date_anchor('endday'   ,$endday_url    ,'|' , $_[1]); }

### 新規にっき作成 ###
$::action_plugin{today} = sub {
    my @tm = localtime;
    &::print_header( divclass=>'max' );
    my $default_title=sprintf('(%04d.%02d.%02d)' ,
         $tm[5]+1900,$tm[4]+1,$tm[3] );

    &::putenc('<form action="%s" method="post"
        ><h1>Create Page</h1><p
        ><input type="hidden" name="a" value="edt"
        ><input type="text" name="p" value="%s" size="40"
        ><input type="submit"></p></form>'
        , $::me , $default_title );
    &::print_footer;
};

### カレンダー関連 ###
sub query_wday { 
    my ($y,$m) = @_;
    my ($zy,$zm)=( $m<=2 ? ($y-1,12+$m) : ($y,$m) );

    ( $zy + int($zy/4) - int($zy/100) + int($zy/400) + int((13*$zm+ 8)/5)+1)%7;
}

sub query_days_in_month{
    my ($y,$m) = @_;
    my @mdays = (0,31, $y%($y%100?4:400)?28:29 
        , 31,30,31,30   ,   31,31,30,31,30,31);

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
                        , $::me , $y , $m , $d , $d);
    }else{
        $$buffer .= $d;
    }
    $$buffer .= "</$tag> ";
}

sub query_current_month{
    my @r;
    if( defined($::form{p}) &&
        $::form{p} =~ /^\((\d\d\d\d)\.(\d\d)\.(\d\d)\)/ ){
        @r=($1,$2,$3);
    }elsif( defined($::form{date}) &&
        $::form{date} =~ /^(\d\d\d\d)(\d\d)(\d\d)?$/ ){
        @r=($1,$2,$3||'00');
    }else{
        my ($y,$m,$today)=(localtime)[5,4,3];
        @r=($y + 1900 , $m+1 , $today );
    }
    $r[2] =~ s/^0//;
    @r;
}

$::inline_plugin{calender} = sub {
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
    } &::ls_core( {} , sprintf('(%04d.%02d.??)*',$y,$m));

    my $title=&year_and_month($y,$m);

    if( defined($mode) && $mode eq 'f' ) {
        my $buffer = sprintf(
            '<div class="calender_flat"><span class="calender_header">%s%s %s/</span>'
            , &inline_startday()
            , $::inline_plugin{prevmonth}->($session)
            , $title
        );
        foreach my $d (1..$max_mdays){
            &put_1day('span',$y,$m,$d,$wday,$today,\%thismonth,\$buffer);
            $wday = ($wday + 1) % 7;
        }
        $buffer . sprintf( '<span class="calender_footer">%s%s</span></div>'
            , $::inline_plugin{nextmonth}->($session)
            , &inline_endday()
        );
    }else{
        my $buffer = sprintf(
            '<table class="calender"><caption>%s%s %s %s%s</caption><tr nowrap>%s'
            , &inline_startday()
            , $::inline_plugin{prevmonth}->($session)
            , $title
            , $::inline_plugin{nextmonth}->($session)
            , &inline_endday()
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
};

sub stamp_format{
    sprintf("%s, %02d %s %04d %s GMT",
        (split(/\s+/,gmtime( $_[0] )))[0,2,1,4,3]);
}

$::inline_plugin{archives} = sub {
    my (undef,$backMonths)=@_;

    my $startym='1900.00';
    if ( defined($backMonths) ) {
        if( $backMonths !~ m/^\d+$/ ){
            return '<blink>archives: 1st parameter must be digits.</blink>';
        }
        my @localtime = localtime;
        my $currentMonths = ($localtime[5]+1900)*12+$localtime[4];
        my $specifiedMonths = $currentMonths - $backMonths;
        $startym = sprintf("%04d.%02d",int($specifiedMonths/12),$specifiedMonths%12+1);
    }

    my %diary;
    for my $fn ( &::list_page() ){
        $diary{ $1 }++ if &::fname2title($fn) =~ /^\((\d+\.\d\d)\.\d\d\)/;
    }

    my $html = '<ul class="sowp-nikkytools-archives">';
    for my $ym ( reverse sort keys %diary ){
        my ($year,$month) = split(/\./,$ym);

        next if $ym < $startym;

        $html .= sprintf( '<li class="sowp-nikkytools-archives-month"><a href="%s?date=%04d%02d">%s [%d]</a></li>', $::me, $year, $month, &year_and_month($year,$month),$diary{$ym});
    }
    $html . '</ul>';
};

$::inline_plugin{packedarchives} = sub {
    my %diary;
    for my $fn ( &::list_page() ){
        if( &::fname2title($fn) =~ /^\((\d+)\.(\d\d)\.\d\d\)/ ){
            ($diary{ $1 }||={})->{$2}++;
        }
    }
    my $html = '<ul class="sowp-nikkytools-archives">';
    for my $y ( sort keys %diary ){
        $html .= '<li class="sowp-nikkytools-archives-month">'.$y;
        for my $m ( sort keys %{$diary{$y}} ){
            $html .= sprintf('|<a href="%s?date=%04d%02d" title="%d article(s)">%02d</a>' , $::me , $y , $m , $diary{$y}->{$m} , $m );
        }
        $html .= '</li>';
    }
    $html . '</ul>';
};

sub year_and_month{
    # 設定に応じて、月・日を文字列化する。
    my ($y,$m)=@_;
    if( $::config{nikky_calendertype} ){
        sprintf('%s %d' , ( qw/January February March April May June July 
                            August September October November December/ )[$m-1],$y);
    }else{
        sprintf('%04d.%02d',$y,$m);
    }
}

sub nvl{
    # 第一引数が数値なら第一引数、さもなければ第二引数を返す.
    my ($n,$default)=@_;
    if( defined($n) && $n =~ /^\d+$/ ){
        $n;
    }else{
        $default;
    }
}

sub set_action_plugin{
    # a=date や a=nikky 等のアクションプラグイン登録を行う
    # in
    #   action => プラグイン名
    #   region => 表示範囲の配列への参照
    #   title  => <title> に書くタイトル
    # out
    #   prev   =>「<<」につながるページ構造体の代入先
    #   next   =>「>>」につながるページ構造体の代入先

    my %o=@_;
    my $region_max=-1;
    my $region_min=$#nikky+1;
    for( @{$o{region}} ){
        $region_max = $_->{seq} if $_->{seq} > $region_max;
        $region_min = $_->{seq} if $_->{seq} < $region_min;
    }
    ${$o{next}} = $nikky[ $region_max + 1 ] if $region_max < $#nikky ;
    ${$o{prev}} = $nikky[ $region_min - 1 ] if $region_min > 0;
    if( exists $o{action} ){
        $::action_plugin{$o{action}} = sub {
            &::print_template(
                template => $wifky::nikky::template ,
                Title => $o{title} || '',
                main => sub{
                    &concat_article( @{$o{region}} );
                }
            );
        }; 
    }
}
1;
