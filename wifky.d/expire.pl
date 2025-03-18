# 0.3_1 # expire.pl
package wifky::expire;

# use strict; use warnings;

mkdir 'expired',0755;

if( &::is_signed() ){
    if( $::form{p} ){
        if( ref($::menubar{'300_Edit'}) ){
            push(@{$::menubar{'300_Edit'}} ,
                &::anchor('Expire',{ p=>$::form{p} , a=>'expire' } )
            );
        }else{
            $::menubar{'555_expire'} = 
                &::anchor('Expire',{ p=>$::form{p} , a=>'expire' } );
        }
    }
    if( ref($::menubar{'600_Index'}) ){
        push( @{$::menubar{'600_Index'}} ,
              &::anchor('ExpireList',{ a=>'expirelist' } )
        );
    }else{
        $::menubar{'556_expirelist'} = &::anchor('ExpireList',{ a=>'expirelist' } );
    }
    if( @::index_action ){
        push( @::index_action , 
            ' <input type="submit" name="a" value="expire" />'
        );
    }
}

$::action_plugin{expire} = sub{
    goto &::action_signin unless &::is_signed();
    foreach my $title ( @{$::forms{p}} ){
        my @attach=&::list_attachment($title);
        my @tm=localtime;
        my $prefix=sprintf('%04d%02d%02d%02d%02d%02d'
                , 1900+$tm[5],1+$tm[4],@tm[3,2,1,0]);

        my @renlist = map{ &expire($prefix,$title,$_) } @attach;
        &renames( @renlist , &expire($prefix,$title) );
    }
    &::transfer_url($::me.'?a=recent');
};

$::action_plugin{restore} = sub {
    goto &::action_signin unless &::is_signed();
    my $stamp=$::form{q};
    die("!Invalid Parameter q=$stamp!") if $stamp !~ /^\d{14}$/;

    my $fname=&::title2fname($::form{p});
    my @renlist;
    local *DIR;
    opendir(DIR,"./expired") or die;
    while( my $fn=readdir(DIR)){
        if( $fn =~ /^(\d{14})__(([0-9a-f]+)(?:__[0-9a-f]+)?)$/ &&
            $1 eq $stamp  &&  $3 eq $fname )
        {
            push(@renlist,[ "./expired/$&" , $2 ]);
        }
    }
    closedir(DIR);
    &renames(@renlist);
    &::transfer_page($::form{p});
};

$::action_plugin{expirelist} = sub {
    goto &::action_signin unless &::is_signed();
    my $list=&expirelist();
    &::print_template(
        template => $::system_template ,
        main => sub{
            &::begin_day('Explired Pages');
            &::puts('<ul>');
            foreach my $p (reverse sort keys %{$list}){
                my ($stamp,$body)=split($;,$p);
                &::putenc('<li>%s' , $stamp );
                my $title=&::fname2title($body);
                if( -f $body ){
                    &::putenc('%s()' , $title );
                }else{
                    &::puts( &::anchor(&::enc($title), 
                        { p=>$title , a=>'restore' , q=>$stamp }));
                }
                &::puts('</li>');
            }
            &::puts('<li>no pages are expired.</li>') unless %{$list};
            &::puts('</ul>');
            &::end_day();
        }
    );
};

sub expire{
    my $prefix=shift;
    my $src = &::title2fname(@_);
    my $dst = "./expired/${prefix}__$src";
    die "!Found!" if -f $dst;
    [ $src , $dst ];
}

sub expirelist{
    local *DIR;
    opendir(DIR,"./expired") or die;
    my %list;
    while( my $fn=readdir(DIR) ){
        next unless my ($stamp,$body) = ($fn =~ /^(\d{14})__([a-z0-9]+)/);
        push(@{$list{$stamp,$body}},$');
    }
    closedir(DIR);
    \%list;
}

sub renames{
    foreach my $p (@_){
        rename($p->[0],$p->[1]);
    }
}
