# 0.1 # expimp.pl

push( @::index_action , '<input type="submit" name="a" value="export" />' );
if( &::is_signed ){
    push( @{$::menubar{'500_Tools'}} ,
            &::anchor('Import',{ a=>'Import',rel=>'nofollow' } ) );
}

$::action_plugin{export} = sub {
    goto &::action_signin unless &::is_signed();
    unless( exists $::form{p} ){
        return &::transfer(url=>&::myurl({a=>'index'}));
    }
    print "Content-Type: application/octet-stream\r\n";
    print "Content-Disposition: attachment; filename=wifkydmp.tgz\r\n";
    print "\r\n";

    my @tar=("/usr/bin/tar","zcf","-");
    foreach my $p ( @{$::forms{p}} ){
        push(@tar,&::title2fname($p));
        foreach my $a ( &::list_attachment($p) ){
            push(@tar,&::title2fname($p,$a));
        }
    }
    system(@tar);
    exit(0);
};

$::action_plugin{Import} = sub{
    goto &::action_signin unless &::is_signed();

    &::print_template(
        template => $::system_template ,
        Title => 'Import Pages' ,
        main => sub{
            &::putenc(
                '<form action="%s" method="post" '.
                'enctype="multipart/form-data">' .
                '<input type="file" name="wifkydmp_b" />'.
                '<input type="submit" name="a" value="import" />'.
                '</form>'
                , $::me
            );
        }
    );
};

$::action_plugin{import} = sub{
    goto &::action_signin unless &::is_signed();

    if( exists $::form{wifkydmp_b} ){
        local *FP;
        open(FP,'|/usr/bin/tar zxf -') or die("!tar error!");
        print FP $::form{wifkydmp_b};
        close(FP);
    }
    &::transfer(url=>&::myurl({a=>'index'}));
};
