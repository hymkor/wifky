package Wifky::MacroPlugin;

# use strict; use warnings;

my $version='2.2';
my $rows=8;

my $pref=[];
my %code;

### for configuration ####
# count the required number of codes.
my $maxn=0;
while( my ($key,$val) = each %::config ){
    if( $key =~ /^htmlcode_(\d+)$/ && $val !~ /\A\s*\Z/ && $1 > $maxn ){
        $maxn = $1;
    }
}
++$maxn;

# regist each item.
for my $i (0..$maxn){
    my $name="htmlname_$i";
    my $code="htmlcode_$i";
    push( @{$pref} , 
	    { desc=>"No.${i} name" , name=>$name , size=>8 },
            { desc=>'code' , name=>$code , type=>'textarea' ,
              size=>128 , cols=>80 , rows=>8 },
    );
    $name=$::config{$name};
    $code=$::config{$code};
    if( $name && $code  && ! exists $::inline_plugin{$name} ){
        $::inline_plugin{$name} = sub{ 
            my $html=$code;
            $html =~ s/\$(\w~?)/&macro_param($1,@_)/ge;
            &::verb($html);
        };
    }
}

push( @{$pref} , 
    {
        desc=>'Codes in <head>...</head>' , name=>'htmlcode_in_header' ,
        type=>'textarea' , size=>128 , cols=>80 , rows=>8 
    }
);
$::preferences{"Macro-plugin(rawhtml.pl) $version"} = $pref;

### regist inline-plugin ###
$::inline_plugin{html} = sub{
    my $session=shift;
    my $no=(shift || 0);

    my $html=$::config{"htmlcode_$no"};
    $html =~ s/\$(\w~?)/&macro_param($1,@_)/ge;
    &::verb($html);
};

### insert header ###
if( $::form{a} ne 'tools' &&
    exists $::config{htmlcode_in_header} &&
    $::config{htmlcode_in_header} !~ /\A\s*\Z/ )
{
    push( @::html_header , $::config{htmlcode_in_header} );
}

### Macro ###
sub macro_param{
    my ($param,@argv)=@_;
    my $rv;
    if( $param =~ /^[1-9]+/ && $param <= $#argv ){
        $rv=$argv[$param] || '';
    }elsif( $param =~ /^p/ ){
        $rv=$argv[0]->{title};
    }elsif( $param =~ /^P/ ){
        $rv=$::form{p} || $::config{FrontPage};
    }elsif( $param =~ /^x/ ){
        $rv=$::me;
    }elsif( $param =~ /^X/ ){
        $rv=$::postme;
    }else{
        $rv='$'.$param;
    }
    if( $param =~ /~$/ ){
        $rv = &::percent(&::denc($rv));
    }
    $rv;
}
