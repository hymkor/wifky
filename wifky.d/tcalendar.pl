# 0.2_0 # tcalendar.pl
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
            $y->{$2} = $p if $::contents{$p}->{timestamp};
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

my %days_per_month1 = (
    "01"=>31, "02"=>28, "03"=>31, "04"=>30, "05"=>31, "06"=>30,
    "07"=>31, "08"=>31, "09"=>30, "10"=>31, "11"=>30, "12"=>31,
);
my %days_per_month2 = (
    "01"=>31, "02"=>29, "03"=>31, "04"=>30, "05"=>31, "06"=>30,
    "07"=>31, "08"=>31, "09"=>30, "10"=>31, "11"=>30, "12"=>31,
);

$::inline_plugin{mcalendar} = sub {
    my (undef,$del1,$del2)=@_;
    my ($pattern,$y,$m);
    if( $::form{p} && $::form{p} =~ /^\((\d{4})\.(\d{2})./ ){
        $y = $1 ; $m = $2;
        $pattern = $&;
    }else{
        my @t=localtime;
        $y = 1900 + $t[5]; $m = sprintf("%02d",1 + $t[4]);
        $pattern = "($y.$m.";
    }
    my %monthcalendar;
    foreach my $p (keys %::contents){
        next unless substr($p,0,9) eq $pattern && length($p)>=11;
        my $d = substr($p,9,2);
        if( ! $monthcalendar{$d} || $p lt $monthcalendar{$d} ){
            $monthcalendar{$d} = $p if $::contents{$p}->{timestamp};
        }
    }
    my $end;
    if( $y % 400 == 0 ){ # uru
        $end = $days_per_month2{ $m };
    }elsif( $y % 100 == 0 ){ # not uru
        $end = $days_per_month1{ $m };
    }elsif( $y % 4 == 0 ){ # uru
        $end = $days_per_month2{ $m };
    }else{ # not uru
        $end = $days_per_month1{ $m };
    }
    my @buffer;
    for(my $i=1;$i <= $end ; ++$i ){
        my $d = sprintf('%02d',$i);
        if( exists $monthcalendar{$d} ){
            $d = &::anchor($d,{p=>$monthcalendar{$d}});
        }
        push(@buffer,$d);
    }
    '<span>'.substr($pattern,1,7) .
    ($del1 || '.') .
    join(($del2||"\n"),@buffer)."</span>";
};
