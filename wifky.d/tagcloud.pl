$::inline_plugin{tagcloud}=sub {
    my $html='<div class="tagcloud">';
    my @count_and_style=( 
        [22,"150","bold"],
        [19,"150","normal"],
        [16,"120","bold"],
        [13,"120","normal"],
        [10,"100","bold"],
        [ 7,"100","normal"],
        [ 4,"88.8","bold"],
        [ 0,"88.8","normal"],
    );
    while( my ($label,$list)=each %::label_contents ){
        my $style='';
        foreach my $s (@count_and_style){
            if( scalar(@{$list}) >= $s->[0] ){
                $style=sprintf('font-size:%s%%;font-weight:%s',$s->[1],$s->[2]);
                last;
            }
        }
        $html .= &anchor(&enc($label), { tag=>$label,a=>'index'}, { style=>$style });
        $html .= "\n";
    }
    $html .= '</div>';
};
