#!/usr/local/bin/perl -T

use strict; use warnings;

$::version  = '1.5.1_0';

$::version .= '++' if defined(&strict::import);
$::PROTOCOL = '(?:s?https?|ftp)';
$::RXURL    = '(?:s?https?|ftp)://[-\\w.!~*\'();/?:@&=+$,%#]+' ;
$::charset  = 'UTF-8';
%::form     = %::forms = ();
$::me       = $::postme = $ENV{SCRIPT_NAME} || (split(/[\\\/]/,$0))[-1];
$::print    = ' 'x 10000; $::print = '';
%::config   = ( crypt => '' , sitename => 'wifky!' );
%::flag     = ();
%::cnt      = ();

my $messages = '';

if( $0 eq __FILE__ ){
    binmode(STDOUT);
    binmode(STDIN);

    eval{
        local $SIG{ALRM} = sub { die("Time out"); };
        local $SIG{__WARN__} = local $SIG{__DIE__} = sub {
            return if ( caller(0) )[1] =~ /\.pm$/;
            my $msg=join(' ',@_);
            if( $msg =~ /^!(.*)!/ ){
                $messages .= '<div>'.&enc($1)."</div>\n" ;
            }else{
                $messages .= '<div>'.&enc($msg)."</div>\n" ;
                my $i=0;
                while( my (undef,$fn,$lno,$subnm)=caller($i++) ){
                    $messages .= sprintf("<div> &nbsp; on %s at %s line %d.</div>\n" ,
                                &enc($subnm),&enc($fn),$lno );
                }
            }
        };
        eval{ alarm 60; };

        &read_form;
        &chdir_and_code;
        foreach my $pl (sort map(/^([\w\.]+\.plg)$/ ? $1 : () ,&directory) ){
            do "./$pl"; die($@) if $@;
        }
        &load_config;
        &init_globals;
        foreach my $pl (sort map(/^([\w\.]+\.pl)$/ ? $1 : (),&directory) ){
            do "./$pl"; die($@) if $@;
        }

        if( $::form{a} && $::action_plugin{$::form{a}} ){
            $::action_plugin{ $::form{a} }->();
        }elsif( $::form{p} ){ # page view
            if( $::form{f} ){ # output attachment
                &action_cat();
            }else{ # output page itself.
                &action_view($::form{p});
            }
        }else{
            &action_default();
        }

        &flush;
        eval{ alarm 0; };
    };
    if( $@ ){
        print $_,"\r\n" for @::http_header;
        print "Content-Type: text/html;\r\n" unless grep(/^Content-Type:/i,@::http_header);
        print "\r\n<html><body>\n",&errmsg($@);
        print $messages if $@ !~ /^!/;
        print "</body></html>\n";
    }
    exit(0);
}

sub action_default{
    if( &object_exists($::config{FrontPage}) ){
        &action_view($::config{FrontPage});
    }else{
        &do_index('recent','rindex','-l');
    }
}

sub chdir_and_code{
    (my $udir = __FILE__ ) =~ s/\.\w+((\.\w+)*)$/.d$1/;
    if( chdir $udir ){
        return;
    }
    (my $edir = __FILE__ ) =~ s/\.\w+((\.\w+)*)$/.dat$1/;
    if( chdir $edir ){
        $::charset = 'EUC-JP';
        return;
    }
    mkdir($udir,0755);
    unless( chdir $udir ){
        die("can not access $udir or $edir.");
    }
}

