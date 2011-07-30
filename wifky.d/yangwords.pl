package wifky::yangwords;

$::preferences{'Yet Another NG-Words Plugin 0.2'} = [
    {
        desc=>'Only administrator can write ng words.' ,
        name=>'yangwords_admin_ok' ,
        type=>'checkbox' ,
    },{
        desc=>'NG Words',
        name=>'yangwords',
        type=>'textarea',
        rows=>20,
    },
    {
        desc=>'record IP-address' ,
        name=>'yangwords_record_ip' ,
        type=>'checkbox' ,
    }
];

my $action_comment_orig = $::action_plugin{'comment'};
if( !&::is_signed() || !$::config{yangwords_admin_ok} ){
    (*::do_submit , *org_submit ) = (*new_submit , *::do_submit);
    $::action_plugin{'comment'} = \&new_comment;
}

sub new_submit{
    if( defined(my $item=&found_ng( \$::form{text_t})) ){
        die(qq{!Your subject has NG word: "$item".!});
    }
    &org_submit(@_);
};

sub new_comment{
    my $remote_addr = '{'.$ENV{REMOTE_ADDR}.'}';
    foreach my $text ( \$::form{'who'}, \$::form{'comment'}, \$remote_addr ){
        if( defined(my $item=&found_ng($text)) ){
            die(qq{!Your comment has NG word: "$item".!});
        }
    }
    if( $::config{yangwords_record_ip} ){
        unless( -f &::title2fname($::form{p}) ){
            die("There are no pages called '$::form{p}'");
        }
        my $fname=&::title2fname($::form{p},'comment_ip.txt');
        open(FP,">>$fname") or die("Can not open $fname for append");
            my @tm=localtime;
            printf FP "%04d/%02d/%02d %02d:%02d:%02d\t%s\r\n"
                , 1900+$tm[5],1+$tm[4],@tm[3,2,1,0]
                , $ENV{REMOTE_ADDR} ;

        close(FP);
    }
    $action_comment_orig->();
};

sub found_ng{
    my $text=shift;
    my @list = split(/\s+/,$::config{yangwords} || '');
    foreach my $item (@list) {
        if( index($$text,$item) >= 0 ){
            return $item;
        }
    }
    undef;
}

1;
