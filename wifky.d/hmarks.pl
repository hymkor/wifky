package wifky::hmarks;
use strict;use warnings;
use Encode ();

my $utf8=Encode::find_encoding('utf8');
my $eucjp=Encode::find_encoding('euc-jp');

my $version="1.6_0";

###
### Hatena Bookmark Secion ###
###

if( exists $::form{utf8p} ){
    print  "Status: 301 See Other\r\n";
    printf "Location: %s\r\n",
        &::myurl( { p=>$eucjp->encode( $utf8->decode( $::form{utf8p} ) ) } );
    print  "\r\n\r\n";
    exit(0);
}

if( ! exists $::form{p} && exists $::form{q} ){
    $::form{p} = unypack($::form{q});
}

if( $::config{hmark_each_section} ){
    (*::midashi,*org_midashi ) = (*new_midashi,*::midashi);
}

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

if( $::config{hmark_each_page} ){
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
}

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

    $title ||= $session->{title};
    $title =~ s/^ +//;
    my $fulltitle = $::config{sitename} . ' - ' . $title;

    if( $::charset eq 'EUC-JP' ){
        $url1 = &::myurl(
            { utf8p=>$utf8->encode( $eucjp->decode($session->{title}) ) } ,
            $sharp||''
        );
    }
    $url1 =~ s/\+/\%20/g;

    # [Bookmark anchor]
    &::verb( 
        sprintf(
            ' <a href="http://b.hatena.ne.jp/add?mode=confirm&title=%s&url=%s"><img src="%s" alt="[B!]" border="0" /></a><a href="http://b.hatena.ne.jp/entry/%s"><img src="http://b.hatena.ne.jp/entry/image/%s" border="0" alt="[n user]"/></a>'
            , &::percent( $fulltitle )
            , &::percent( $url1 )
            , &::enc($::config{hatenabookmark_mark} || ($::me . '?a=b_entry') )
            , $url2
            , $url2
        ) .
        # [Twitter mark]
        sprintf(
            ' <a href="http://twitter.com/share" class="twitter-share-button" data-url="%s" data-text="&quot;%s&quot;" data-count="%s" %s data-lang="ja">Tweet</a><script type="text/javascript" src="http://platform.twitter.com/widgets.js"></script>'
            , &::enc($url1)
            , &::enc($fulltitle)
            , $::config{hmark_tweet_counter} ? 'horizontal' : 'none'
            , $::config{hmark_twitter_id} 
                ? 'data-via="'.&::enc($::config{hmark_twitter_id}).'"'
                : ''
        )
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
    { desc=>'Twitter: Your id' , name=>'hmark_twitter_id' },
    { desc=>'Twitter: mark on each page header', name=>'hmark_each_page', type=>'checkbox' },
    { desc=>'Twitter: mark on each section header', name=>'hmark_each_section', type=>'checkbox' },
    { desc=>'Twitter: display Tweet counter' , name=>'hmark_tweet_counter' , type=>'checkbox' },
    { desc=>'HatenaStar: Token', name=>'hatenastar_token', type=>'text', size=>41 },
    { desc=>'HatenaStar: image(URL)',   name=>'hatenastar_star_image' , size=>41 },
    { desc=>'HatenaStar: Add button image(URL)', name=>'hatenastar_add_button_image', size=>41 },
    { desc=>'HatenaStar: Comment button image(URL)', name=>'hatenastar_comment_button_image', size=>41 },
    { desc=>'HatenaBookmark: static-image(URL)' , name=>'hatenabookmark_mark' , size=>41 } ,
];

sub unypack{
    (my $s=shift) =~ y/\-_A-Za-z0-9/\x20-\x95/;
    unpack('u*',$s);
}
# vim:set sw=4 et notextmode:
