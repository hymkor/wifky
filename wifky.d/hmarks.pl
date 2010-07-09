package wifky::hmarks;
use strict;use warnings;
use Encode ();

my $version="1.5_1";

###
### Hatena Bookmark Secion ###
###

if( ! exists $::form{p} && exists $::form{q} ){
    $::form{p} = unypack($::form{q});
}

(*::midashi,*org_midashi ) = (*new_midashi,*::midashi);

sub new_midashi{
    my ($depth,$text,$session)=@_;
    if( $depth == 0 &&
        $session->{title} ne 'Footer'  &&
        $session->{title} ne 'Sidebar' &&
        $session->{title} ne 'Header' )
    {
        &org_midashi(
            $depth ,
            $text . &marking(
                $session,
                "#p". ( exists $session->{section} ? 1+$session->{section}->[$depth] : 1),
                $text
            ) ,
            $session
        );
    }else{
        &org_midashi($depth,$text,$session);
    }
}

$::call_syntax_plugin{'200_bookmark'} = sub {
    my $session=$_[1];
    return if exists $session->{nest} && $session->{nest} > 1;

    if( $session->{title} ne 'Footer'  &&
        $session->{title} ne 'Sidebar' &&
        $session->{title} ne 'Header'  )
    {
        &::puts('<div align="right" class="hatenabookmark">'
            .&marking($session).'</div>' );
    }
};

sub marking{
    my ($session,$sharp,$title)=@_;
    local $::me = 'http://' . (
                    defined $ENV{'HTTP_HOST'}
                  ? $ENV{'HTTP_HOST'}
                  : defined $ENV{'SERVER_PORT'} && $ENV{'SERVER_PORT'} != 80
                  ? $ENV{'SERVER_NAME'} . ':' . $ENV{'SERVER_PORT'}
                  : $ENV{'SERVER_NAME'}
            ) . $ENV{'SCRIPT_NAME'};
    local $::postme=$::me;
    my $url1 = &::myurl( { p=>$session->{title} } , $sharp||'' );
    (my $url2 = $url1)=~s/\#/\%23/g;

    my $mini_url = &::myurl( { q=>ypack($session->{title}) } , $sharp ||'');
    if( length($mini_url) >= length($url1) ){
        $mini_url = &::percent($url1);
    }
    $mini_url =~ s/\#/\%23/g;

    $title ||= $session->{title};
    $title =~ s/^ +//;
    my $fulltitle = $::config{sitename} . ' - ' . $title;

    if( $::charset eq 'EUC-JP' ){
        Encode::from_to($title,'euc-jp','utf8');
        Encode::from_to($fulltitle,'euc-jp','utf8');
    }

    # [Bookmark anchor]
    sprintf(
        ' <a href="http://b.hatena.ne.jp/add?mode=confirm&title=%s&url=%s"><img src="%s" alt="[B!]" border="0" /></a><a href="http://b.hatena.ne.jp/entry/%s"><img src="http://b.hatena.ne.jp/entry/image/%s" border="0" alt="[n user]"/></a>'
        , &::percent( $title )
        , &::percent( $url1 )
        , &::enc($::config{hatenabookmark_mark} || ($::me . '?a=b_entry') )
        , $url2
        , $url2
    ) .
    # [Twitter mark]
    sprintf(
        q{ <a href="http://twitter.com/home/?status=%%22%s%%22+%s"><img src="%s" border="0" alt="[Tw]" /></a>}
        , &::percent($title)
        , &::enc($mini_url)
        , &::enc($::config{twit_mark} || ($::me . '?a=t_logo'))
    );
}

