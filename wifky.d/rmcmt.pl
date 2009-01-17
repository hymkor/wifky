# use strict; use warnings;

if( $::form{a} && $::form{a} eq 'edt' &&
    ( !defined(&::is_signed) || &is_signed() ) )
{
    $::form_list{'999_rmcmt'} = sub{
        my $comments = &read_object( $::form{p} , 'comment.0' );

        if( $comments ){
            &puts('</form>');
            &puts('<h2>Remove Comments</h2>');
            my $i=0;
            &putenc('<form action="%s" method="post">' , $::me );
            for my $c ( split(/\n/,$comments ) ){
                my ($dt,$who,$text)=split(/\t/,$c);
                &::puts('<div>');
                &::putenc('<input type="checkbox" name="no" value="%d" />' , $i );
                &::putenc('<span class="commentator">%s</span>' , &deyen($who) );
                &::putenc('%s <span class="comment_date">(%s)</span>' ,
                    &deyen($text) , $dt );
                &::puts('</div>');
                ++$i;
            }
            unless( defined( &::is_signed ) ){
                &puts('<p>Sign:<input type="password" name="password" />');
            }
            &puts('<input type="hidden" name="a" value="rmcmnt" />');
            &putenc('<input type="hidden" name="p" value="%s" />' , $::form{p} );
            &puts('<input type="submit" value="Remove"></p>');
        }

        my $referer = &read_object( $::form{p} , 'referer.txt' );

        if( $referer ){
            &puts('</form>');
            &puts('<h2>Remove Referers</h2>');
            my $i = 0;
            &putenc('<form action="%s" method="post">' , $::me );
            for my $r ( split(/\n/,$referer ) ){
                my (undef,$url)=split(/\t/,$r,2);
                &::putenc('<div><input type="checkbox" name="no" value="%d" />',$i++);
                &::putenc('<a href="%s" target="_blank">%s</a></div>' , $url , $r );
            }
            unless( defined( &::is_signed ) ){
                &puts('<p>Sign:<input type="password" name="password" />');
            }
            &puts('<input type="hidden" name="a" value="rmrefer" />');
            &putenc('<input type="hidden" name="p" value="%s" />' , $::form{p} );
            &puts('<input type="submit" value="Remove"></p>');
        }
    };
}

$::action_plugin{rmcmnt} = sub{
    if( defined( &::is_signed ) ){
        goto &signin unless &is_signed();
    }else{
        &ninsho;
    }
    my $comments = &read_object( $::form{p} , 'comment.0' );

    # This strange regular expression is to recover broken comments demilitor.
    my @comments = split(/\r?[\r\n]/,$comments );
    $comments[ $_ ] = '' for( @{$::forms{no}} );

    &write_object( $::form{p} , 'comment.0' , 
		   join("",map{$_ ne '' ? "$_\r\n" : () } @comments ) );

    &::transfer_page();
};

$::action_plugin{rmrefer} = sub{
    if( defined( &::is_signed ) ){
        goto &signin unless &is_signed();
    }else{
        &ninsho;
    }
    my $referer = &read_object( $::form{p} , 'referer.txt' );
    my @referers = split(/\n/,$referer );
    $referers[ $_ ] = '' for( @{$::forms{no}} );

    &write_object( $::form{p} , 'referer.txt' , join("\n",grep($_ ne '',@referers) ) );
    &::transfer_page();
};
