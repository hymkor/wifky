$::inline_plugin{monta} = sub{
    if( $::form{a} !~ /rss/ ){
        '<span style="color:gray;background-color:gray">'.
        $_[0]->{argv}.
        '</span>';
    }else{
        '*' x length($_[0]->{argv});
    }
};

$::inline_plugin{confidential} = sub{
    if( ! &::is_frozen() ){
        '<blink>Please freeze this page to hide the secret information.</blink>'
    }elsif( &::is_signed() ){
        goto &{$::inline_plugin{monta}};
    }else{
        &anchor( 
            '(Confidential)',
            { a=>signin , p=>$::form{p} }
        );
    }
};