sub init_globals{
    if( &is('locallink') ){
        $::PROTOCOL = '(?:s?https?|ftp|file)';
        $::RXURL    = '(?:s?https?|ftp|file)://[-\\w.!~*\'();/?:@&=+$,%#]+';
    }

    $::target = ( $::config{target}
                ? sprintf(' target="%s"',$::config{target}) : '' );
    $::config{CSS} ||= 'CSS';
    $::config{FrontPage} ||= 'FrontPage';
    ( $::session_cookie = ( split(/[\\\/]/,$0) )[-1] ) =~ s/\.\w+$/_session/;

    %::inline_plugin = (
        'adminmenu'=> \&plugin_menubar ,
        'menubar'  => \&plugin_menubar ,
        'nomenubar'=> sub{ $::flag{menubar_printed}=1;'' } ,
        'pagename' => \&plugin_pagename ,
        'recent'   =>
            sub{ '<ul>'.&ls('-r','-t',map("-$_",@_[1..$#_])) . '</ul>' } ,
        'search'   => \&plugin_search ,
        'fn'       => \&plugin_footnote ,
        'ls'       => sub{ '<ul>' . &ls(map(&denc($_),@_[1..$#_])) . '</ul>' },
        'comment'  => \&plugin_comment ,
        'sitename' => sub{ &enc( $::config{sitename} || '') } ,
        'br'       => sub{ '<br>' } ,
        'clear'    => sub{ '<br clear="all">' } ,
        'lt'       => sub{ '&lt;' } ,
        'gt'       => sub{ '&gt;' } ,
        'amp'      => sub{ '&amp;' } ,
        'lp'       => sub{ '&#40;' } ,
        'rp'       => sub{ '&#41;' } ,
        'lb'       => sub{ '&#91;' } ,
        'rb'       => sub{ '&#93;' } ,
        'll'       => sub{ '&#40;&#40;' },
        'rr'       => sub{ '&#41;&#41;' },
        'vl'       => sub{ '&#124;' },
        'v'        => sub{ '&' . ($#_ >= 1 ? $_[1] : 'amp') . ';' },
        'bq'       => sub{ '&#96;' },
        'null'     => sub{ '' } ,
        'outline'  => \&plugin_outline ,
        '#'        => sub{ $::ref{$_[2]||0} = ++$::cnt{$_[1]||0} } ,
    );

    %::action_plugin = (
        'index'         => sub{ &do_index('recent','rindex','-i','-a','-l');  },
        'rindex'        => sub{ &do_index('recent','index' ,'-i','-a','-l','-r'); },
        'older'         => sub{ &do_index('recent','index' ,'-i','-a','-l','-t'); },
        'recent'        => sub{ &do_index('older' ,'index' ,'-i','-a','-l','-t','-r');},
        '?'             => \&action_seek ,
        'edt'           => \&action_edit ,
        'passwd'        => \&action_passwd ,
        'comment'       => \&action_comment ,
        'Delete'        => \&action_delete ,
        'Commit'        => \&action_commit ,
        'Preview'       => \&action_preview ,
        'rollback'      => \&action_rollback ,
        'rename'        => \&action_rename ,
        'Upload'        => \&action_upload ,
        'tools'         => \&action_tools ,
        'preferences'   => \&action_preferences ,
        'new'           => \&action_new ,
        'Freeze/Fresh'  => \&action_freeze_or_fresh ,
        'signin'        => \&action_signin ,
        'signout'       => \&action_signout ,
    );

    @::http_header = ( "Content-type: text/html; charset=$::charset" );

    @::html_header = (
      qq(<meta http-equiv="Content-Type" content="text/html; charset=$::charset">\n<meta http-equiv="Content-Style-Type" content="text/css">\n<meta name="generator" content="wifky.pl $::version">\n<link rel="start" href="$::me">\n<link rel="index" href="$::me?a=index">)
    );

    @::body_header = (
        qq{<form name="newpage" action="$::postme" method="post"
            style="display:none"><input type="hidden" name="p" />
            <input type="hidden" name="a" value="edt" /></form>},
        $::config{body_header}||'' ,
    );

    %::menubar = (
        '100_FrontPage' => [
            &anchor($::config{FrontPage} , undef  ) ,
        ],
        '600_Index' => [
            &anchor('Index',{a=>'index'}) ,
            &anchor('Recent',{a=>'recent'}) ,
        ],
    );
    if( !&is('lonely') || &is_signed() ){
        $::menubar{'200_New'} = [
            qq|<a href="$::me?a=new" onClick="JavaScript:if(document.newpage.p.value=prompt('Create a new page')){document.newpage.submit()};return false;">New</a>| ,
        ];
    }
    @::menubar = ();
    if( &is_signed() ){
        $::menubar{'900_Sign'} = [
            &anchor('SignOut',{a=>'signout'},{ref=>'nofollow'}) ,
            &anchor('ChangeSign',{a=>'passwd'},{ref=>'nofollow'}) ,
        ];
        $::menubar{'500_Tools'} = [
            &anchor('Tools',{a=>'tools'},{ref=>'nofollow'})
        ];
    }else{
        my $p={a=>'signin'};
        if( ($ENV{REQUEST_METHOD}||'') eq 'GET' ){
            while( my ($key,$val)=each %::form ){
                $p->{$key} ||= $val ;
            }
        }
        $::menubar{'900_SignIn'} = &anchor('SignIn',$p,{ref=>'nofollow'});
    }

    ### menubar ###
    if( $::form{p} || !exists $::form{a} ){
        my $title=$::form{p} || $::config{FrontPage};
        if( !&is_frozen() || &is_signed() ){
            unshift( @{$::menubar{'300_Edit'}} ,
                &anchor('Edit',{ a=>'edt', p=>$title},{rel=>'nofollow'})
            );
            if( &is_signed() ){
                push( @{$::menubar{'300_Edit'}} ,
                    &anchor('Rollback',{ a=>'rollback', p=>$title },
                                {rel=>'nofollow'}) ,
                    &anchor('Rename' , { a=>'rename' , p=>$title },
                                {rel=>'nofollow'}) ,
                );
            }
        }
    }
    @::copyright = (
        qq(Generated by <a href="http://wifky.sourceforge.jp">wifky</a> $::version with Perl $])
    );

    %::preferences = (
        '*General Options*' => [
            { desc=>'Debug mode' , name=>'debugmode' , type=>'checkbox' } ,
            { desc=>'Archive mode' , name=>'archivemode' , type=>'checkbox' } ,
            { desc=>'Convert CRLF to <br>' ,
              name=>'autocrlf' , type=>'checkbox' } ,
            { desc=>'The sitename', name=>'sitename', size=>40 },
            { desc=>'Enable link to file://...', name=>'locallink' ,
              type=>'checkbox' },
            { desc=>'Forbid any one but administrator creating a new page.' ,
              name=>'lonely' , type=>'checkbox' },
            { desc=>'Target value for external link.',name=>'target'},
            { desc=>'Pagename(s) for CSS (1-line for 1-page)' ,
              name=>'CSS' , type=>'textarea' , rows=>2 },
            { desc=>'Pagename for FrontPage'  , name=>'FrontPage' , size=>40 },
            { desc=>'HTML-Code after <body> (for banner)' ,
              name=>'body_header' , type=>'textarea' , rows=>2 },
            { desc=>'Section mark', name=>'sectionmark', size=>3 } ,
            { desc=>'Subsection mark' , name=>'subsectionmark' , size=>3 } ,
            { desc=>'Subsubsection mark' , name=>'subsubsectionmark' , size=>3 }
        ],
    );
    %::inline_syntax_plugin = (
        '100_innerlink1' => \&preprocess_innerlink1 ,
        '200_innerlink2' => \&preprocess_innerlink2 ,
        '300_outerlink1' => \&preprocess_outerlink1  ,
        '400_outerlink2' => \&preprocess_outerlink2 ,
        '500_attachment' => \&preprocess_attachment  ,
        '600_htmltag'    => \&preprecess_htmltag ,
        '700_decoration' => \&preprocess_decorations ,
        '800_plugin'     => \&preprocess_plugin ,
        '900_rawurl'     => \&preprocess_rawurl ,
    );
    %::block_syntax_plugin = (
        '100_list'       => \&block_listing   ,
        '200_definition' => \&block_definition ,
        '300_midashi1'   => \&block_midashi1  ,
        '400_midashi2'   => \&block_midashi2 ,
        '500_centering'  => \&block_centering ,
        '600_quoting'    => \&block_quoting ,
        '700_table'      => \&block_table ,
        '800_htmltag'    => \&block_htmltag ,
        '900_seperator'  => \&block_separator ,
        '990_normal'     => \&block_normal ,
    );
    %::call_syntax_plugin = (
        '100_verbatim'       => \&call_verbatim ,
        '200_blockquote'     => \&call_blockquote ,
        '500_block_syntax'   => \&call_block ,
        '800_close_sections' => \&call_close_sections ,
        '900_footer'         => \&call_footnote ,
    );
    %::final_plugin = (
        '900_verbatim' => \&unverb ,
    );

    %::form_list = (
        '000_mode'           => \&form_mode ,
        '100_textarea'       => \&form_textarea ,
        '200_preview_botton' => \&form_preview_button ,
        '300_signarea'       => \&form_signarea ,
        '400_submit'         => \&form_commit_button ,
        '500_attachemnt'     => \&form_attachment ,
    );

    @::outline = ();

    $::user_template ||= '
        <div class="main">
            <div class="header">
                &{header}
            </div><!-- header -->
            <div class="autopagerize_page_element">
                &{main}
                <div class="terminator">
                    %{Footer}
                </div>
            </div>
            <div class="autopagerize_insert_before"></div>
            <div class="copyright footer">
                &{copyright}
            </div><!-- copyright -->
        </div><!-- main -->
        <div class="sidebar">
        %{Sidebar}
        </div><!-- sidebar -->
        &{message}';

    $::system_template ||= '
        <div class="max">
            <div class="Header">
                &{menubar}
                <h1>&{Title}</h1>
            </div><!-- Header -->
            &{main}
            <div class="copyright footer">
                &{copyright}
            </div><!-- copyright -->
        </div><!-- max -->
        &{message}';

    %::default_contents = (
        &title2fname('CSS') => <<'HERE' ,
p.centering,big{ font-size:200% }

h2{background-color:#CCF}

h3{border-width:0px 1px 1px 0px;border-style:solid}

h4{border-width:0 0 0 3mm;border-style:solid;border-color:#BBF;padding-left:1mm}

dt,span.commentator{font-weight:bold;padding:1mm}

span.comment_date{font-style:italic}

div.sidebar{ float:right; width:25% ; word-break: break-all;font-size:90%}

div.main{ float:left; width:70% }

a{ text-decoration:none }

a:hover{ text-decoration:underline }

blockquote{ background-color:#DDF }

table.block{ margin-left:1cm ; border-collapse: collapse;}

table.block th,table.block td{ border:solid 1px gray;padding:1pt}

pre{
 background-color:#DDF;
 margin-left: 1cm;
 white-space: -moz-pre-wrap; /* Mozilla */
 white-space: -o-pre-wrap; /* Opera 7 */
 white-space: pre-wrap; /* CSS3 */
 word-wrap: break-word; /* IE 5.5+ */
}

@media print{
 div.sidebar,div.footer,div.adminmenu{ display:none }
 div.main{ width:100% }
}

HERE
    &title2fname("Header") => <<HERE ,
((menubar))

!!!! ((sitename))
HERE
    );
}

sub browser_cache_off{
    push( @::http_header,"Pragma: no-cache\r\nCache-Control: no-cache\r\nExpires: Thu, 01 Dec 1994 16:00:00 GMT" );
}

sub read_multimedia{
    my ($query_string , $cutter ) = @_;

    my @blocks = split("\r\n$cutter","\r\n$query_string");
    foreach my $block (@blocks){
        $block =~ s/\A\r?\n//;
        my ($header,$body) = split(/\r?\n\r?\n/,$block,2);
        next unless defined($header) &&
            $header =~ /^Content-Disposition:\s+form-data;\s+name=\"(\w+)\"/i;

        my $name = $1;
        if( $header =~ /filename="([^\"]+)"/ ){
            &set_form( "$name.filename" , (split(/[\/\\]/,$1))[-1] );
        }
        &set_form( $name , $body );
    }
}

sub read_simpleform{
    foreach my $p ( split(/[&;]/, $_[0]) ){
        my ($name, $value) = split(/=/, $p,2);
        defined($value) or $value = '' ;
        $value =~ s/\+/ /g;
        $value =~ s/%([0-9a-fA-F][0-9a-fA-F])/pack('C', hex($1))/eg;
        &set_form( $name , $value );
    }
}

sub set_form{
    my ($key,$val)=@_;
    if( $key =~ /_y$/ ){
        ($key,$val) = ($` . '_t' , &deyen($val));
    }
    push(@{$::forms{$key}} , $::form{$key} = $val );
}

sub read_form{
    foreach(split(/[,;]\s*/,$ENV{'HTTP_COOKIE'}||'') ){
        $::cookie{$`}=$' if /=/;
    }
    if( exists $ENV{REQUEST_METHOD} && $ENV{REQUEST_METHOD} eq 'POST' ){
        $ENV{CONTENT_LENGTH} > 10*1024*1024 and die('Too large form data');
        my $query_string;
        read(STDIN, $query_string, $ENV{CONTENT_LENGTH});
        if( $query_string =~ /\A(--.*?)\r?\n/ ){
            &read_multimedia( $query_string , $1 );
        }else{
            &read_simpleform( $query_string );
        }
    }
    &read_simpleform( $ENV{QUERY_STRING} ) if exists $ENV{QUERY_STRING};
}

sub puts{
    $::print .= "$_\r\n" for(@_);
}

# puts with auto escaping arguments but format-string.
sub putenc{
    my $fmt=shift;
    $::print .= sprintf("$fmt\r\n",map(&enc($_),@_));
}

sub flush{
    $::final_plugin{$_}->(\$::print) for(sort keys %::final_plugin);
    print $::print;
}

sub errmsg{
    '<h1>Error !</h1><pre>'
    . &enc( $_[0] =~ /^\!([^\!]+)\!/ ? $1 : $_[0] )
    . '</pre>';
}

sub enc{
    my $s=shift;
    defined($s) or return '';
    $s =~ s/&/\&amp;/g;
    $s =~ s/</\&lt;/g;
    $s =~ s/>/\&gt;/g;
    $s =~ s/"/\&quot;/g;
    $s =~ s/'/\&#39;/g;
    $s =~ tr/\r\a\b//d;
    $s;
}

sub denc{
    my $s = shift;
    defined($s) or return '';
    $s =~ s/\&#39;/'/g;
    $s =~ s/\&lt;/</g;
    $s =~ s/\&gt;/>/g;
    $s =~ s/\&quot;/\"/g;
    $s =~ s/\&amp;/\&/g;
    $s;
}

sub yen{ # to save crlf-code into hidden.
    my $s = shift;
    $s =~ s/\^/\^y/g;
    $s =~ s/\r/\^r/g;
    $s =~ s/\n/\^n/g;
    $s =~ s/\t/\^t/g;
    $s ;
}

sub deyen{
    my $s = shift;
    $s =~ s/\^t/\t/g;
    $s =~ s/\^n/\n/g;
    $s =~ s/\^r/\r/g;
    $s =~ s/\^y/\^/g;
    $s ;
}

sub mtimeraw{
    $::mtime_cache{$_[0]} ||= (-f $_[0] ? ( stat(_) )[9] : 0);
}

sub mtime{
    &ymdhms( &mtimeraw(@_) );
}

sub ymdhms{
    my $tm=$_[0] or return '0000/00/00 00:00:00';
    my @tm=localtime( $tm );
    sprintf('%04d/%02d/%02d %02d:%02d:%02d'
        , 1900+$tm[5],1+$tm[4],@tm[3,2,1,0])
}

sub cacheoff{
    undef %::mtime_cache;
    undef @::contents;
    undef %::contents;
}
sub title2mtime{
    &mtime( &title2fname(@_) );
}
sub fname2title{
    pack('h*',$_[0]);
}
sub title2fname{
    my $fn=join('__',map(unpack('h*',$_),@_) );
    if( $fn =~ /^(\w+)$/ ){
        $1;
    }else{
        die("$fn: invalid filename");
    }
}
sub percent{
    my $s = shift;
    $s =~ s/([^\w\'\.\-\*\_ ])/sprintf('%%%02X',ord($1))/eg;
    $s =~ s/ /+/g;
    $s;
}

sub myurl{
    my ($cgiprm,$sharp)=@_; $sharp ||='' ;
    ( $cgiprm && %{$cgiprm}
    ? "$::me?".join(';',map($_.'='.&percent($cgiprm->{$_}),keys %{$cgiprm}))
    : $::me ) . $sharp;
}

sub anchor{
    my ($text,$cgiprm,$attr,$sharp)=@_;
    $attr ||= {}; $attr->{href}= &myurl($cgiprm,$sharp);
    &verb('<a '.join(' ',map("$_=\"".$attr->{$_}.'"',keys %{$attr})).'>')
        . $text . '</a>';
}

sub img{
    my ($text,$cgiprm,$attr)=@_;
    $attr ||= {}; $attr->{src}=&myurl($cgiprm,''); $attr->{alt}=$text;
    '<img '.&verb(join(' ',map("$_=\"".$attr->{$_}.'"',keys %{$attr}))).'>';
}

sub title2url{ &myurl( { p=>$_[0] } ); }
sub attach2url{ &myurl( { p=>$_[0] , f=>$_[1]} );}
sub is{ $::config{$_[0]} && $::config{$_[0]} ne 'NG' ; }

sub form_mode{
    if( $::config{archivemode} ){
        &puts('<div class="archivemode">archive mode</div>');
    }else{
        &puts('<div class="noarchivemode">no archive mode</div>');
    }
}
sub form_textarea{
    &putenc('<textarea cols="80" rows="20" name="text_t">%s</textarea><br>'
            , ${$_[0]} );
}
sub form_preview_button{
    &puts('<input type="submit" name="a" value="Preview">');
}
sub form_signarea{
    &is_signed() or &is_frozen() or return;

    &puts('<input type="hidden" name="admin" value="admin">');

    &puts('<input type="checkbox" name="to_freeze" value="1"');
    &puts('checked') if &is_frozen();
    &puts(' >freeze');

    my $fname=&title2fname( $::form{p} );
    if( &mtimeraw($fname) ){
        &puts('<input type="checkbox" name="sage" value="1">sage');
    }
}
sub form_commit_button{
    &puts('<input type="submit" name="a" value="Commit">');
}

sub form_attachment{
    ### &begin_day('Attachment');
    &puts('<h3>Attachment</h3>');
    &puts('<p>New:<input type="file" name="newattachment_b" size="48">');
    &puts('<input type="submit" name="a" value="Upload"></p>');
    my @attachments=&list_attachment( $::form{p} ) or return;
    &puts('<p>');
    foreach my $attach (sort @attachments){
        my $fn = &title2fname($::form{p}, $attach);

        &putenc('<input type="checkbox" name="f" value="%s"' , $attach );
        if( !&is_signed() && ! &w_ok($fn) ){
            &puts(' disabled');
        }
        &putenc('><input type="text" name="dummy" readonly value="&lt;&lt;{%s}"
                size="%d" style="font-family:monospace"
                onClick="this.select();">', $attach, length($attach)+4 );
        &puts('('.&anchor('download',{ a=>'cat' , p=>$::form{p} , f=>$attach } ).':' );
        &putenc('%d bytes, at %s', (stat $fn)[7],&mtime($fn));
        &puts('<strong>frozen</strong>') unless &w_ok();
        &puts(')<br>');
    }
    &puts('</p>');
    &puts('<input type="submit" name="a" value="Freeze/Fresh">') if &is_signed();
    &puts('<input type="submit" name="a" value="Delete" onClick="JavaScript:return window.confirm(\'Delete Attachments. Sure?\')">');
    ### &end_day();
}

sub print_form{
    my ($title,$newsrc,$orgsrc) = @_;

    &putenc('<div class="update"><form name="editform" action="%s"
          enctype="multipart/form-data" method="post"
          accept-charset="%s" ><input type="hidden" name="orgsrc_y" value="%s"
        ><input type="hidden" name="p" value="%s"><br>'
        , $::postme , $::charset , &yen($$orgsrc) , $title );
    $::form_list{$_}->($newsrc) for(sort keys %::form_list );
    &puts('</form></div>');
}

sub flush_header{
    print join("\r\n",@::http_header);
    print qq(\r\n\r\n<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">);
    print qq(\r\n<html lang="ja"><head>\r\n);
    print join("\r\n",@::html_header),"\r\n";
}

sub print_header{
    $::final_plugin{'000_header'} = \&flush_header;
    my %arg=@_;
    my $label = $::config{sitename};
    $label .= ' - '.$::form{p} if exists $::form{p};
    $label .= '('.$arg{title}.')' if exists $arg{title};
    push(@::html_header,"<title>$label</title>");

    &puts('<style type="text/css"><!--
div.menubar{
    height:1em;
}
div.menubar div{
    position:absolute;
    width:100%;
    z-index:100;
    font-size:14px;
}
ul.mainmenu{
    margin:0px;
    padding:0px;
    width:100%;
    position:relative;
    list-style:none;
    text-align:center;
}
ul.mainmenu li.menuoff{
    position:relative;
    float:left;
    height:1em;
    overflow:hidden;
    padding-left:2pt;
}
ul.mainmenu li.menuon{
    float:left;
    overflow:hidden;
    padding-left:2pt;
}
ul.mainmenu>li.menuon{
    overflow:visible;
}
ul.submenu{
    margin:0px;
    padding:0px;
    position:relative;
    list-style:none;

    background-color:white;
}
');
    foreach my $p (split(/\s*\n\s*/,$::config{CSS}) ){
        if( my $css =&read_text($p) ){
            $css =~ s/\<\<\{([^\}]+)\}/&myurl( { p=>$p , f=>$1 } )/ge;
            $css =~ s/[<>&]//g;
            $css =~ s|/\*.*?\*/||gs;
            &puts( $css );
        }
    }
    &puts('--></style></head>');
    &puts( &is_frozen() ? '<body class="frozen">' : '<body>' );
    &puts( @::body_header );
    if( $arg{userheader} ){
        if( $arg{userheader} eq 'template' ){
            $::flag{userheader} = 'template';
        }else{
            &putenc('<div class="%s">' , $arg{divclass}||'main' );
            &print_page( title=>'Header' , class=>'header' );
            $::flag{userheader} = 1;
        }
    }else{
        &putenc('<div class="%s">' , $arg{divclass}||'max' );
        &print_page( title =>'Header' ,
                     source=>\$::default_contents{ &title2fname('Header')} );
    }
}

sub print_footer{ ### deprecate ###
    if( $::flag{userheader} ){
        return if $::flag{userheader} eq 'template';
        &puts('<div class="copyright footer">',@::copyright,'</div>') if @::copyright;
        &puts('</div><!-- main --><div class="sidebar">');
        &print_page( title=>'Sidebar' );
    }
    &puts('</div>');
    &puts( $messages ) if $::config{debugmode} && $messages;
    &puts('</body></html>');
}

sub print_sidebar_and_footer{ ### deprecate ###
    @::copyright=();
    &print_footer();
}
sub print_copyright{} ### deprecate ###

sub is_frozen{
    if( -r &title2fname(  $#_>=0            ? $_[0]
                        : exists $::form{p} ? $::form{p}
                        : $::config{FrontPage}))
    {
        ! &w_ok();
    }else{
        &is('lonely');
    }
}

sub auth_check{ # If password is right, return true.
    !$::config{crypt} ||
    grep(crypt($_,$::config{crypt}) eq $::config{crypt},@{$::forms{password}})>0;
}

sub ninsho{ # If password is wrong, then die.
    &auth_check() or die('!Administrator\'s Sign is wrong!');
}

sub print_signarea{
    &puts('Sign: <input type="password" name="password">');
}

sub check_frozen{
    if( !&is_signed() && &is_frozen() ){
        die( '!This page is frozen.!');
    }
}
sub check_conflict{
    my $current_source = &read_text($::form{p});
    my $before_source  = $::form{orgsrc_t};
    if( $current_source ne $before_source ){
        die( "!Someone else modified this page after you began to edit."  );
    }
}

sub read_text{ # for text
    &read_file(&title2fname(@_));
}

sub read_object{ # for binary
    &read_file(&title2fname(@_));
}

sub read_textfile{ # for text
    &read_file;
}

sub read_file{
    open(FP,$_[0]) or return $::default_contents{ $_[0] } || '';
    local $/;
    my $object = <FP>;
    close(FP);
    defined($object) ? $object : $::default_contents{ $_[0] } || '';
}

# write object with OBJECT-NAME(S) , not filename.
sub write_object{
    my $body  = pop(@_);
    my $fname = &title2fname(@_);
    &write_file($fname,$body);
}

sub write_file{
    my ($fname,$body) = @_;

    if( length( ref($body) ? $$body : $body ) <= 0 ){
        unlink($fname) or rmdir($fname);
        &cacheoff;
        0;
    }else{
        open(FP,">$fname") or die("can't write the file $fname.");
            binmode(FP);
            print FP ref($body) ? ${$body} : $body;
        close(FP);
        &cacheoff;
        1;
    }
}

sub action_new{
    &print_template(
        template=>$::system_template ,
        Title => 'Create Page' ,
        main => sub {
            &begin_day();
            &putenc(qq(<form action="%s" method="post" accept-charset="%s">
                <p><input type="text" name="p" size="40">
                <input type="hidden" name="a" value="edt">
                <input type="submit" value="Create"></p></form>)
                , $::postme , $::charset );
            &end_day();
        },
    );
}

sub load_config{
    for(split(/\n/,&read_textfile('index.cgi'))){
        $::config{$1}=&deyen($2) if /^\#?([^\#\!\t ]+)\t(.*)$/;
    }
}

sub local_cookie{
    my $id;
    if( exists $ENV{LOCAL_COOKIE_FILE} && open(FP,'<'.$ENV{LOCAL_COOKIE_FILE}) ){
        $id=<FP>;
        close(FP);
    }
    $id;
}

sub is_signed{
    return $::signed if defined $::signed;

    my $remote_addr=$ENV{REMOTE_ADDR}||0;
    my $id=$::cookie{$::session_cookie} || &local_cookie() || rand();

    # time(TAB)ip(TAB)key
    for( split(/\n/,&read_textfile('session.cgi') ) ){
        $::ip{$2}=[$3,$1] if /^\#(\d+)\t([^\t]+)\t(.*)$/ && $1>time-24*60*60;
    }

    if( ($::form{signing} && &auth_check() ) ||
        ($::ip{$remote_addr} && $::ip{$remote_addr}->[0] eq $id ) )
    {
        push( @::http_header , "Set-Cookie: $::session_cookie=$id" );
        $::ip{$remote_addr} = [ $id , time ];
        &save_session();
        $::signed=1;
    }else{
        $::signed=0;
    }
}

sub save_session{
    &lockdo( sub{
        &write_file( 'session.cgi' ,
            join("\n",map(sprintf("#%s\t%s\t%s",$::ip{$_}->[1],$_,$::ip{$_}->[0]),
                 keys %::ip ))
        ); } , 'session.cgi'
    );
}

sub action_signin{
    &print_template(
        template => $::system_template ,
        Title=> 'Signin form',
        main=> sub{
            &begin_day();
            &putenc(qq(<form action="%s" method="POST" accept-charset="%s">
                <p>Sign: <input type="password" name="password">
                <input type="submit" name="signing" value="Enter">)
                , $::postme , $::charset , $ENV{REQUEST_METHOD} );

            while( my ($key,$val)=each %::form ){
                if( $key =~ /_t$/ ){
                    &putenc('<input type="hidden" name="%s_y" value="%s" />' ,
                                $` , &yen($val) );
                }elsif( ($key ne 'a' || $val ne 'signin') && $key !~ /_b$/ ){
                    &putenc('<input type="hidden" name="%s" value="%s" />', $key , $val );
                }
            }
            &puts('</p></form>');
            &end_day();
        }
    );
}

sub action_signout{
    if( &is_signed() ){
        delete $::ip{$ENV{REMOTE_ADDR}||0};
        &save_session();
    }
    &transfer_url($::me);
}

sub save_config{
    my @settings;
    while( my ($key,$val)=each %::config ){
        push( @settings , '#'.$key."\t".&yen($val) ) if $val;
    }
    &lockdo( sub{ &write_file( 'index.cgi' , join("\n", @settings) ) } );
}

sub action_commit{
    eval{
        &check_frozen();
        &check_conflict();
        &do_submit();
    };
    &do_preview( $@ ) if $@;
}

sub archive{
    my @tm=localtime;
    my $source=&title2fname($::form{p});
    my $backno=&title2fname($::form{p},
        sprintf('~%02d%02d%02d_%02d%02d%02d.txt',$tm[5]%100,1+$tm[4],@tm[3,2,1,0] )
    );
    rename( $source , $backno );
    chmod( 0444 , $backno );
}

sub action_preview{
    eval{
        &check_conflict;
    };
    if( $@ ){
        &do_preview( $@ );
    }else{
        &do_preview();
    }
}

sub action_rollback{
    goto &action_signin if &is_frozen() && !&is_signed();

    if( $::form{b} && $::form{b} eq 'Rollback' ){
        my $title=$::form{p};
        my $fn=&title2fname($title);
        my $frozen=&is_frozen();
        chmod(0644,$fn) if $frozen;
        &archive() if $::config{archivemode};
        &lockdo( sub{ &write_file( $fn , \&read_text($title,$::form{f})) } , $title );
        chmod(0444,$fn) if $frozen;
        &transfer_page();
    }elsif( $::form{b} && $::form{b} eq 'Preview' ){
        my $title = $::form{p};
        my $attach = $::form{f};
        &print_template(
            template => $::system_template ,
            main=>sub{
                &begin_day("Rollback Preview: $title");
                &print_page(
                    title=>$title ,
                    source=>\&read_text($title,$attach) ,
                    index=>1,
                    main=>1
                );
                &putenc('<form action="%s" method="post">',$::postme);
                &puts('<input type="hidden" name="a" value="rollback"> ');
                &puts('<input type="submit" name="b" value="Rollback"> ');
                &puts('<input type="submit" name="b" value="Cancel"> ');
                &putenc('<input type="hidden" name="p" value="%s">',$title);
                &putenc('<input type="hidden" name="f" value="%s">',$attach);
                &end_day();
            }
        );
    }else{ ### menu ###
        my $title = $::form{p};
        return unless &object_exists($title) && &is_signed();

        my @attachment=&list_attachment($title);

        &print_template(
            template => $::system_template ,
            main => sub{
                my @archive=grep(/^\~\d{6}_\d{6}\.txt/ ,@attachment);
                if( @archive ){
                    &begin_day('Rollback');
                    &putenc('<form action="%s" method="post"><select name="f">', $::postme);
                    foreach my $f(reverse sort @archive){
                        &putenc('<option value="%s">%s/%s/%s %s:%s:%s</option>',
                                $f,
                                substr($f,1,2), substr($f,3,2),  substr($f, 5,2),
                                substr($f,8,2), substr($f,10,2), substr($f,12,2),
                        );
                    }
                    &puts('</select>');
                    &putenc('<input type="hidden" name="p" value="%s">',$title);
                    &puts('<input type="hidden" name="a" value="rollback" >');
                    &puts('<input type="submit" name="b" value="Preview">');
                    &puts('</form>');
                    &end_day()
                }
            }
        );
    }
}

sub action_passwd{
    goto &action_signin unless &is_signed();

    if( $::form{b} ){
        unless( auth_check() ){
            &transfer(url=>&myurl({a=>'passwd'}),
                      title=>'Failure' , message=>'Old sign is wrong.');
        }
        my ($p1,$p2) = ( $::form{p1} , $::form{p2} );
        if( $p1 ne $p2 ){
            &transfer(url=>&myurl({a=>'passwd'}),
                      title=>'Failure' , message=>'New signs differs');
        }
        my @salts=('0'..'9','A'..'Z','a'..'z',".","/");
        $::config{crypt} = crypt($p1,$salts[ int(rand(64)) ].$salts[ int(rand(65)) ]);
        &save_config;
        &transfer(url=>$::me,title=>'Succeeded',message=>'Succeeded to change sign');
    }else{
        &print_template(
            template => $::system_template ,
            Title => 'Change Sign' ,
            main => sub{
                &putenc('<form action="%s" method="post">
                    <ul>
                     <li>Old Sign:<input name="password" type="password" size="40"></li>
                     <li>New Sign(1):<input name="p1" type="password" size="40"></li>
                     <li>New Sign(2):<input name="p2" type="password" size="40"></li>
                    </ul>
                    <p><input name="a" type="hidden"  value="passwd">
                    <input type="submit" name="b" value="Submit"></p></form>',$::postme);
            }
        );
    }
}

sub action_tools{
    goto &action_signin unless &is_signed();

    &browser_cache_off();
    push( @::html_header , <<HEADER );
<script language="JavaScript">
<!--
    function hide(id){ document.getElementById(id).style.display = 'none'; }
    function show(id){ document.getElementById(id).style.display = '';     }
    var lastid="*General Options*";
// -->
</script>
HEADER

    &print_template(
        template=>$::system_template ,
        Title => 'Tools' ,
        main => sub {
            ### Section Select ###
            &puts('<form action="#"><input type="hidden" name="a" value="tools">');
            &putenc('<select onChange="if( lastid ){ hide(lastid); };show(this.options[this.selectedIndex].value);lastid=this.options[this.selectedIndex].value;return false;">' );

            foreach my $section ( sort keys %::preferences ){
                &putenc('<option value="%s">%s</option>',$section,$section);
            }
            &puts('</select></form>');

            while( my $section=each %::preferences ){
                if( $section eq '*General Options*' ){
                    &putenc('<div id="%s" class="section">', $section );
                }else{
                    &putenc('<div id="%s" style="display:none" class="section">',
                                $section );
                }
                &begin_day($section);
                &putenc('<form action="%s" method="post" accept-charset="%s">',
                            $::postme,$::charset);
                &putenc('<input type="hidden" name="section" value="%s">',$section);

                &puts('<ul>');
                foreach my $i ( @{$::preferences{$section}} ){
                    &puts('<li>');
                    $i->{type} ||= 'text';
                    if( $i->{type} eq 'checkbox' ){
                        &putenc('<input type="checkbox" name="config__%s" value="1"%s> %s<br>'
                            , $i->{name}
                            , ( &is($i->{name}) ? ' checked' : '' )
                            , $i->{desc}
                        );
                    }elsif( $i->{type} eq 'password' ){
                        &putenc('%s <input type="password" name="config__%s">
                                (retype)<input type="password" name="verify__%s"><br>'
                            , $i->{desc} , $i->{name} , $i->{name}
                        );
                    }elsif( $i->{type} eq 'textarea' ){
                        &putenc(
                            '%s<br><textarea name="config__%s" cols="%s" rows="%s">%s</textarea><br>'
                            , $i->{desc} , $i->{name}
                            , ($i->{cols} || 40 )
                            , ($i->{rows} ||  4 )
                            , exists $::config{$i->{name}} ? $::config{$i->{name}} : ''
                        );
                    }elsif( $i->{type} eq 'radio' ){
                        &putenc('%s<br>',$i->{desc});
                        foreach my $p (@{$i->{option}}){
                            &putenc('<input type="radio" name="config__%s" value="%s"%s>%s<br>'
                                , $i->{name}
                                , $p->[0]
                                , ( defined($::config{$i->{name}}) &&
                                    $::config{$i->{name}} eq $p->[0]
                                  ? ' checked' : '' )
                                , $p->[1] );
                        }
                    }elsif( $i->{type} eq 'a' ){
                        &putenc('<a href="%s">%s</a><br>',$i->{href},$i->{desc} );
                    }elsif( $i->{type} eq 'rem' ){
                        &putenc('%s<br>',$i->{desc} );
                    }elsif( $i->{type} eq 'function' ){
                        $i->{display}->('config__'.$i->{name},$::config{$i->{name}});
                    }else{ # text
                        &putenc(
                            '%s <input type="text" name="config__%s" value="%s" size="%s"><br>'
                            , $i->{desc} , $i->{name}
                            , exists $::config{$i->{name}} ? $::config{$i->{name}} : ''
                            , $i->{size} || 10
                        );
                    }
                    &puts('</li>');
                }
                &puts('</ul><input type="hidden" name="a" value="preferences">',
                      '<input type="submit" value="Submit"></form>' );
                &end_day();
                &puts('</div>');
            }
        }
    );
}

sub action_preferences{
    goto &action_signin unless &is_signed();

    foreach my $i ( @{$::preferences{$::form{section}}} ){
        next unless exists $i->{name};
        my $type = $i->{type} || 'text';
        my $newval= exists $::form{'config__'.$i->{name}}
                  ? $::form{'config__'.$i->{name}} : '';
        if( $type eq 'checkbox' ){
            $::config{ $i->{name} } = ($newval ? 1 : 0);
        }elsif( $type eq 'password' ){
            if( length($newval) > 0 ){
                if( $newval ne $::form{'verify__'.$i->{name}} ){
                    die('invalud value for ' . $i->{name} );
                }
                $::config{ $i->{name} } = $newval;
            }
        }else{
            $::config{ $i->{name} } = $newval;
        }
    }
    &save_config;
    &transfer_url($::me);
}

sub action_rename{
    goto &action_signin unless &is_signed();
    my $title    = $::form{p};

    if( $::form{b} && $::form{b} eq 'body' ){
        my $newtitle = $::form{newtitle};
        my $fname    = &title2fname($title);
        my $newfname = &title2fname($newtitle);
        die("!The new page name '$newtitle' is already used.!") if -f $newfname;

        my @list = map {
            my $older="${fname}__$_" ;
            my $newer="${newfname}__$_";
            die("!The new page name '$newtitle' is already used.!") if -f $newer;
            [ $older , $newer ];
        } @{$::contents{$fname}};

        rename( $fname , $newfname );
        rename( $_->[0] , $_->[1] ) foreach @list;
        &transfer_page($newtitle);
    }elsif( $::form{b} && $::form{b} eq 'attachment' ){
        my $older=&title2fname($title,$::form{f1});
        my $newer=&title2fname($title,$::form{f2});
        die("!The new attachment name is null.!") unless $::form{f2};
        die("!The new attachment name '$::form{f2}' is already used.!") if -f $newer;

        rename( $older , $newer );
        &transfer_page($title);
    }else{ # menu
        my @attachment=&list_attachment($title);
        return unless &object_exists($title) && &is_signed();

        &print_template(
            template => $::system_template ,
            Title => 'Rename' ,
            main => sub{
                &begin_day('Rename');
                &putenc('<h3>Page</h3><p><form action="%s" method="post">
                    <input type="hidden"  name="a" value="rename">
                    <input type="hidden"  name="b" value="body">
                    <input type="hidden"  name="p" value="%s">
                    Title: <input type="text" name="newtitle" value="%s" size="80">'
                    , $::postme , $title , $title );
                &puts('<br><input type="submit" name="ren" value="Submit"></form></p>');

                if( @attachment ){
                    &putenc('<h3>Attachment</h3><p>
                        <form action="%s" method="post" name="rena">
                        <input type="hidden"  name="a" value="rename">
                        <input type="hidden"  name="b" value="attachment">
                        <input type="hidden"  name="p" value="%s">'
                        , $::postme , $title);
                    &puts('<select name="f1" onChange="document.rena.f2.value=this.options[this.selectedIndex].value;return false">');
                    &puts('<option value="" selected></option>');
                    foreach my $f (@attachment){
                        &putenc('<option value="%s">%s</option>', $f, $f);
                    }
                    &puts('</select><input type="text" name="f2" value="" size="30" />');
                    &puts('<br><input type="submit" name="rena" value="Submit"></form></p>');
                }
                &end_day();
            }
        );
    }
}

sub action_seek{
    my $keyword=$::form{keyword};
    my $keyword_=&enc( $keyword );

    &print_template(
        Title => qq(Seek: "$keyword_") ,
        main => sub {
            &begin_day( qq(Seek: "$keyword_") );
            &puts('<ul>');
            foreach my $fn ( &list_page() ){
                my $title  = &fname2title( $fn );
                if( index($title ,$keyword) >= 0 ){
                    &puts('<li>' . &anchor($title,{ p=>$title }) . ' (title)</li>');
                }elsif( open(FP,$fn) ){
                    while( <FP> ){
                        if( index($_,$keyword) >= 0 ){
                            &puts('<li>' . &anchor($title,{ p=>$title } ) . '</li>' );
                            last;
                        }
                    }
                    close(FP);
                }
            }
            &puts('</ul>');
            &end_day();
        },
    );
}

sub action_delete{
    goto &action_signin if &is_frozen() && !&is_signed();

    foreach my $f ( @{$::forms{f}} ){
        my $fn=&title2fname( $::form{p} , $f );
        if( &w_ok($fn) || &is_signed() ){
            unlink( $fn ) or rmdir( $fn );
        }
    }
    &cacheoff;
    &do_preview();
}

sub action_freeze_or_fresh{
    goto &action_signin unless &is_signed();

    foreach my $f ( @{$::forms{f}} ){
        my $fn=&title2fname( $::form{p} , $f );
        chmod( &w_ok($fn) ? 0444 : 0666 , $fn );
    }
    &cacheoff;
    &do_preview();
}

sub action_comment{
    my $title   = $::form{p};
    my $comid   = $::form{comid};
    my $who     = $::form{who} ;
    my $comment = $::form{comment};

    if( length($comment) > 0 ){
        utime( time , time , &title2fname($title) ) <= 0
            and die("unable to comment to unexistant page.");
        &cacheoff;
        my $fname  = &title2fname($title,"comment.$comid");
        local *FP;
        open(FP,">>$fname") or die("Can not open $fname for append");
            my @tm=localtime;
            printf FP "%04d/%02d/%02d %02d:%02d:%02d\t%s\t%s\r\n"
                , 1900+$tm[5],1+$tm[4],@tm[3,2,1,0]
                , &yen($who) , &yen($comment) ;
        close(FP);
    }
    &transfer_page;
}

sub begin_day{
    &puts('<div class="day">');
    &putenc('<h2><span class="title">%s</span></h2>',$_[0]) if @_;
    &puts('<div class="body">');
}

sub end_day{ &puts('</div></div>'); }

sub do_index{
    my ($t,$n,@param)=@_;

    &print_template(
        title => 'IndexPage' ,
        main  => sub{
            &begin_day('IndexPage');
            &puts( '<ul><li><tt>' .
                    &anchor(' Last Modified Time' , { a=>$t } ) .
                    '&nbsp' . &anchor('Page Title' , { a=>$n } ) .
                    '</tt></li>' . &ls(@param) . '</ul>' );
            &end_day();
        }
    );
}

sub action_upload{
    exists $::form{p} or die('not found pagename');
    &check_frozen;
    my $fn=&title2fname( $::form{p} , $::form{'newattachment_b.filename'} );
    if( -r $fn && ! &w_ok() ){
        &do_preview('The attachment is frozen.');
    }else{
        &write_file( $fn , \$::form{'newattachment_b'} );
        &do_preview();
    }
}

sub lockdo{
    my ($code,@title)=(@_,'LOCK');
    my $lock=&title2fname(@title);
    my $retry=0;
    while( mkdir($lock,0777)==0 ){
        sleep(1);
        if( ++$retry >= 3 ){
            die("!Disk full or file writing conflict (lockfile=$lock)!");
        }
    }
    my $rc=undef;
    eval{ $rc=$code->() };
    my $err=$@;
    rmdir $lock;
    die($err) if $err;
    $rc;
}


sub do_submit{
    my $title=$::form{p};
    my $fn=&title2fname($title);
    my $sagetime=&mtimeraw($fn);

    chmod(0644,$fn) if &is_frozen();

    $::hook_submit->(\$title , \$::form{text_t}) if $::hook_submit;
    if( $::form{text_t} ne $::form{orgsrc_t}  &&  $::config{archivemode} ){
        &archive();
    }
    if( &lockdo( sub{ &write_file( $fn , \$::form{text_t} ) },$::form{p} )){
        if( $::form{to_freeze} ){
            chmod(0444,$fn);
        }
        if( $::form{sage} ){
            utime($sagetime,$sagetime,$fn)
        }
        &transfer_page();
    }else{
        &transfer_url($::me.'?a=recent');
    }
}

sub transfer{
    my %o=@_;
    my $url= defined $o{page}   ? &myurl( { p=>$o{page} } )
           : defined $o{url}    ? $o{url}
           : $::me;

    print join("\r\n",@::http_header),"\r\n\r\n";
    printf '<html><head><title>%s</title>' ,
            $o{title} || 'Moving...' ;
    unless( $::config{debugmode} && $messages ){
        print qq|<meta http-equiv="refresh" content="1;URL=$url">\n|
    }
    print '</head><body>';
    printf "<p>%s</p>\n" , $o{message} if $o{message};
    print qq|<p><a href="$url">Wait or Click Here</a></p>\n|;
    print "<p>$messages</p>\n" if $::config{debugmode} && $messages;
    print '</body></html>';
    exit(0);
}

sub transfer_url{ &transfer( url=>shift ); }
sub transfer_page{ &transfer( page=>shift || $::form{p} ); }

sub do_preview{
    goto &action_signin if &is_frozen() && !&is_signed();

    my @param=@_;
    my $title = $::form{p};
    &print_template(
        template => $::system_template ,
        main=>sub{
            &puts(@param ? '<div class="warning">'.&errmsg($param[0]).'</div>' : '');
            &begin_day('Preview:'.$::form{p} );
            &print_page( title=>$title , source=>\$::form{text_t} , index=>1 , main=>1 );
            &end_day();
            &print_form( $title , \$::form{text_t} , \$::form{orgsrc_t} );
        },
    );
}

sub action_edit{
    goto &action_signin if &is_frozen() && !&is_signed();

    &browser_cache_off();
    my $title = $::form{p};
    my @attachment=&list_attachment($title);

    &print_template(
        template => $::system_template ,
        Title => 'Edit' ,
        main  => sub {
            &begin_day( $title );
            my $source=&read_text($title);
            &print_form( $title , \$source , \$source );
            &end_day();
        }
    );
}

sub print_template{
    my %hash=@_;
    my $template = $hash{template} || $::user_template;
    my %default=(
        header=>sub{
            &::print_page( title=>'Header' );
            $::flag{userheader} = 1;
            &puts(&plugin({},'menubar')) unless $::flag{menubar_printed};
        },
        message=>sub{
            $::config{debugmode} && $messages ? $messages : '';
        },
        copyright => sub{ join('',@::copyright); },
        menubar => sub {
            $::flag{menubar_printed} ? "" : &plugin({},'menubar');
        },
    );
    &print_header( userheader=>'template' );
    $template =~ s/([\&\%]){(.*?)}/&template_callback(\%default,\%hash,$1,$2)/ge;
    &puts( $template );
    &puts('</body></html>');
}
sub template_callback{
    my ($default,$hash,$mark,$word)=@_;
    if( $mark eq '&' ){
        my $target="<!-- unknown function $word-->";
        if( exists $default->{$word} ){
            $target = $default->{$word};
        }elsif( exists $hash->{$word} ){
            $target = $hash->{$word};
        }
        if( ref($target) ){
            local $::print="";
            my $value=$target->( $word );
            $::print || $value || '';
        }else{
            $target;
        }
    }else{
        local $::print='';
        &::print_page( title=>$word );
        $::print;
    }
}

sub action_view{
    my $title=$::form{p}=shift;
    &print_template(
        title => $title ,
        main  => sub{
            &begin_day( $title );
            unless( &print_page( title=>$title , index=>1 , main=>1 ) ){
                push(@::http_header,'Status: 404 Page not found.');
                &::puts( '<p>404 Page not found.</p>' );
            }
            &end_day();
        }
    );
}

sub action_cat{
    my $attach=$::form{f};
    my $path=&title2fname($::form{p},$attach);

    unless( open(FP,$path) ){
        push(@::http_header,'Status: 404 Attachment not found.');
        die('!404 Attachment not found!');
    }
    binmode(FP);
    binmode(STDOUT);

    my $type= $attach =~ /\.gif$/i ? 'image/gif'
            : $attach =~ /\.jpg$/i ? 'image/jpeg'
            : $attach =~ /\.png$/i ? 'image/png'
            : $attach =~ /\.pdf$/i ? 'application/pdf'
            : $attach =~ /\.txt$/i ? 'text/plain'
            : 'application/octet-stream';

    if( $ENV{HTTP_USER_AGENT} =~ /Fire/  ||
        $ENV{HTTP_USER_AGENT} =~ /Opera/ ){
        printf qq(Content-Disposition: attachment; filename*=%s''%s\r\n),
            $::charset , $attach ;
    }else{
        if( $::charset eq 'EUC-JP' ){
            $attach =~ s/([\x80-\xFF])([\x80-\xFF])/&euc2sjis($1,$2)/ge;
        }else{
            $attach = &percent($attach);
        }
        printf qq(Content-Disposition: attachment; filename=%s\r\n),$attach;
    }
    print  qq(Content-Type: $type\r\n);
    printf qq(Content-Length: %d\r\n),( stat(FP) )[7];
    printf qq(Last-Modified: %s, %02d %s %04d %s GMT\r\n) ,
                (split(' ',scalar(gmtime((stat(FP))[9]))))[0,2,1,4,3];
    print  qq(\r\n);
    print <FP>;
    close(FP);
    exit(0);
}

sub euc2sjis{
    my $c1=ord(shift) & 0x7F;
    my $c2=ord(shift) & 0x7F;
    if( $c1 & 1 ){
        $c2 += 0x1F;
    }else{
        $c2 += 0x7D;
    }
    if( $c2 >= 0x7F ){
        ++$c2;
    }
    $c1 = ($c1-0x21)/2 + 0x81;
    if( $c1 > 0x9F ){
        $c1 += 0x40;
    }
    pack("C2",$c1,$c2);
}

sub cache_update{
    unless( defined(@::contents) ){
        opendir(DIR,'.') or die('can\'t read work directory.');
        while( my $fn=readdir(DIR) ){
            push( @::contents , $fn );
            if( $fn =~ /^([0-9a-f][0-9a-f])+$/ ){
                $::contents{$&} ||= [];
            }elsif( $fn =~ /^((?:[0-9a-f][0-9a-f])+)__((?:[0-9a-f][0-9a-f])+)$/ ){
                push(@{$::contents{$1}},$2);
            }
        }
        closedir(DIR);
    }
}

sub directory{
    &cache_update() ; @::contents;
}

sub list_page{
    &cache_update() ; keys %::contents;
}

sub object_exists{
    &cache_update() ; exists $::contents{ &title2fname($_[0]) }
}

sub list_attachment{
    &cache_update();
    my $fn=&title2fname($_[0]);
    return () unless exists $::contents{$fn};
    map{ &fname2title($_) } @{$::contents{$fn}};
}

sub print_page{
    my %args=@_;
    my $title=$args{title};
    my $html =&enc( exists $args{source} ? ${$args{source}} : &read_text($title));
    return 0 unless $html;

    push(@::outline,
        { depth => -1 , text  => $title , title => $title , sharp => '' }
    );

    my %attachment;
    foreach my $attach ( &list_attachment($title) ){
        my $attach_ = &enc( $attach );
        my $url=&attach2url($title,$attach);
        $attachment{ $attach_ } = {
            # for compatible #
            name => $attach ,
            url  => $url ,
            tag  => $attach =~ /\.(png|gif|jpg|jpeg)$/i
                    ? qq(<img src="$url" alt="$attach_" class="inline">)
                    : qq(<a href="$url" title="$attach_" class="attachment">$attach_</a>) ,
        };
    }
    my %session=(
        title      => $title ,
        attachment => \%attachment ,
        'index'    => $args{'index'} ,
        main       => $args{main} ,
    );
    if( exists $args{class} ){
        &puts(qq(<div class="$args{class}">));
        &syntax_engine( \$html , \%session );
        &puts('</div>');
    }else{
        &syntax_engine( \$html , \%session );
    }
    1;
}

sub unverb_textonly{
    ${$_[0]} =~ s/\a\((\d+)\)/
          $1 > $#::later
          ? "(code '$1' not found)"
          : ref($::later[$1]) eq 'CODE' ? $&
          : $::later[$1]/ge;
}
sub strip_tag{
    my $text=shift;
    &unverb_textonly( \$text );
    $text =~ s/\r?\n/ /g;
    $text =~ s/\<[^\>]*\>//g;
    $text;
}

sub call_verbatim{
    ${$_[0]} =~
    s!^\s*\&lt;pre&gt;(.*?\n)\s*\&lt;/pre&gt;|^\s*8\&lt;(.*?\n)\s*\&gt;8|`(.)`(.*?)`\3`!
    defined($4)
    ? &verb('<tt class="pre">'.&cr2br($4).'</tt>')
    : "\n\n<pre>".&verb(defined($1) ? $1 : $2)."</pre>\n\n"
    !gesm;
}

sub call_blockquote{
    ${$_[0]} =~
    s!(?:&lt;blockquote&gt;|6&lt;)(.*?)(?:&lt;/blockquote&gt;|&gt;9)!&call_blockquote_sub($1,$_[1])!gesm;
}

sub call_blockquote_sub{
    my ($text,$request)=@_;
    local $::print='';
    &syntax_engine( $text , $request );
    qq(\n\n<blockquote class="block">).&verb($::print)."</blockquote>\n\n";
}


sub inner_link{
    my ($session,$symbol,$title,$sharp)
        = ($_[0], $_[1] , split(/(?=#[pf][0-9mt])/,$_[2]) );
    if( $title =~ /^#/ ){
        ($title,$sharp)=($session->{title},$title);
    }else{
        $title = &denc($title);
    }

    if( &object_exists($title) ){
        &anchor( $symbol , { p=>$title } , { class=>'wikipage' } , $sharp);
    }else{
        qq(<blink class="page_not_found">$symbol?</blink>);
    }
}

sub plugin_menubar{
    shift;
    $::flag{menubar_printed}=1;
    my $i=50;
    my %bar=(%::menubar , map( (sprintf('%03d_argument',++$i) => $_) , @_));
    my $out='<div class="menubar"><div><ul class="mainmenu">';
    foreach my $p (sort keys %bar){
        $out .= q|<li class="menuoff" onmouseover="this.className='menuon'" onmouseout="this.className='menuoff'">|;
        my $items=$bar{$p};
        if( ref($items) ){
            my ($first,@rest)=@{$items};
            $out .= $first;
            if( @rest ){
                $out .= '<ul class="submenu"><li>' .
                        join("</li>\n<li>",@rest)  .
                        "</li>\n</ul>\n";
            }
        }else{
            $out .= $items;
        }
        $out .= '</li>';
    }
    $out . '</ul></div></div>';
}

sub plugin_search{
    sprintf( '<div class="search_form"><form class="search" action="%s">
        <input class="search" type="text" name="keyword" size="20" value="%s">
        <input type="hidden" name="a" value="?">
        <input class="search" type="submit" value="?">
        </form></div>' ,
        $::me ,
        &enc(exists $::form{keyword} ? $::form{keyword} : '' ));
}

sub plugin_footnote{
    my $session = shift;
    my $footnotetext=$session->{argv};
    push(@{$session->{footnotes}}, $footnotetext );

    my $i=$#{$session->{footnotes}} + 1;
    my %attr=( title=>&strip_tag($footnotetext)  );
    $attr{name}="fm$i" if $session->{index};
    '<sup>' .
    &anchor("*$i", { p=> $::form{p} } , \%attr , "#ft$i" ) .
    '</sup>' ;
}

sub call_footnote{
    my (undef,$session) = @_;
    my $footnotes = $session->{footnotes};
    return unless $footnotes;

    my $i=0;
    &puts(qq(<div class="footnote">));
    foreach my $t (@{$footnotes}){
        ++$i;
        &puts('<p class="footnote">' ,
            &anchor("*$i",{ p=>$::form{p} } ,
            ($session->{index} ? { name=>"ft$i"} : undef) ,
            "#fm$i"),
            "$t</p>");
    }
    &puts('</div><!--footnote-->');
    delete $session->{footnotes};
}

sub verb{
    my $cnt=scalar(@::later);
    push( @::later , $_[0] );
    "\a($cnt)";
}

sub unverb{
    for(1..10){
        last unless ${$_[0]} =~ s/\a\((\d+)\)/
              $1 > $#::later
              ? "(code '$1' not found)"
              : ref($::later[$1]) eq 'CODE' ? $::later[$1]->()
              : $::later[$1]/ge;
    }
}


sub plugin_outline{
    &verb(
        sub{
            my $depth=-2;
            my $ss='';
            foreach my $p( @::outline ){
                next if $p->{title} eq 'Header' ||
                        $p->{title} eq 'Footer' ||
                        $p->{title} eq 'Sidebar' ;

                my $diff=$p->{depth} - $depth;
                if( $diff > 0 ){
                    $ss .= '<ul><li>' x $diff ;
                }else{
                    $diff < 0    and $ss .= "</li></ul>\n" x -$diff;
                    $depth >= 0  and $ss .= "</li>\n" ;
                    $ss .= '<li>';
                }
                $ss .= &anchor( $p->{text}, { p=>$p->{title} }, undef, $p->{sharp} );
                $depth=$p->{depth};
            }
            $ss .= '</li></ul>' x ($depth+2);
            $ss;
        }
    );
}

sub ls_core{
    my ($opt,@args) = @_;
    push(@args,'*') unless @args;

    my @list;
    foreach my $pat (@args){
        $pat =~ s/([^\*\?]+)/unpack('h*',$1)/eg;
        $pat =~ s/\?/../g;
        $pat =~ s/\*/.*/g;
        $pat = '^' . $pat . '$';
        push(@list, map{
             +{ fname  => $_ ,
                title  => &fname2title($_) ,
                mtimeraw => &mtimeraw($_) ,
                mtime  => &mtime($_)
              }
            }grep{
                  exists $opt->{a}
                ? ($_ =~ $pat )
                : ($_ =~ $pat && !/^e2/ && -f $_ )
            }
            &list_page()
        );
    }
    if( exists $opt->{t} ){
        @list = sort{ $a->{mtime} cmp $b->{mtime} } @list;
    }else{
        @list = sort{ $a->{title} cmp $b->{title} } @list;
    }
    @list = reverse @list if exists $opt->{r};
    if( defined (my $n=$opt->{number} || $opt->{countdown}) ){
        splice(@list,$n) if $n =~ /^\d+$/ && $#list >= $n;
    }
    @list;
}

sub parse_opt{
    my ($opt,$arg,@rest)=@_;
    foreach my $p (@rest){
        if( $p =~ /^-(\d+)$/ ){
            $opt->{number} = $opt->{countdown} = $1;
        }elsif( $p =~ /^-/ ){
            $opt->{$'} = 1;
        }else{
            push(@{$arg},$p);
        }
    }
}

sub ls{
    &parse_opt(\my %opt,\my @arg,@_);

    my $buf = '';
    foreach my $p ( &ls_core(\%opt,@arg) ){
        $buf .= '<li>';
        exists $opt{l} and $buf .= '<tt>'.$p->{mtime}.' </tt>';
        exists $opt{i} and $buf .= '<tt>'.(1+@{$::contents{ $p->{fname} }}).' </tt>';

        $buf .= &anchor( &enc($p->{title}) , { p=>$p->{title} } );
        $buf .= "</li>\r\n";
    }
    $buf;
}

sub plugin_comment{
    return '' unless $::form{p};

    my $session=shift;
    &parse_opt( \my %opt , \my @arg , @_ );
    my $title_= &enc($::form{p});
    my $comid = (shift(@arg) || '0');
    my $caption = @arg ? '<div class="caption">'.join(' ',@arg).'</div>' : '';

    exists $session->{"comment.$comid"} and return '';
    $session->{"comment.$comid"} = 1;

    my $buf = sprintf('<div class="comment" id="c_%s_%s">%s<div class="commentshort">',
                unpack('h*',$::form{p}) ,
                unpack('h*',$comid) ,
                $caption );
    for(split(/\r?\n/,&read_text($::form{p} , "comment.$comid"))){
        my ($dt,$who,$say) = split(/\t/,$_,3);
        my $text=&enc(&deyen($say)); $text =~ s/\n/<br>/g;
        $buf .= sprintf('<p><span class="commentator">%s</span>'.
            ' %s <span class="comment_date">(%s)</span></p>'
                , &enc(&deyen($who)), $text , &enc($dt) );
    }
    unless( exists $opt{f} ){
        my $comid_ = &enc($comid);
        $buf .= <<HTML
<div class="form">
<form action="$::postme" method="post" class="comment">
<input type="hidden" name="p" value="$title_">
<input type="hidden" name="a" value="comment">
<input type="hidden" name="comid" value="$comid_">
<div class="field name">
<input type="text" name="who" size="10" class="field">
</div><!-- div.field name -->
<div class="textarea">
<textarea name="comment" cols="60" rows="1" class="field"></textarea>
</div><!-- div.textarea -->
<div class="button">
<input type="submit" name="Comment" value="Comment">
</div><!-- div.button -->
</form>
</div><!-- div.form -->
HTML
    }
    $buf . '</div></div>';
}

sub plugin_pagename{
    if( exists $::form{a} && (
        $::form{a} eq 'index'  || $::form{a} eq 'recent' ||
        $::form{a} eq 'rindex' || $::form{a} eq 'older'   )  ){
        'IndexPage';
    }elsif( exists $::form{keyword} ){
        &enc('Seek: '.$::form{keyword});
    }else{
        &enc( exists $::form{p} ? $::form{p} : $::config{FrontPage} );
    }
}

sub plugin{
    my $session=shift;
    my ($name,$param)=(map{(my $s=$_)=~s/<br>\Z//;$s} split(/\s+/,shift,2),'');
    $session->{argv} = $param;

    $param =~ s/\x02.*?\x02/"\x05".unpack('h*',$&)."\x05"/eg;
    my @param=split(/\s+/,$param);
    foreach(@param){
        s|\x05([^\x05]*)\x05|pack('h*',$1)|ge;
        s|\x02+|"\x02"x(length($&)>>1)|ge;
    }

    ($::inline_plugin{$name} || sub{'Plugin not found.'} )
        ->($session,@param) || '';
}

sub cr2br{
    my $s=shift;
    $s =~ s/\n/\n<br>/g;
    $s =~ s/ /&nbsp;/g;
    $s;
}

sub preprocess_innerlink1{ ### >>{ ... }{ ... } ###
    my ($text,$session)=@_;
    $$text =~ s|&gt;&gt;\{([^\}]+)\}(?:\{([^\}]*)\})?|
        &inner_link($session,defined($2)?$2:$1,$1)|ge;
}

sub preprocess_innerlink2{ ### [[ ... | ... ] ###
    my ($text,$session)=@_;
    $$text =~ s!\[\[(?:([^\|\]]+)\|)?(.+?)\]\]!
        &inner_link($session,defined($1)?$1:$2,$2)!ge;
}

sub preprocess_outerlink1{ ### http://...{ ... } style ###
    ${$_[0]} =~ s!($::RXURL)\{([^\}]+)\}!
        &verb(sprintf('<a href="%s"%s>',$1,$::target)).$2.'</a>'!goe;
}

sub preprocess_outerlink2{ ### [...|http://...] style ###
    ${$_[0]} =~ s!\[([^\|]+)\|((?:\.\.?/|$::PROTOCOL://)[^\]]+)\]!
        &verb(sprintf('<a href="%s"%s>',$2,$::target)).$1.'</a>'!goe;
}

sub attach2tag{
    my ($session,$nm,$label)=@_;
    my ($p,$f)=($session->{title},&denc($nm));
    $label ||= $nm;
    $label =~ s/\r*\n/ /gs;

    if( exists $session->{attachment}->{$nm} ){
        if( $nm =~ /\.png$/i || $nm =~ /\.gif$/i  || $nm =~ /\.jpe?g$/i ){
            &img( $label ,{ p=>$p , f=>$f } , { class=>'inline' } );
        }else{
            &anchor($label ,{ p=>$p , f=>$f } , { title=>$label } )
        }
    }else{
        &verb(sub{$::ref{$nm} || qq(<blink class="attachment_not_found">$nm</blink>)});
    }
}


sub preprocess_attachment{
    ${$_[0]} =~ s|&lt;&lt;\{([^\}]+)\}(?:\{([^\}]+)\})?|&attach2tag($_[1],$1,$2)|ge;
}

sub preprecess_htmltag{
    ${$_[0]} =~ s!&lt;(/?(b|big|br|cite|code|del|dfn|em|hr|i|ins|kbd|q|s|samp|small|span|strike|strong|sup|sub|tt|u|var)\s*/?)&gt;!<$1>!gi;
}

sub preprocess_decorations{
    my $text=shift;
    $$text =~ s|^//.*$||mg;
    $$text =~ s|&#39;&#39;&#39;&#39;(.*?)&#39;&#39;&#39;&#39;|<big>$1</big>|gs;
    $$text =~ s|&#39;&#39;&#39;(.*?)&#39;&#39;&#39;|<strong>$1</strong>|gs;
    $$text =~ s|&#39;&#39;(.*?)&#39;&#39;|<em>$1</em>|gs;
    $$text =~ s|__(.*?)__|<u>$1</u>|gs;
    $$text =~ s|==(.*?)=={(.*?)}|<del>$1</del><ins>$2</ins>|gs;
    $$text =~ s|==(.*?)==|<strike>$1</strike>|gs;
    $$text =~ s|``(.*?)``|'<tt class="pre">'.&cr2br($1).'</tt>'|ges;
    $$text =~ s/\n/<br>\n/g if $::config{autocrlf} ;
}

sub preprocess_plugin{
    my ($text,$sesion) = @_;
    $$text =~ s/&quot;/\x02/g;
    $$text =~ s/\(\(/\x03/g;
    $$text =~ s/\)\)/\x04/g;
    $$text =~ s/\x03([^\x02-\x04]*?(?:\x02[^\x02]*\x02[^\x02-\x04]*?)*?)\x04/&plugin($sesion,$1)/ges;
    $$text =~ s/\x04/\)\)/g;
    $$text =~ s/\x03/\(\(/g;
    $$text =~ s/\x02/&quot;/g;
}

sub preprocess_rawurl{
    my $text=shift;
    $$text = " $$text";
    $$text =~ s/([^-\"\>\w\.!~'\(\);\/?\@&=+\$,%#])($::RXURL)/
        $1.&verb(sprintf('<a href="%s"%s>',$2,$::target)).$2.'<\/a>'/goe;
    substr($$text,0,1)='';
}

sub preprocess{
    my ($text,$session) = @_;
    foreach my $p ( sort keys %::inline_syntax_plugin ){
        $::inline_syntax_plugin{$p}->( \$text , $session );
    }
    $text;
}

sub headline{
    my ($body,$n,$id)=@_;
    &puts("<h$n" . ($id ? qq( id="$id") : '') . ">$body</h$n>" );
}

sub midashi{
    my ($depth,$text,$session)=@_;
    $text = &preprocess($text,$session);
    my $section = ($session->{section} ||= [0,0,0,0,0]) ;

    if( $depth < 0 ){
        &puts( "<h1>$text</h1>" );
    }else{
        grep( $_ && &puts('</div></div>'),@{$section}[$depth .. $#{$section}]);
        $section->[ $depth ]++;
        $_=0 for(@{$section}[$depth+1 .. $#{$section} ]);

        my $tag = join('.',@{$section}[0...$depth]);
        my $h    = $depth+ 3 ;
        my $cls  = ('sub' x $depth).'section' ;

        push( @::outline ,
                {
                  depth => $depth ,
                  text  => &strip_tag($text) ,
                  title => $session->{title} ,
                  sharp => "#p$tag"
                }
        );

        $text =~ s/^\+/$tag. /;
        $text = &anchor( '<span class="sanchor">' .
                         &enc($::config{"${cls}mark"}) .
                         '</span>'
                  , { p     => $session->{title} }
                  , { class => "${cls}mark sanchor" }
                  , "#p$tag"
                  ) . qq(<span class="${cls}title">$text</span>) ;

        if( $session->{main} ){
            &puts(qq(<div class="$cls x$cls">));
        }else{
            &puts(qq(<div class="x$cls">));
        }
        &headline($text,$h,( $session->{index} ? "p$tag" : undef ) );
        if( $session->{main} ){
            &puts(qq(<div class="${cls}body x${cls}body">));
        }else{
            &puts(qq(<div class="x${cls}body">));
        }
    }
}

sub syntax_engine{
    my ($ref2html,$session) = ( ref($_[0]) ? $_[0] : \$_[0] , $_[1] );
    $session->{nest}++;
    foreach my $p ( sort keys %::call_syntax_plugin ){
        $::call_syntax_plugin{$p}->( $ref2html , $session );
    }
    $session->{nest}--;
}

sub call_block{
    my ($ref2html,$session)=@_;
    foreach my $fragment( split(/\r?\n\r?\n/,$$ref2html) ){
        foreach my $p (sort keys %::block_syntax_plugin){
            $::block_syntax_plugin{$p}->($fragment,$session) and last;
        }
    }
}

sub call_close_sections{
    my ($ref2html,$session)=@_;
    exists $session->{section} and
        grep( $_ && &puts('</div></div>'),@{$session->{section}} );
}

sub block_listing{ ### <UL><OL>... block ###
    my ($fragment,$session)=@_;
    return 0 unless $fragment =~ /\A\s*[\*\+]/;

    my @stack;
    foreach( split(/\n[ \t]*(?=[\*\+])/,&preprocess($fragment,$session))){
        my ($mark,$text)=(/\A\s*(\*+|\++)/ ? ($1,$') : ('',$_) );
        my $nest=length($mark);
        my $diff=$nest - scalar(@stack);
        if( $diff > 0 ){### more deep ###
            if( $mark =~ /\+/ ){
                &puts( '<ol><li>' x $diff );
                push( @stack,('</li></ol>') x $diff );
            }else{
                &puts('<ul><li>' x $diff );
                push( @stack,('</li></ul>') x $diff );
            }
            $nest > 0 and &puts( $text );
        }else{
            $diff < 0    and &puts( reverse splice(@stack,$nest) );
            $#stack >= 0 and &puts( '</li>' );
            $nest > 0    and &puts( "<li>$text" );
        }
    }
    &puts( reverse @stack );
    1;
}

sub block_definition{ ### <DL>...</DL> block ###
    my ($fragment,$session)=@_;
    return 0 unless $fragment =~ /\A\s*\:/;

    my @s=split(/\n\s*:/, &preprocess($',$session) );
    &puts('<dl>',map( /^:/ ? "<dd>$'</dd>\r\n" : "<dt>$_</dt>\r\n",@s),'</dl>');
    1;
}

sub block_midashi1{ ### <<...>>
    my ($fragment,$session)=@_;
    return 0 unless $fragment =~ /\A\s*((?:\&lt;){2,6})(.*?)(?:\&gt;){2,6}\s*\Z/s;
    &midashi( length($1)/4-2 , $2 , $session );
    1;
}

sub block_midashi2{ ### !!!... ###
    my ($fragment,$session)=@_;
    return 0 unless $fragment =~ /\A\s*(\!{1,4})(.*)\Z/s;

    &midashi( 3 - length($1) , $2 , $session );
    1;
}

sub block_centering{ ### >> ... <<
    my ($fragment,$session)=@_;
    return 0 unless $fragment =~ /\A\s*\&gt;&gt;\s*(.*)\s*\&lt;\&lt;\s*\Z/s;

    my $s=&preprocess($1,$session);
    &puts('<p class="centering block" align="center">',$s,'</p>');
    1;
}

sub block_quoting{ ### "" ...
    my ($fragment,$session)=@_;
    return 0 unless $fragment =~ /\A&quot;&quot;/s;

    $fragment =~ s/^&quot;&quot;//gm;
    $fragment =~ s/^$/<br><br>/gm;
    &puts('<blockquote class="block">'.&preprocess($fragment,$session).'</blockquote>' );
    1;
}

sub block_table{ ### || ... | ... |
    my ($fragment,$session)=@_;
    return 0 unless $fragment =~ /\A\s*\|\|/;

    my $i=0;
    &puts('<table class="block">');
    foreach my $tr ( split(/\|\|/,&preprocess($',$session) ) ){
        my $tag='td';
        if( $tr =~ /\A\|/ ){
            $tag = 'th'; $tr = $';
        }
        &puts( '<tr class="'.(++$i % 2 ? "odd":"even").'">',
               map("<$tag>$_</$tag>",split(/\|/,$tr) ) , '</tr>' );
    }
    &puts('</table>');
    1;
}

sub block_htmltag{ ### <blockquote> or <center>
    my ($fragment,$session)=@_;
    return 0 unless
        $fragment =~ /\A\s*&lt;(blockquote|center)&gt;(.*)&lt;\/\1&gt;\s*\Z/si ;
    my $tag=$1;
    &puts( "<$tag>",&preprocess($2,$session),"</$tag>" );
    1;
}

sub block_separator{ ### ---
    my ($fragment,$session)=@_;
    return 0 unless $fragment =~ /\A\s*\-\-\-+\s*\Z/;

    &puts( '<hr class="sep">' );
    1;
}

sub block_normal{
    my ($fragment,$session)=@_;
    if( (my $s = &preprocess($fragment,$session)) !~ /^\s*$/s ){
        if( $s =~ /\A\s*<(\w+).*<\/\1[^\/]*>\s*\Z/si ){
            &puts( "<div>$s</div>" );
        }else{
            &puts("<p>$s</p>");
        }
    }
    1;
}

sub w_ok{ # equals "-w" except for root-user.
    ( $#_ < 0 ? stat(_) : stat($_[0]) )[2] & 0200;
}