### Print mark [B!] ###
$::action_plugin{b_entry} = sub {
    my $image=pack('h*',<<__BIN__);
7494648393160100c0001920008114ecffffffffffff000000129f401000002000c2000000000100c00000206241e89961deffe0c0ac94a614bb21d6d418a47558b568278e7668ad562c952ce46306c8ab050000b3
__BIN__
    print  "Content-Type: image/gif\n";
    printf "Content-Length: %d\n",length($image);
    print  "\n";
    print  $image;
    exit(0);
};
### Print mark [Tw] ###
$::action_plugin{t_logo} = sub {
    my $image=pack('h*',<<__BIN__);
9805e474d0a0a1a0000000d09484442500000001000000018060000000f13fff16000000403724944580808080c780468800000090078495370000a00f0000a00f1024ca43890000006147548547342756164796f6e6024596d656001313f21343f20393fbedae90000000c14754854735f6664777162756001446f62656026496275677f627b63702343543602b3d0a000010d39444144583d859291be43c030168fb42e2912c084809c2a2644035f50a34e51a26beb10f20cecac374706c6f5181ab57262614269a419a328d098b6b91a4942d44d827295a3d9ffff3ddd9d1ca65ba3306104a4fb871062208584923d1e078dbcdbe5fa3dc2bc6120845a4985b6b7104a49469569a00a66ecd5081fbbc70104c1af3a0a600c0289cbd00089d5b1e222b40d5007ecdf71c780aef87fef3107a98825ced22cbd620a63f7856af0f15a939806e7be906b547006074afd34d6b10aa3fedb4bcdd9fe6cbf2b0892ab102a279ac6d7d7ec97c57102cda164980e5550cc63123bdce69294403fb1f81df953048b70cef89f65c3e5d69152dc7f7f70ad6de0ca65807e87abc488e42e2dced164ba6fd145ff10041a515865d8e0ad2400b4da5f83e83ee417532fc37085a006a97e9f3715413ee300fedf2189ef2b7049af3120e99e9000000009454e444ea240628
__BIN__
    print  "Content-Type: image/png\n";
    printf "Content-Length: %d\n",length($image);
    print  "\n";
    print  $image;
    exit(0);
};

###
### Hatena Star Section
###

my $token=$::config{hatenastar_token};
if( $token ){
    push( @::html_header , <<END );
<!-- HatenaStar -->
<script type="text/javascript" src="http://s.hatena.ne.jp/js/HatenaStar.js"></script>
<script type="text/javascript"><!--
    Hatena.Star.Token = '${token}';
    Hatena.Star.SiteConfig = {
        entryNodes: {
            'div.xsection':{ uri: 'h3 a', title: 'h3', container: 'h3' },
            'div.day'     :{ uri: 'h2 a', title: 'h2', container: 'h2' }
    }
};
// -->
</script>
END
}

### Images ###
my $html='';
for my $key (qw/star add-button comment-button/){
    my $configid="hatenastar_${key}_image"; $configid =~ s/-/_/g;
    my $url = $::config{$configid};
    if( defined $url && $url !~ /^\s*$/ ){
        $html .= "  .hatena-star-${key}-image{\n  background-image: url($url)\n}\n";
    }
}
push( @::html_header , qq(<style type="text/css">\n$html</style>) ) if $html;

### Configuration ###

$::preferences{"Heading marks ${version}"} = [
    { desc=>'HatenaStar: Token', name=>'hatenastar_token', type=>'text', size=>41 },
    { desc=>'HatenaStar: image(URL)',   name=>'hatenastar_star_image' , size=>41 },
    { desc=>'HatenaStar: Add button image(URL)', name=>'hatenastar_add_button_image', size=>41 },
    { desc=>'HatenaStar: Comment button image(URL)', name=>'hatenastar_comment_button_image', size=>41 },
    { desc=>'HatenaBookmark: static-image(URL)' , name=>'hatenabookmark_mark' , size=>41 } ,
    { desc=>'Twitter: static-image(URL)' , name=>'twit_mark' , size=>41 } ,
];

sub ypack{
    my $s=pack('u*',shift);
    $s =~ y/\x20-\x95`\r\n/\-_A-Za-z0-9\-/d;
    $s;
}
sub unypack{
    (my $s=shift) =~ y/\-_A-Za-z0-9/\x20-\x95/;
    unpack('u*',$s);
}
# vim:set sw=4 et notextmode:
