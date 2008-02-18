package wifky::rssreader;
my $version='0.3';

use strict;
use warnings;
use IO::Socket;
use Encode;
use Storable ();

$::preferences{"RSS Reader $version"} = [
    { desc => 'allowed rss-list', name=>'rssreader__rssurl' ,
      cols =>60 , type=>"textarea"},
    { desc => 'default max article(empty:8 articles)' ,
      name=>'rssreader__maxnum' , size=>2 },
    { desc => 'update cycle/minutes(empty:15 minutes)' ,
      name=>'rssreader__cycle' , size=>2 },
    { desc => 'debug mode' , type=>'checkbox' ,
      name=>'rssreader__debug' },
];

$::inline_plugin{'rssreader'} = sub {
    my $session = shift;
    my %opt;
    while( $#_ >= 0 && $_[0] =~ /^-/ ){
        $opt{ $' } = 1;
        shift(@_);
    }
    my ($rssurl,$maxnum)=@_;

    ### URL normalize ###
    my $rsslist = $::config{'rssreader__rssurl'}
        or return '(not defined rss-list)';
    my @rsslist = split(/\s+/,$rsslist);
    if( defined($rssurl) ){
        if( grep( $_ eq $rssurl , @rsslist ) <= 0 ){
            return "<blink>not allowed url: $rssurl</blink>";
        }
    }else{
        $rssurl = $rsslist[0];
    }
    $rssurl =~ s|^http://||;
    my ($host,$uri) = split(m|(?=/)|,$rssurl,2);
    $uri ||= '/';

    ### Entry number normalize ###
    my $default_number=&nvl($::config{rssreader__maxnum},8);
    if( &nvl($maxnum,9999) > $default_number ){
        $maxnum = $default_number;
    }

    my @entries = &rss( &::title2fname( $session->{title} , $rssurl . '.nst' ) ,
                          $host , $uri , $maxnum );

    my $tag= $opt{o} ? 'ol' : $opt{u} ? 'ul' : 'dl';
    qq(<$tag class="rssreader">\n) . join('',
            map{
                my $cont=$_->[1];
                if( $_->[0] ){ ### has a url ###
                    $cont = sprintf('<a href="%s">%s</a>',$_->[0],$cont);
                }
                if( $opt{o} || $opt{u} ){
                    '<li>'.$cont.'</li>';
                }else{
                    sprintf(qq(<dt>%s</dt><dd>%s</dd>\n) ,
                        $cont ,
                        &set_class_category($_->[2]) );
                }
            } @entries
    ) . "</$tag>";
};

sub set_class_category{
    my ($desc)=@_;
    $desc =~ s|^(\[.*?\])+|<span class="rssreader_subject">$&</span>|;
    $desc;
}

sub rss{
    my ($fname , $host , $uri , $max_entries ) = @_;

    ### Check cached entries ###
    my $lastmodified;
    my @oldentries;
    my $ncache;
    if( -f $fname ){
        $ncache=Storable::retrieve($fname);
        $lastmodified = $ncache->{lastmodified};
        @oldentries = @{$ncache->{entries}};
    }

    ### Update entries with http:// ###
    ###   (1) timestamp of $fname ... last query time with http
    ###   (2) value of field: 'last-modified' ... last rss update time.
    ### These order is (2) <= (1) <= now.

    my $xml;
    if( (!defined $ncache) || ( -M $fname ) >= &nvl($::config{rssreader__cycle},15)/1440.0 ){
        utime( time , time , $fname );
        eval{
            local $SIG{ALRM} = sub { die('Timeout to read RSS'); };
            alarm(30);
                $xml = &http( $host , $uri , $lastmodified );
            alarm(0);
        };
        if( $@ ){
            alarm(0);
            if( $@ =~ /Timeout to read RSS/ ||
                $@ =~ /not found/ ){
                undef $xml;
            }else{
                die($@);
            }
        }
    }

    my @newentries;
    if( defined($xml) ){
        my $encode='utf8';
        if( $xml =~ /^Content-Type:.*charset=([\-\_\w]+)/ ||
            $xml =~ /<?xml[^>]+encoding="?([\-\_\w]+)"?/ )
        {
            my $charset=$1;
            if( $charset =~ /euc[\-\_]?jp/i ){
                $encode = 0;
            }elsif( $charset =~ /utf[\-\_]?8/i ){
                $encode = 'utf8';
            }
        }
        if( $encode ){
            Encode::from_to($xml,'utf8','euc-jp',Encode::XMLCREF);
        }
        &parse_rss($xml,
            sub{
                my ($url,$title,$desc)=@_;
                if( defined($oldentries[0])      &&
                    defined($oldentries[0]->[1]) &&
                    $oldentries[0]->[1] eq $title )
                {
                    0;
                }else{
                    push(@newentries,[ $url , $title , $desc ]);
                    &errlog("Read:%s",$title);
                    (scalar(@newentries) < $max_entries ) ? 1 : 0;
                }
            }
        );
    }
    my @entries=(@newentries,@oldentries);
    splice(@entries, $max_entries ) if $max_entries < scalar(@entries) ;

    if( defined($xml) ){
        my @tm=split(/\s+/,scalar(gmtime(time()-30)));
        Storable::nstore( {
            lastmodified => 
                sprintf('%s, %02d %s %d %s GMT',$tm[0],$tm[2],$tm[1],$tm[4],$tm[3]),
            entries => \@entries ,
        } , $fname );
    }
    @entries;
}

# If $since has TIME and the page not modified, &http returns undef;
sub http{
    my ($host,$path,$since)=@_;

    my $http = IO::Socket::INET->new(PeerAddr=>$host,PeerPort=>80,Proto=>'tcp')
        or die("socket error.\n");
    &errlog('call %s/%s',$host,$path);
    $http->print("GET $path HTTP/1.1\r\n");
    if( defined($since) ){
        $http->print("If-Modified-Since: $since\r\n");
        &errlog('If-Modified-Since: %s',$since);
    }
    $http->print("Host: ${host}:80\r\n");
    $http->print("User-Agent: wifky rss-reader plugin.\r\n");
    $http->print("Connection: close\r\n");
    $http->print("\r\n");
    $http->flush();

    my $flag=0;
    my $body='';
    my $line=<$http>;
    &errlog("header> %s",$line);
    if( ( split(/\s+/,$line) )[1] eq '304' ){
        $body = undef;
    }else{
        while( defined(my $line=<$http>) ){
            &errlog("body> %s",$line);
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

sub parse_xml{
    my ($xml,$start,$end,$text)=@_;
    $xml =~ s/\<\!\[CDATA\[(.*?)\]\]\>/"\a".unpack('h*',$1)."\a"/ges;
    while( length($xml) > 0 ){
        if( $xml =~ m|\A\</([^\<\>]+)\>|s ){ ### </tag>
            $xml = $';
            $end->(split(/\s+/,$1)) or return;
        }elsif( $xml =~ m|\A\<([^\<\>]+)\>|s ){ ### <tag>
            $xml = $';
            $start->( split(/\s+/,$1) ) or return;
        }elsif( $xml =~ m|\A[^\<\>]+|s ){
            $xml = $';
            my $body = $&; $body =~ s/\a(.*?)\a/pack('h*',$1)/ges;
            $text->( $body ) or return;
        }else{
            return;
        }
    }
}

sub parse_rss{
    my ($xml,$get_entry)=@_;
    my $item=undef;
    my $text=undef;
    &parse_xml( $xml ,
        sub { ### Start ###
            my $tag=shift;
            my @elements = @_;
            if( $tag eq 'item' ){
                my %hash;
                grep( (/^([^\=]+)\=\"?(.*?)\"?$/ and $hash{$1}=$2,0),@elements);
                $item = { url=>$hash{'rdf:about'} , 'dc:subject'=>[] };
            }elsif( defined($item) && $tag =~ /title|description|dc\:subject/){
                $text = '';
            }
            1;
        } ,
        sub { ### End ###
            my ($tag)=@_;
            if( defined($text) ){
                if( $tag =~ /^(title|description)/ ){
                    $item->{ $tag } = $text;
                }elsif( $tag eq 'dc:subject' ){
                    push(@{$item->{'dc:subject'}},$text);
                }elsif( $tag eq 'item' ){
                    my $rv=$get_entry->( $item->{url},
                            $item->{title},
                            join('',
                                map("[${_}]", grep( $_  , @{$item->{'dc:subject'}}))
                            ) .  $item->{description}
                        ) or return 0;
                    undef $item;
                }
            }
            1;
        } ,
        sub { ### Text ###
            defined($text) and $text .= $_[0];
            1;
        }
    );
}

sub nvl{
    my $value=shift;
    if( defined($value) && $value =~ /^\d+$/ ){
        $value;
    }else{
        shift;
    }
}

sub errlog{
    return unless $::config{rssreader__debug};

    local *ERRLOG;
    my $fmt=shift;

    open(ERRLOG,'>>'.&::title2fname('messages')) or die;
        my @tm=localtime();
        my $message=sprintf($fmt,@_);
        chomp($message);

        printf ERRLOG "|| %04d/%02d/%02d_%02d:%02d:%02d |```%s```\n",
            1900+$tm[5] , 1+$tm[4] , @tm[3,2,1,0] , $message ;
    close(ERRLOG);
}

1;
