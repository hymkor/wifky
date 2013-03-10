package wifky::makerss;

my $trigger=$::config{makerss__trigger} || 'rssfeed';
my $rssurl = $::me.'?a='.&::percent($trigger);
my $proxy = ($::config{'makerss__proxy'} || $rssurl);

push( @::html_header ,
    qq(<link rel="alternate" type="application/rss+xml"
        title="RSS" href="$proxy">) );

$::preferences{'makerss.pl'} = [
    {
        desc => 'Description' ,
        name => 'makerss__description' ,
        type => 'textarea'
    },
    {
        desc => 'Articles number outputed to feed at once' ,
        name => 'makerss__feednum' ,
        type => 'text' ,
    },
    {
        desc => 'Author' ,
        name => 'makerss__author' ,
        type => 'text' ,
    },
    {
        desc => 'unfeed pages (split by LF)' ,
        name => 'makerss__unfeed' ,
        type => 'textarea' ,
    },
    {
        desc => 'URL compatiblity(default="rssfeed)"' ,
        name => 'makerss__trigger' ,
    },
    {
        desc => 'RSS Feed ProxyURL' ,
        name => 'makerss__proxy' ,
        type => 'text' ,
    },
];

$::action_plugin{$trigger} = sub {
    $::me = 'http://' . (
                    defined $ENV{'HTTP_HOST'}
                  ? $ENV{'HTTP_HOST'}
                  : defined $ENV{'SERVER_PORT'} && $ENV{'SERVER_PORT'} != 80
                  ? $ENV{'SERVER_NAME'} . ':' . $ENV{'SERVER_PORT'}
                  : $ENV{'SERVER_NAME'}
            ) . $ENV{'SCRIPT_NAME'};
    $::inline_plugin{comment} = sub { &::plugin_comment(@_,'-f'); };

    my @unfeed = split(/\s+/,$::config{makerss__unfeed});
    my $feed_num = ($::config{makerss__feednum} || 3);

    my $last_modified=0;
    my @pagelist;
    foreach my $p ( &::ls_core( { r=>1 , t=>1 } ) ){
        next if grep( $p->{title} eq $_ , @unfeed);
        next unless -f $p->{fname};
        last if $feed_num-- <= 0;

        my $tm=(stat($p->{fname}))[9];
        $last_modified = $tm if $last_modified < $tm ;
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
        push(@pagelist,$p);
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
    printf qq{<channel rdf:about="%s">\r\n},$rssurl;
    &printag( title       => $::config{sitename} ,
              link        => $::me ,
              description => $::config{makerss__description} );
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
            desc  => [ $text ] ,
            attachment => $p->{attachment} ,
        );

        push(@topics , { %item } );

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
                  author        => $::config{makerss__author} ,
                  'dc:creator'  => $::config{makerss__author} ,
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
sub stamp_format{
    sprintf("%s, %02d %s %04d %s GMT",
        (split(/\s+/,gmtime( $_[0] )))[0,2,1,4,3]);
}

$::inline_plugin{read_more} = $::inline_plugin{'read-more'} = sub {
    if( $::form{a} && ($::form{a} eq 'rss' || $::form{a} eq $trigger) ){
        &::anchor('(more...)',{ p=>$::form{p} } ) . '<!--- READ MORE --->';
    }else{
        '';
    }
};
