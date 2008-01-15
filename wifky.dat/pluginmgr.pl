# Plugin Manager
# support wifky 1.3 or later.

# Do not use 'package' statement.
# PackageManager must run in main-packages.

# use strict;use warnings; 

my $version='0.6';

-d 'plugins' or mkdir('plugins',0777) or die('can not mkdir plugins directory');

###
### Create link to pluginmgr
###

if( &is_signed() ){
    $::inline_plugin{'a_pluginmgr'} = sub {
        &::verb( qq(<a href="$::me?a=pluginmgr">Plugin Manager</a>) );
    };
    $::menubar{'501_Pluginmgr'} 
        = &anchor('Plugin',{a=>'pluginmgr'},{ref=>'nofollow'});
}

###
### create plugin list
### 

local *DIR;
opendir(DIR,'plugins');
my @plugins =
    sort{ $a->{name} cmp $b->{name} } 
    map {
        +{ 
            name  => pack('h*',$_) ,
            hexnm => $_  ,
            key   => "pluginmgr__$_" ,
            path  => "plugins/$_" ,
        };
    }
    grep{ /^([0-9a-f][0-9a-f])+$/ }
    readdir(DIR) ;
closedir(DIR);

###
### Load plugins
###

unless( $::form{a} && ($::form{a} =~ /^pluginmgr/ || $::form{a} eq 'signin') ){
    foreach my $p ( grep( $::config{$_->{key}} , @plugins) ){
        do $p->{path} ; $@ and die($@);
    }
}

###
### Plugin Uploader
###

$::action_plugin{'pluginmgr_upload'} = sub{
    goto &action_signin unless &is_signed();

    my $name=$::form{'plugin.filename'};
    my $body=$::form{'plugin'};
    local *FP;
    my $hexnm = unpack('h*',$name);
    open(FP,">plugins/$hexnm") or die;
        print FP $body;
    close(FP);
    if( $::form{'enable'} ){
        $::config{"pluginmgr__$hexnm"} = 1;
    }else{
        $::config{"pluginmgr__$hexnm"} = 0;
    }
    &::save_config();
    &::transfer_url( "$::me?a=pluginmgr" );
};

###
### Plugin Enable/Disabler
###

$::action_plugin{'pluginmgr_permit'} = sub {
    goto &action_signin unless &is_signed();

    foreach my $key (grep(/^pluginmgr__/,keys %::config)){
        delete $::config{$key};
    }
    while( my ($key,$value)=each %::form ){
        $::config{$key} = 1 if $key =~ /^pluginmgr__/;
    }
    &::save_config;
    &::transfer_url( "$::me?a=pluginmgr" );
};

###
### Plugin Eraser
###
$::action_plugin{'pluginmgr_erase'} = sub {
    goto &action_signin unless &is_signed();

    my $fn=$::form{target};
    $fn =~ /^([0-9a-f][0-9a-f])+$/ or die("!Invalied plugin-filename $fn!");
    -f "./plugins/$fn" or die('!Remove not exists plugin!');
    unlink "./plugins/$fn";
    &::transfer_url( "$::me?a=pluginmgr" );
};

###
### Plugin Manager Menu
###

$::action_plugin{'pluginmgr'} = sub {
    goto &action_signin unless &is_signed();

    unshift(@::copyright,"<div>Plugin Manager $version</div>");
    &::print_header( divclass=>'max' , title=>'Plugin Manager' );
    &::putenc(<<HTML
<div class="day">
<h2>Enable/Disable Plugin</h2>
<div class="body">
<form name="plugin_form" action="%s" method="post" accept-charset="%s" >
HTML
    , $::postme , $::charset );
    foreach my $p (@plugins){
        &::putenc('<div><input type="checkbox" name="%s" value="1"%s> %s</div>'
            , $p->{key} 
            , $::config{$p->{key}} ? ' checked':''
            , $p->{name} );
    }
    foreach my $nm ( sort grep(/\.pl$/,&::directory() )){
        &::putenc('<input type="checkbox" checked disabled> %s (hand-installed)<br>'
            , $nm );
    }
    &::putenc(<<HTML
<p>
<input type="hidden" name="a" value="pluginmgr_permit">
<input type="submit" value="Enable/Disable">
</p>
</form>
</div><!-- body -->
</div><!-- day -->
<div class="day">
<h2>New plugin</h2>
<div class="body">
<form name="plugin_form" action="%s" enctype="multipart/form-data"
 method="post" accept-charset="%s" >
<p>Plugin file: <input type="file" name="plugin" size="48">
<input type="checkbox" name="enable" value="1" checked>enable?</p>
<p><input type="hidden" name="a" value="pluginmgr_upload"
><input type="submit" value="Upload">
</p>
</form>
</div><!-- body -->
</div><!-- day -->
<div class="day">
<h2>Erase unused Plugins</h2>
<div class="body">
<form action="%s" method="post" accept-charset="%s">
HTML
    , $::me , $::charset 
    , $::me , $::charset 
    );

    foreach my $p (@plugins){
        unless( $::config{ $p->{key} } ){
            &::putenc('<div><input type="radio" name="target" value="%s"> %s</div>'
                , $p->{hexnm}
                , $p->{name}
            );
        }
    }
    &::putenc(<<HTML
<p><input type="hidden" name="a" value="pluginmgr_erase"
><input type="submit" value="Erase" onClick="JavaScript:return window.confirm('Erase Sure?')"></p>
</form>
</div><!-- body -->
</div><!-- day -->
HTML
    );
    &::print_copyright;
    &::print_footer;
};

1;
