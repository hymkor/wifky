# 0.9_0 # amazon.pl
package wifky::amazon;

use strict; use warnings;
my $version='0.9_0';

my $default_amazon_proxy = 'wifky.sourceforge.jp/cgi-bin/amazon_proxy.cgi';

$::preferences{"Amazon.pl $version"} = [
    {
      desc => 'Your Amazon associate-ID' ,
      name => 'amazon_associate_id' ,
      size => 20 
    },
    {
      desc => "ProxyServer (default:$default_amazon_proxy)" ,
      name => 'amazon_proxy' ,
      size => 20 
    },
    {
      desc => "default align(empty/left/center/right)",
      name => 'amazon_default_align' ,
    }
];

$::inline_plugin{'amazon'} = sub {
    my ($session,$itemid,@args) = @_;
    my $title;
    my %option=( left=>0  , right=>0 , center=>0 , inline=>0 ,
                 clear=>0 , image=>0 , small=>0 ,
                 large=>0 , middle=>0 , text=>0 );
    foreach my $e (@args){
        if( exists $option{$e} ){ $option{$e}++ ; }
        else { $title = $e; }
    }

    my %tags;
    my $bookinfo=&::read_object($session->{title},"bookinfo.$itemid");
    if( $bookinfo ){
        %tags = map{ split(/=/,$_,2) } split(/\n/,$bookinfo);
    }else{
        my $id=$::config{amazon_associate_id}; 
        my $associate_tag=( $id ? "&AssociateTag=$id" : '' );

        my $amazon_proxy = ($::config{amazon_proxy} || $default_amazon_proxy);
        $amazon_proxy =~ s|^http://||;
        my @amazon_proxy = split(/\//,$amazon_proxy,2);

        my $tsv = &http(
            $amazon_proxy[0] ,
            '/'.$amazon_proxy[1]."?item=${itemid}&id=${id}&enc=$::charset"
        );
        foreach my $line (split(/\n/,$tsv)){
            my @col=split(/\t/,$line);
            if( defined (my $key=shift(@col))){
                $tags{$key} = join("\t",@col);
            }
        }
        if( $tags{Status} eq 'Success' ){
            &::write_object( $session->{title} ,
                                 "bookinfo.$itemid" ,
                                 join("\n",map{
                                         $_ && exists $tags{$_} 
                                         ?  sprintf("%s=%s",$_,$tags{$_})
                                         : () }
                                    qw{
                                        Title
                                        SmallImage
                                        MediumImage
                                        LargeImage
                                        DetailPageURL
                                    }
                                 ));
        }
    }

    if( %tags ){
        $title ||= &::enc( $tags{Title} );
        my $buf = sprintf('<a href="%s"%s>',$tags{DetailPageURL},$::target );

        my $img = $option{large} ? $tags{LargeImage}
                : $option{small} ? $tags{SmallImage}
                : $tags{MediumImage} ;
        if( $img && !$option{text} ){
            $buf .= sprintf(
                    '<img %s alt="%s" title="%s" border=0 class="amazon"' .
                    ' src="%s" width="%s" height="%s">'
                , ( $option{left}   ? 'align="left"'   :
                    $option{center} ? 'align="center"' :
                    $option{right}  ? 'align="right"'  :
                    $option{inline}   ? '' :
                    $::config{amazon_default_align} ?
                        'align="'.&::enc($::config{amazon_default_align}).'"' : '' )
                , $title , $title
                , split(/\t/,$img) 
            );
        }
        $option{image} or $buf .= $title;
        $buf . '</a>';
    }else{
        'Book information cannot read from amazon.co.jp.';
    }
};

# If $since has TIME and the page not modified, &http returns undef;
sub http{
    my ($host,$path,$since)=@_;

    use IO::Socket;

    my $http=IO::Socket::INET->new("$host:80") or die("socket error.\n");

    $http->print("GET $path HTTP/1.0\r\n");
    if( defined($since) ){
        my @tm=split(/\s+/,''.gmtime($since));
        $http->printf("If-Modified-Since: %s, %02d %s %d %s GMT\n" ,
            $tm[0],$tm[2],$tm[1],$tm[4],$tm[3]);
    }
    $http->print("Host: $host\r\n");
    $http->print("Connection: close\r\n");
    $http->print("\r\n");

    my $flag=0;
    my $body='';
    if( ( split(/\s+/,<$http>) )[1] eq '304' ){
        undef $body;
    }else{
        while( defined(my $line=<$http>) ){
            if( $line =~ /^\r?\n?$/ ){
                while( defined(my $line=<$http>) ){
                    $body .= $line;
                }
                last;
            }
        }
    }
    $http->close();
    $body;
}

1;
