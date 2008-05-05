package wifky::nikky;

use strict; use warnings;

$wifky::nikky::template ||= '
    <div class="main">
        <div class="header">
            &{header}
        </div><!-- header -->
        <div class="autopagerize_page_element">
            &{main} <!-- contents and footers -->
        </div>
        <div class="autopagerize_insert_before"></div>
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
my $version='0.24_1';
my ($nextday , $prevday , $nextmonth , $prevmonth , $startday , $endday );
my $ss_terminater=(%::ss ? $::ss{terminator} : 'terminator');
my $ss_copyright =(%::ss ? $::ss{copyright}  : 'copyright footer');

push( @::body_header , qq{<form name="newdiary" action="$::me" method="post" style="display:none"><input type="hidden" name="p" /><input type="hidden" name="a" value="edt" /></form>} );

my @now=localtime();
$::menubar{'200_New'} = sprintf( q|<a href="%s?a=new" onClick="JavaScript:if(document.newdiary.p.value=prompt('Create a new diary','(%04d.%02d.%02d)')){document.newdiary.submit()};return false;">New</a>|,$::me,$now[5]+1900,$now[4]+1,$now[3] ) if exists $::menubar{'200_New'};

$::inline_plugin{'nikky.pl_version'} = sub{ "nikky.pl $version" };
$::inline_plugin{lastdiary}=\&lastdiary;
$::inline_plugin{olddiary}=\&olddiary;
$::inline_plugin{newdiary}=\&newdiary;
$::inline_plugin{recentdiary}=\&recentdiary;
$::inline_plugin{referer}=\&referer;
$::inline_plugin{calender}= \&calender;
$::inline_plugin{prevday}=\&prevday;
$::inline_plugin{nextday}=\&nextday;
$::inline_plugin{prevmonth}=\&prevmonth;
$::inline_plugin{nextmonth}=\&nextmonth;
$::inline_plugin{startday}=\&startday;
$::inline_plugin{endday}=\&endday;
$::inline_plugin{a_nikky} = sub {
    qq(<a href="$::me?a=nikky">) .  join(' ',@_[1..$#_]) . '</a>';
};
$::inline_plugin{nikky_comment} = sub {
    $::form{p} =~ /^\(\d\d\d\d\.\d\d.\d\d\)/ ? &::plugin_comment(@_) : '';
};
$::inline_plugin{nikky_referer} = sub {
    $::form{p} =~ /^\(\d\d\d\d\.\d\d.\d\d\)/ ? &wifky::nikky::referer(@_) : '';
};

$::action_plugin{rss} = \&action_rss ;
$::action_plugin{new} = \&action_newdiary;

exists $::form{date} and $::form{a}='date';

if( &::is('nikky_front') &&
    !exists $::form{a} && !exists $::form{p} )
{
    $::form{a} = 'nikky';
}

if( exists $::form{a} && ($::form{a} eq 'date' || $::form{a} eq 'nikky') ){
    delete $::menubar{'300_Edit'};
    delete $::menubar{'400_Edit(Admin)'};
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

    { desc=>'Displayed RSS Feed URL' ,
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
    my $h = ( $::version ge '1.1' || &::is('cssstyle') ? 2 : 1 );
    foreach my $p (@_){
        next unless -f $p->{fname};
        my $pagename=$p->{title};
        &::puts('<div class="day">');
        &::putenc('<h%d><span class="title"><a href="%s">%s</a></span></h%d><div class="body">',
                    $h , &::title2url( $pagename ) , $pagename , $h );
        local $::form{p} = $pagename;
        &::print_page( title=>$pagename );
        &::puts('</div></div>');
        &::print_page( title=>'Footer' , class=>$ss_terminater );
    }
}

sub lastdiary{
    local $::inline_plugin{lastdiary}=sub{};
    local $::print='';
    my $days = $#_ >= 1 ? $_[1] : 3;
    my @list=&::ls_core( {} , '(????.??.??)*' );
    my @tm=localtime(time+24*60*60);
    my $tomorrow=sprintf('(%04d.%02d.%02d)',1900+$tm[5],1+$tm[4],$tm[3]);
    &concat_article( &lastN($days,grep( $_->{title} lt $tomorrow && -f $_->{fname} , @list )));

    $::print;
}

sub olddiary{
    local $::inline_plugin{olddiary}=sub{};
    local $::print='';
    &concat_article( &firstN($#_ >0 ? $_[1] : 3 ,@nikky) );
    $::print;
}

sub newdiary{
    local $::inline_plugin{newdiary}=sub{};
    local $::print='';
    &concat_article( &lastN($#_ >= 1 ? $_[1] : 3,@nikky));
    $::print;
}

sub recentdiary{
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
}

sub referer{
    my $session=shift;
    my @exclude=@_;
    my @title=($::form{p} || 'FrontPage' , 'referer.txt' );
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

sub action_rss{
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
    foreach my $p (@pagelist){
        my $text = &::enc( &::read_object($p->{title}) );
        $text =~ s!^\s*\&lt;pre&gt;(.*?\n)\s*\&lt;/pre&gt;|^\s*8\&lt;(.*?\n)\s*\&gt;8|`(.)`(.*?)`\3`!
                      defined($4)
                    ? &::verb('<tt class="pre">'.&::cr2br($4).'</tt>')
                    : "\n\n<pre>".&::verb($1||$2)."</pre>\n\n"
                !gesm;

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
                    my $title = &::preprocess($1,{ attachment=>{} } );
                    $title =~ s|\a((?:[0-9a-f][0-9a-f])*)\a|pack('h*',$1)|ges;
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
                '<dl>' . join("\n",
                    map{
                        my ($dt,$who,$text)=
                            map{ &::enc(&::deyen($_)) } split(/\t/,$_,3);
                        "<dt>$who ($dt)</dt><dd>$text</dd>";
                    } split(/\n/,&::read_object($p->{title},$name) )
                ) . '</dl>'
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
        &::syntax_engine(
            join("\n\n",@{$t->{desc}}) ,
            { title => $t->{page} , attachment => $t->{attachment} }
        );
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

sub printag{
    my %tags=(@_);
    while( my ($tag,$val)=each %tags){
        printf "<%s>%s</%s>\r\n",$tag,&::enc($val),$tag;
    }
}

sub init{
    my $seq=0;
    @nikky = map{
        my $title = $_->{title};
        $_->{seq} = $seq++;
        $nikky{ $_->{title} } = $_;
    } &::ls_core( {} , '(????.??.??)*' );

    my $nextnikky;
    my $prevnikky;
    if( exists $::form{date} && $::form{date} =~ /^(\d{4})(\d\d)(\d\d)?$/ ){
        if( defined $3 ){ ### YYYYMMDD
            my $ymd=sprintf('(%4s.%2s.%2s)',$1,$2,$3);
            my @region = grep(substr($_->{title},0,12) eq $ymd, @nikky);
            set_view_thosenikky(
                title  => $ymd ,
                action => 'date' ,
                region => \@region ,
                prev   => \$prevnikky ,
                next   => \$nextnikky ,
            );
            $::form{a} = 'date';
        }else{ ### YYYYMM
            my $ymd=sprintf('(%4s.%2s.',$1,$2);
            my @region=grep(substr($_->{title},0,9) eq $ymd, @nikky);
            &set_view_thosenikky(
                title  => sprintf('(%04s.%02s)',$1,$2) ,
                action => 'date' ,
                region => \@region ,
                prev   => \$prevnikky ,
                next   => \$nextnikky ,
            );
            $::form{a} = 'date';
        }
    }elsif( exists $::form{a} && $::form{a} eq 'nikky' ){
        my @tm=localtime(time+24*60*60);
        my $tomorrow=sprintf('(%04d.%02d.%02d)',1900+$tm[5],1+$tm[4],$tm[3]);
        my $days = &nvl($::config{nikky_days},3); 
        my @region=&lastN($days,grep($_->{title} lt $tomorrow , @nikky));
        &set_view_thosenikky(
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
    if( $prevnikky ){
        $prevday = &::title2url($prevnikky->{title});
        push(@::html_header, sprintf('<link rel="next" href="%s">' , $prevday ) );
    }
    if( $nextnikky ){
        $nextday = &::title2url($nextnikky->{title});
        push( @::html_header , sprintf('<link ref="prev" href="%s">' ,$nextday ) );
    }

    my $p=$::form{p};
    if( exists $::form{date} ){
        $p = sprintf('(%04s.%02s.%02s)',unpack('A4A2A2',$::form{date}) );
    }elsif( ! defined($p) || $p !~ /^\(\d\d\d\d.\d\d.\d\d\)/ ){
        my @tm=localtime(time);
        $p = sprintf( "(%04d.%02d.%02d)\xFF", 1900+$tm[5], 1+$tm[4], $tm[3] );
    }
    my $month_first=substr($p,0,9).'00)';
    my $month_end  =substr($p,0,9).'99)';
    foreach(@nikky){
        $prevmonth   = $_ if $_->{title} lt $month_first;
        $nextmonth ||= $_ if $_->{title} gt $month_end  ;
    }
    $prevmonth = &::title2url($prevmonth->{title}) if $prevmonth;
    $nextmonth = &::title2url($nextmonth->{title}) if $nextmonth;
    if( defined(%::menubar) ){
        $::menubar{'050_prevday'} = &prevday();
    }else{
        unshift(@::menubar,&prevday);
    }
    if( defined(%::menubar) ){
        $::menubar{'950_nextday'} = &nextday();
    }else{
        push(@::menubar,&nextday);
    }
    $startday = &::title2url($nikky[ 0]->{title}) if @nikky;
    $endday   = &::title2url($nikky[-1]->{title}) if @nikky;
}

sub date_anchor{
    my ($xxxxday,$date_url,$default_mark,$symbol)=@_;
    $symbol ||= &::enc($::config{"nikky_symbol${xxxxday}link"}||$default_mark);
    !$symbol ? ''
    : $date_url
    ? qq(<a href="${date_url}">${symbol}</a>)
    : qq(<span class="no${xxxxday}">$symbol</span>) ;
}

sub prevday  { &date_anchor('prevday'  ,$prevday ,'<' , $_[1]); }
sub nextday  { &date_anchor('nextday'  ,$nextday ,'>' , $_[1]); }
sub prevmonth{ &date_anchor('prevmonth',$prevmonth ,'<<', $_[1]); }
sub nextmonth{ &date_anchor('nextmonth',$nextmonth ,'>>', $_[1]); }
sub startday { &date_anchor('startday' ,$startday  ,'|' , $_[1]); }
sub endday   { &date_anchor('endday'   ,$endday    ,'|' , $_[1]); }

sub action_newdiary{
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
}

sub query_wday { ### query week day.
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
    } &::ls_core( {} , sprintf('(%04d.%02d.??)*',$y,$m));

    my $title=&year_and_month($y,$m);

    if( defined($mode) && $mode eq 'f' ) {
        my $buffer = sprintf(
            '<div class="calender_flat"><span class="calender_header">%s%s %s/</span>'
            , &startday()
            , $::inline_plugin{prevmonth}->($session)
            , $title
        );
        foreach my $d (1..$max_mdays){
            &put_1day('span',$y,$m,$d,$wday,$today,\%thismonth,\$buffer);
            $wday = ($wday + 1) % 7;
        }
        $buffer . sprintf( '<span class="calender_footer">%s%s</span></div>'
            , $::inline_plugin{nextmonth}->($session)
            , &endday()
        );
    }else{
        my $buffer = sprintf(
            '<table class="calender"><caption>%s%s %s %s%s</caption><tr nowrap>%s'
            , &startday()
            , $::inline_plugin{prevmonth}->($session)
            , $title
            , $::inline_plugin{nextmonth}->($session)
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

$::inline_plugin{'archives'} = sub {
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

$::inline_plugin{'packedarchives'} = sub {
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
    my ($y,$m)=@_;
    if( &::is('nikky_calendertype') ){
        sprintf('%s %d' , ( qw/January February March April May June July 
                            August September October November December/ )[$m-1],$y);
    }else{
        sprintf('%04d.%02d',$y,$m);
    }
}

sub nvl{
    my ($n,$default)=@_;
    if( defined($n) && $n =~ /^\d+$/ ){
        $n;
    }else{
        $default;
    }
}

sub firstN{
    my $n=shift; grep( $n-- > 0 , @_ );
}

sub lastN{
    my @result;
    my $n=shift;
    push(@result,pop(@_)) while( $n-- > 0 && @_ );
    @result;
}

sub set_view_thosenikky{
    my %o=@_;

    my ($prevnikky,$nextnikky);
    my $max=-1;
    my $min=$#nikky+1;
    for( @{$o{region}} ){
        $max = $_->{seq} if $_->{seq} > $max;
        $min = $_->{seq} if $_->{seq} < $min;
    }
    ${$o{next}} = $nikky[ $max + 1 ] if $max < $#nikky ;
    ${$o{prev}} = $nikky[ $min - 1 ] if $min > 0;
    $::action_plugin{$o{action}} = sub {
        if( defined &::print_template ){
            &::print_template(
                template => $wifky::nikky::template ,
                Title => $o{title} || '',
                main => sub{
                    &concat_article( @{$o{region}} );
                }
            );
        }else{
            if( $o{title} ){
                &::print_header( userheader=>'YES' , title=> $o{title}  );
            }else{
                &::print_header( userheader=>'YES' );
            }
            &concat_article( @{$o{region}} );
            &::puts(qq(<div class="$ss_copyright">),@::copyright,'</div>');
            &::print_sidebar_and_footer;
        }
    } if exists $o{action};
}
1;
