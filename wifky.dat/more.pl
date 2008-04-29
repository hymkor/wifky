
$inline_plugin{"version"} = sub{
    my $buffer="<ul>\n<li>wifky.pl ${version}</li>\n";
    while( my ($key,$val) = each %inline_plugin ){
	next unless $key =~ /_version/;
	$buffer .= sprintf("<li>%s</li>\n",&{$val});
    }
    $buffer . "</ul>";
};

$inline_plugin{"more.pl_version"} = sub{
    "more.pl 1.1";
};

$inline_plugin{"blue"} = sub{
    shift;
    '<span style="color:blue;font-weight:bold">' . join(" ",@_) . '</span>';
};
$inline_plugin{img} = sub{
    my ($session,$img,$w,$h)=@_;
    $w=( defined($w) ? qq(width="$w") : "");
    $h=( defined($h) ? qq(height="$h") : "");

    sprintf('<img src="%s" %s %s />'
	,$session->{attachment}->{$img}->{url},$w,$h
    );
};
$inline_plugin{banner} = sub{
    my ($session,$img,$url)=@_;
    if( $url =~ m|^http://| ){
	sprintf('<a href="%s"><img src="%s" border="0" class="banner" /></a>'
		    , $url
		    , $session->{attachment}->{$img}->{url}
	);
    }else{
	"<blink>invalid url for banner-plugin.</blink>";
    }
};
$inline_plugin{recentdays} = sub{
    my $max = ( $#_ >= 1 ? $_[1] : -1 );
    my %days = ();
    foreach my $fn ( &list_page() ){
	my $stamp = &mtime( $fn );
	my $date = substr($stamp, 0 , 10);
	my $time = substr($stamp, 11 );

	if( exists $days{ $date } ){
	    $days{ $date }->{ $time } = $fn;
	}else{
	    $days{ $date } = { $time => $fn };
	}
    }

    my $buffer="<dl>\n";
    foreach my $date (reverse sort keys %days){
	$buffer .= "<dt>${date}</dt>\n";
	foreach my $time ( reverse sort keys %{$days{$date}} ){
	    my $title=&fname2title($days{$date}->{$time});
	    $buffer .= sprintf( qq(<dd><a href="%s">%s</a></dd>\n) 
		, &title2url($title) , &enc($title) );
	}
	last if( --$max == 0 );
    }
    $buffer . "</dl>\n";
};

1
