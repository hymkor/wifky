
$inline_plugin{latest_attach} = sub {
    my ($session,$wildcard)=@_;
    return "" unless $wildcard;

    $wildcard =~ s/([^\*\?]+)/unpack('h*',$1)/eg;
    $wildcard =~ s/\?/../g;
    $wildcard =~ s/\*/.*/g;

    my @list = sort{
        $a->{name} cmp $b->{name}
    }grep{
        unpack('h*',$_->{name}) =~ /^$wildcard$/
    } values %{$session->{attachment}};
    if( @list ){
        $list[-1]->{tag};
    }else{
        "";
    }
};
