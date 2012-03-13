# 1.12_0 # hmarks.pl

package wifky::hmarks;
#use strict;use warnings;

my $version="1.12_0";

if( exists $::form{hp} ){
    print  "Status: 301 See Other\r\n";
    printf "Location: %s\r\n", &::myurl( { p=>pack('h*',$::form{hp} ) } );
    print  "\r\n\r\n";
    exit(0);
}

if( ! exists $::form{p} && exists $::form{hp} ){
    $::form{p} = pack('h*',$::form{hp});
}

if( $::config{hmark_each_section} ){
    (*::headline,*org_headline ) = (*new_headline,*::headline);
}

###
### Hatena Bookmark Secion ###
###

sub new_headline{
    my %arg = @_;
    my ($depth,$text,$session)=($arg{n}-3,$arg{body},$arg{session});
    if( $depth == 0 &&
        $session->{title} ne 'Footer'  &&
        $session->{title} ne 'Sidebar' &&
        $session->{title} ne 'Header'  &&
        $session->{title} ne 'Footest' &&
        $session->{title} ne 'Help' &&
        $session->{title} !~ /^\./ )
    {
        $arg{body} .= &marking(
            $session,
            "#p". ( exists $session->{section} ? $session->{section}->[$depth] : 1),
            $text
        );

        &org_headline( %arg );
    }else{
        &org_headline( %arg );
    }
}

if( $::config{hmark_each_page} ){
    $::call_syntax_plugin{'200_bookmark'} = sub {
        my $session=$_[1];
        return if exists $session->{nest} && $session->{nest} > 1;

        if( $session->{title} ne 'Footer'  &&
            $session->{title} ne 'Sidebar' &&
            $session->{title} ne 'Header'  &&
            $session->{title} ne 'Footest' &&
            $session->{title} ne 'Help'    &&
            $session->{title} !~ /^\./ )
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
    my $url = &::myurl( { p=>$session->{title} } , $sharp||'' );

    if( defined $title ){
        $title = &::preprocess($title);
        &::unverb( \$title );
        $title =~ s/\<.*?\>//g;
    }else{
        $title = $session->{title};
    }
    $title =~ s/^ +//;
    $title = $::config{sitename} . ' - ' . $title;

    &::verb(
        &anchor_delicous     ($url,$title,$session) .
        &anchor_livedoor_clip($url,$title,$session) .
        &anchor_hatena       ($url,$title,$session) .
        &anchor_twitter      ($url,$title,$session) .
        &anchor_facebook     ($url,$title,$session)
    );
}

sub anchor_livedoor_clip{
    my ($url,$title)=@_;
    sprintf(' <a href="http://clip.livedoor.com/redirect?link=%s&title=%s&ie=%s" class="ldclip-redirect" title="[Livedoor Clip]"><img src="http://parts.blog.livedoor.jp/img/cmn/clip_16_16_w.gif" width="16" height="16" alt="[Livedoor Clip]" style="border: none" /></a> '
        , &::enc( $url )
        , &::enc( $title ) 
        , $::charset );
}

sub anchor_hatena{
    my ($url,$title,$session)=@_;

    if( $::config{hmark_bookmark_style} &&
        $::config{hmark_bookmark_style} ne 'off' )
    {
        sprintf('<a href="http://b.hatena.ne.jp/entry/%s" class="hatena-bookmark-button" data-hatena-bookmark-title="%s" data-hatena-bookmark-layout="%s" title="[Add this entry to hatena bookmark]"><img src="http://b.st-hatena.com/images/entry-button/button-only.gif" alt="[Add this entry to hatena bookmark]" width="20" height="20" style="border: none;" /></a><script type="text/javascript" src="http://b.st-hatena.com/js/bookmark_button_wo_al.js" charset="utf-8" async="async"></script>'
                , $url
                , &::enc( $title )
                , $::config{hmark_bookmark_style}
        );
    }else{
        '';
    }
}

sub anchor_twitter{
    my ($url,$title,$session)=@_;
    if( $::charset eq 'EUC-JP' ){
        # $url = &::myurl( { hp=>unpack('h*',$session->{title}) } , $sharp||'');
        return '';
    }
    $url =~ s/\+/\%20/g;

    sprintf(
        ' <a href="http://twitter.com/share" class="twitter-share-button" data-url="%s" data-text="&quot;%s&quot;" data-count="%s" %s data-lang="ja">Tweet</a><script type="text/javascript" charset="utf-8" src="http://platform.twitter.com/widgets.js"></script>'
        , &::enc($url)
        , &::enc($title)
        , $::config{hmark_tweet_style} || 'none'
        , $::config{hmark_twitter_id} 
            ? 'data-via="'.&::enc($::config{hmark_twitter_id}).'"'
            : ''
    );
}

sub anchor_facebook{
    my ($url,$title,$session)=@_;

    sprintf('<iframe src="http://www.facebook.com/plugins/like.php?href=%s&amp;layout=button_count&amp;show_faces=false&amp;width=100&amp;action=like&amp;colorscheme=light&amp;height=21" scrolling="no" frameborder="0" style="border:none; overflow:hidden; width:100px; height:21px;" allowTransparency="true"></iframe>',
            , &::percent($url)
    );
}

sub anchor_delicous{
    my ($url,$title,$session)=@_;

    sprintf(q| <a href="http://www.delicious.com/save" onclick="window.open('http://www.delicious.com/save?v=5&noui&jump=close&url='+encodeURIComponent('%s')+'&title='+encodeURIComponent('%s'), 'delicious','toolbar=no,width=550,height=550'); return false;" title="[Delicous]"><img src="http://www.delicious.com/static/img/delicious.small.gif" height="10" width="10" alt="[Delicious]" border="0" /></a> |
        , &::enc($url)
        , &::enc($title)
    );
}

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
    { desc=>'Twitter: display Tweet counter' , name=>'hmark_tweet_style' , type=>'radio',
        option=>[['horizontal','horizontal'],['vertical','vertical'],['none','simple']] },
    { desc=>'HatenaStar: Token', name=>'hatenastar_token', type=>'text', size=>41 },
    { desc=>'HatenaBookmark Style', name=>'hmark_bookmark_style', type=>'radio' ,
        option=>[
            ['off','off'],
            ['standard','horizontal'],
            ['vertical','vertical'],
            ['simple','simple']
        ] } ,
];

# vim:set sw=4 et notextmode:
