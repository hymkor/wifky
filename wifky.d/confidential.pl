$::inline_plugin{confidential} = sub{
    if( ! &::is_frozen() ){
        '<blink>Please freeze this page to hide the secret information.</blink>'
    }elsif( &::is_signed() ){
	$_[0]->{argv};
    }else{
        &anchor( 
            '(Confidential)',
            { a=>signin , p=>$::form{p} }
        );
    }
};
