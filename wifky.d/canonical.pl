$::preferences{Canonical} = [
    { name=>"canonical_url" ,
      desc=>"Canonical TOP URL" ,
      size=>40 ,
    }
];

if( my $url=$::config{canonical_url} ){
    if( my $q=$ENV{QUERY_STRING} ){
        $url .= '?'.$q;
    }
    $url = &enc($url);
    push( @html_header , qq{<link rel="canonical" href="$url" />} );
}
