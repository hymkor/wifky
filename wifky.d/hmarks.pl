package wifky::hmarks;
#use strict;use warnings;

my $version="1.7_0";

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
    (*::midashi,*org_midashi ) = (*new_midashi,*::midashi);
}

###
### Hatena Bookmark Secion ###
###

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
    my $bookmark_url = &::myurl( { p=>$session->{title} } , $sharp||'' );
    (my $bookmark_entry_url = $bookmark_url)=~s/\#/\%23/g;

    if( defined $title ){
        $title = &::preprocess($title);
        &::unverb( \$title );
        $title =~ s/\<.*?\>//g;
    }else{
        $title = $session->{title};
    }
    $title =~ s/^ +//;
    my $fulltitle = $::config{sitename} . ' - ' . $title;

    my $tweet_url;
    if( $::charset eq 'EUC-JP' ){
        $tweet_url = &::myurl( { hp=>unpack('h*',$session->{title}) } , $sharp||'');
    }else{
        $tweet_url = $bookmark_url;
    }
    $tweet_url =~ s/\+/\%20/g;

    # [Bookmark anchor]
    &::verb( 
        sprintf('<a href="http://b.hatena.ne.jp/entry/%s" class="hatena-bookmark-button" data-hatena-bookmark-title="%s" data-hatena-bookmark-layout="%s" title="Add this entry to add hatena bookmark"><img src="http://b.st-hatena.com/images/entry-button/button-only.gif" alt="Add this entry to add hatena bookmark" width="20" height="20" style="border: none;" /></a><script type="text/javascript" src="http://b.st-hatena.com/js/bookmark_button.js" charset="utf-8" async="async"></script>'
            , $bookmark_url
            , &::enc( $fulltitle ) 
            , $::config{hmark_bookmark_style} || 'standard' ) .
        # [Twitter mark]
        sprintf(
            ' <a href="http://twitter.com/share" class="twitter-share-button" data-url="%s" data-text="&quot;%s&quot;" data-count="%s" %s data-lang="ja">Tweet</a><script type="text/javascript" src="http://platform.twitter.com/widgets.js"></script>'
            , &::enc($tweet_url)
            , &::enc($fulltitle)
            , $::config{hmark_tweet_style} || 'none'
            , $::config{hmark_twitter_id} 
                ? 'data-via="'.&::enc($::config{hmark_twitter_id}).'"'
                : ''
        )
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
        option=>[['standard','horizontal'],['vertical','vertical'],['simple','simple']] } ,
];

# vim:set sw=4 et notextmode:
