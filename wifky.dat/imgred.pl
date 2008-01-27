package wifky::imgred;

# use strict; use warnings;

$::inline_plugin{imgred} = sub{
    my ($session,$url)=@_;
    $url = &::denc($url);
    if( $url !~ /\.jpg$/i &&
        $url !~ /\.png$/i &&
        $url !~ /\.gif$/i &&
        $url !~ m|^http://([-\\w.!~*\'();/?:@&=+$,%#]+)| )
    {
        return "<div>Invalid URL: $url</div>";
    }
    $url =~ s|^http://||;
    if( exists $::form{a} &&
        $::form{a} eq 'Preview' &&
        !( $session->{attachment}->{$url} ) )
    {
        eval{ &::ninsho; };
        if( $@ ){
            return "<div>Please write password to sign area to download image.</div>";
        }

        use IO::Socket;

        my ($host,$uri)=split(/\//,$url,2);

        my $socket=IO::Socket::INET->new(
            PeerAddr=>$host , PeerPort=>80 , Proto=>'tcp')
                or die("$@ for $host($url)");
        $socket->print("GET /$uri http/1.1\n");
        $socket->print("Host: $host\n");
        $socket->print("Connection: close\n");
        $socket->print("User-Agent: wifky $::version imgred plugin\n");
        $socket->print("\n");
        $socket->flush();
        local $/;
        undef $/;
        my ($header,$body)=split(/\n\r?\n/,scalar(<$socket>),2);
        $socket->close();
        &::write_object($session->{title},$url,$body);
        my $realurl=&::attach2url($session->{title},$url);
        
        $session->{attachment}->{$url} = {
            name => $url ,
            url  => $realurl ,
            tag  => sprintf('<img src="%s">' , $realurl ) ,
        };
    }
    $session->{attachment}->{$url}->{tag};
};

# (*::attach2tag , *org_attach2tag ) = (*::new_attach2tag , *::attach2tag );
# 
# sub new_attach2tag{
#     my ($session,$nm,$label)=@_;
#         $::form{a} eq 'Preview' &&
#     
# 
#     &org_attach2tag($session,$nm,$label);
# }
