# 0.1_0 # tcalendar.pl
package wifky::tcalendar;

BEGIN{
    eval{ require 'strict.pm';   }; strict  ->import() unless $@;
    eval{ require 'warnings.pm'; }; warnings->import() unless $@;
}

my %yearcalendar;
foreach my $p (keys %::contents){
    if( $p =~ /^\((\d{4})\.(\d{2})\.\d{2}\)/ ){
        my $y = ($yearcalendar{$1} ||= {});
        if( !$y->{$2} || $p lt $y->{$2} ){
            $y->{$2} = $p;
        }
    }
}

$::inline_plugin{ycalendar} = sub{
    my $html = "<ul>\n";
    foreach my $y ( sort keys %yearcalendar ){
        $html .= '<li>'.$y;
        foreach my $m ( sort keys %{$yearcalendar{$y}} ){
            my $p=$yearcalendar{$y}->{$m};
            $html .= '|'.&::anchor($m,{ p=>$p }); 
        }
        $html .= "</li>\n";
    }
    $html . "</ul>\n";
};

$::inline_plugin{mcalendar} = sub {
    my (undef,$del1,$del2)=@_;
    my $pattern;
    if( $::form{p} && $::form{p} =~ /^\((\d{4})\.(\d{2})./ ){
        $pattern = $&;
    }else{
        my @t=localtime;
        $pattern = sprintf("(%04d.%02d.",1900 + $t[5],1 + $t[4]);
    }
    my %monthcalendar;
    foreach my $p (keys %::contents){
        next unless substr($p,0,9) eq $pattern && length($p)>=11;
        my $d = substr($p,9,2);
        if( ! $monthcalendar{$d} || $p lt $monthcalendar{$d} ){
            $monthcalendar{$d} = $p;
        }
    }
    my @buffer;
    foreach my $d (sort keys %monthcalendar){
        push(@buffer,&::anchor($d,{p=>$monthcalendar{$d}}));
    }
    '<span>'.substr($pattern,1,7) .
    ($del1 || '.') .
    join(($del2||"\n"),@buffer)."</span>";
};
