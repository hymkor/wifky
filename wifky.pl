#!/usr/local/bin/perl

use strict; use warnings;

$::PROTOCOL = '(?:s?https?|ftp)';
$::RXURL    = '(?:s?https?|ftp)://[-\\w.!~*\'();/?:@&=+$,%#]+' ;
$::charset  = 'EUC-JP';
$::version  = '1.3.1_0';
%::form     = %::forms = ();
$::me       = $::postme = $ENV{SCRIPT_NAME};
$::print    = ' 'x 10000; $::print = '';
%::config   = ( crypt => '' , sitename => 'wifky!' );
%::flag     = ();

if( $0 eq __FILE__ ){
    binmode(STDOUT);
    binmode(STDIN);

    eval{
        local $SIG{ALRM} = sub { die("Time out"); };
        eval{ alarm 60; };

        &read_form;
        &change_directory;
        foreach my $pl (sort grep(/\.plg$/,&directory) ){
            do $pl; die($@) if $@;
        }
        &load_config;
        &init_globals;
        foreach my $pl (sort grep(/\.pl$/,&directory) ){
            do $pl; die($@) if $@;
        }
        if( exists $::form{a} && exists $::action_plugin{$::form{a}} ){
            $::action_plugin{ $::form{a} }->();
        }elsif( exists $::form{p} ){ # page view
            if( exists $::form{f} ){ # output attachment
                &action_cat;
            }else{ # output page itself.
                &action_view($::form{p});
            }
        }elsif( &object_exists($::config{FrontPage}) ){
            &action_view($::config{FrontPage});
        }else{
            &do_index('recent','rindex','-l');
        }

        &flush;
        eval{ alarm 0; };
    };
    if( $@ ){
        print "Content-Type: text/html;\n\n<html><body>\n",
              &errmsg($@),"\n</body></html>\n";
    }
    exit(0);
}

sub change_directory{
    my $pagedir = __FILE__ ; $pagedir =~ s/\.\w+((\.\w+)*)$/.dat$1/;
    unless( chdir $pagedir ){
        mkdir($pagedir,0755);
        chdir $pagedir or die("can not access $pagedir.");
    }
    # local *ERR;
    # open(ERR,'>>stderr.txt');
    # open(STDERR,'>&ERR');
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
        'pagename' => \&plugin_pagename ,
        'recent'   =>
            sub{ '<ul>'.&ls('-r','-t',map("-$_",@_[1..$#_])) . '</ul>' } ,
        'search'   => \&plugin_search ,
        'fn'       => \&plugin_footnote ,
        'ls'       => sub{ '<ul>' . &ls(map(&denc($_),@_[1..$#_])) . '</ul>' },
        'comment'  => \&plugin_comment ,
        'sitename' => sub{ &enc(exists $::config{sitename} ?
                                $::config{sitename} : '') } ,
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
    );

    %::action_plugin = (
        'index'         => sub{ &do_index('recent','rindex','-i','-a','-l');  },
        'rindex'        => sub{ &do_index('recent','index' ,'-i','-a','-l','-r'); },
        'older'         => sub{ &do_index('recent','index' ,'-i','-a','-l','-t'); },
        'recent'        => sub{ &do_index('older' ,'index' ,'-i','-a','-l','-t','-r');},
        '?'             => \&action_seek ,
        'edt'           => \&action_edit ,
        'pwd'           => \&action_passwd ,
        'ren'           => \&action_rename ,
        'comment'       => \&action_comment ,
        'Delete'        => \&action_delete ,
        'Commit'        => \&action_commit ,
        'Preview'       => \&action_preview ,
        'Upload'        => \&action_upload ,
        'tools'         => \&action_tools ,
        'preferences'   => \&action_preferences ,
        'new'           => \&action_new ,
        'signin'        => \&action_signin ,
        'signout'       => \&action_signout ,
        'Freeze/Fresh'  => \&action_freeze_or_fresh ,
    );

    @::http_header = ( "Content-type: text/html; charset=$::charset" );

    @::html_header = (
      qq(<meta http-equiv="Content-Type" content="text/html; charset=$::charset">\n<meta http-equiv="Content-Style-Type" content="text/css">\n<meta name="generator" content="wifky.pl $::version">\n<link rel="start" href="$::me">\n<link rel="index" href="$::me?a=index">)
    );

    @::body_header = ( 
        ### qq{<form name="newform" action="$::me" method="post" style="display:none"><input type="hidden" name="p" /><input type="hidden" name="a" value="edt" /></form>} || 
        $::config{body_header}||'' );

    %::menubar = (
        '100_FrontPage' => &anchor($::config{FrontPage} , undef  ) ,
        '600_Index'     => &anchor('Index',{a=>'recent'}) ,
    );
    if( !&is('lonely') || &is_signed() ){
        $::menubar{'200_New'} 
            = &anchor('New' , { a=>'new' } 
         ###, { onClick=> "JavaScript:if(typeof(document.newform.p.value=prompt('New page name'))!='undefined'){document.newform.submit()};return false" }
        );
    }
    @::menubar = ();
    if( &is_signed() ){
        $::menubar{'900_SignOut'} = &anchor('SignOut',{a=>'signout'},{ref=>'nofollow'});
        $::menubar{'500_Tools'} = &anchor('Tools',{a=>'tools'},{ref=>'nofollow'});
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
    unless( exists $::form{a} ){
        my $curpage=exists $::form{p} ? $::form{p} : $::config{FrontPage};
        if( !&is_frozen() || &is_signed() ){
            $::menubar{'300_Edit'} =
                &anchor('Edit',{ a=>'edt', p=>$curpage},{rel=>'nofollow'});
        }
    }
    @::copyright = (
        qq(Generated by <a href="http://wifky.sourceforge.jp">wifky</a> $::version with Perl $])
    );

    %::preferences = (
        ' General Options' => [
            { desc=>'script-revision '.$::version.' $Date: 2007/12/15 05:27:44 $' ,
              type=>'rem' },
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
        ],
        ' Section Marks' => [
            { desc=>'Section mark', name=>'sectionmark', size=>3 } ,
            { desc=>'Subsection mark' , name=>'subsectionmark' , size=>3 } ,
            { desc=>'Subsubsection mark' , name=>'subsubsectionmark' , size=>3 }
        ]
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
        '500_block_syntax'   => \&call_block ,
        '800_close_sections' => \&call_close_sections ,
        '900_footer'         => \&call_footnote ,
    );
    %::final_plugin = (
        '500_outline'  => \&final_outline ,
        '900_verbatim' => \&unverb ,
    );
    %::form_list = (
        '100_textarea'       => \&form_textarea ,
        '200_preview_botton' => \&form_preview_button ,
        '300_signarea'       => \&form_signarea ,
        '400_submit'         => \&form_commit_button ,
        '500_attachemnt'     => \&form_attachment ,
    );

    @::outline = ();
}

sub read_multimedia{
    my ($query_string , $cutter ) = @_;

    my @blocks = split("\r\n${cutter}","\r\n$query_string");
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
    foreach my $set (split(/[,;]\s*/,$ENV{'HTTP_COOKIE'}||'') ){
        $::cookie{$`}=$' if $set =~ /=/ ;
    }
    if( exists $ENV{REQUEST_METHOD} && $ENV{REQUEST_METHOD} eq 'POST' ){
        $ENV{CONTENT_LENGTH} > 1024*1024 and die('Too large form data');
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
    grep(($::print .= "$_\r\n",0),@_);
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
    my ($fn)=@_; $::mtime_cache{$fn} ||= (-f $fn ? ( stat($fn) )[9] : 0);
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
    undef @::dir_cache;
    undef %::dir_cache;
}
sub title2mtime{
    &mtime( &title2fname(@_) );
}
sub fname2title{
    pack('h*',$_[0]);
}
sub title2fname{
    join('__',map(unpack('h*',$_),@_) );
}
sub percent{
    my $s = shift;
    $s =~ s/([^\w\'\.\-\*\(\)\_ ])/sprintf('%%%02X',ord($1))/eg;
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
    &is_frozen() and &puts('checked');
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
    &begin_day('Attachment');
    &puts('<p>New:<input type="file" name="newattachment_b" size="48">');
    &puts('<input type="submit" name="a" value="Upload"></p>');
    my @attachments=&list_attachment( $::form{p} ) or return;
    &puts('<p>');
    foreach my $attach (sort @attachments){
        my $fn = &title2fname($::form{p}, $attach);

        &putenc('<input type="checkbox" name="f" value="%s"' , $attach );
        if( !&is_signed() && ! -w $fn ){
            &puts(' disabled');
        }
        &putenc('><input type="text" name="dummy" readonly value="&lt;&lt;{%s}"
                size="20" style="font-family:monospace"
                onClick="this.select();">', $attach );
        &puts('('.&anchor('download',{ a=>'cat' , p=>$::form{p} , f=>$attach } ).':' );
        &putenc('%d bytes, at %s', (stat $fn)[7],&mtime($fn));
        &puts('<strong>frozen</strong>') unless -w _;
        &puts(')<br>');
    }
    &puts('</p>');
    if( &is_signed() ){
        &puts('<input type="submit" name="a" value="Freeze/Fresh">');
    }
    &puts('<input type="submit" name="a" value="Delete" onClick="JavaScript:return window.confirm(\'Delete Attachments. Sure?\')">');
    &end_day();
}

sub print_form{
    my ($title,$newsrc,$orgsrc) = @_;

    &putenc('<div class="update"><form name="editform" action="%s"
          enctype="multipart/form-data" method="post"
          accept-charset="%s" ><input type="hidden" name="orgsrc_y" value="%s"
        ><input type="hidden" name="p" value="%s"><br>'
        , $::postme , $::charset , &yen($$orgsrc) , $title );
    grep( $::form_list{$_}->($newsrc), sort keys %::form_list );
    &puts('</form></div>');
}

sub flush_header{
    print join("\r\n",@::http_header);
    print qq(\r\n\r\n<?xml version="1.0" encoding="$::charset"?>);
    print qq(\r\n<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">);
    print qq(\r\n<html lang="ja"><head>\r\n);
    print join("\r\n",@::html_header),"\r\n";
}

sub print_header{
    $::final_plugin{'000_header'} = \&flush_header;
    my %arg=(@_);
    my $label = $::config{sitename};
    $label .= ' - '.$::form{p} if exists $::form{p};
    $label .= '('.$arg{title}.')' if exists $arg{title};
    push(@::html_header,"<title>$label</title>");

    &puts('<style type="text/css"><!--');
    foreach my $p (split(/\s*\n\s*/,$::config{CSS})){
        if( my $css =&read_object($p) ){
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
        &putenc('<div class="%s">' , $arg{divclass}||'main' );
        my $r=&print_page( title=>'Header' , class=>'header' );
        &puts( &plugin({},'menubar') ) unless $::flag{menubar_printed} ;
        &putenc('<h1>%s</h1>',$::config{sitename}) if !$r && $::config{sitename};
        $::flag{userheader} = 1;
    }else{
        &putenc('<div class="%s">' , $arg{divclass}||'max' );
        &puts('<div class="Header">');
        &puts( &plugin_menubar(undef) );
        &putenc( '<h1>%s</h1>' , $arg{title} ) if exists $arg{title};
        &puts('</div><!--Header-->');
    }
}

sub print_footer{
    if( $::flag{userheader} ){
        &puts('<div class="copyright footer">',@::copyright,'</div>') if @::copyright;
        &puts('</div><!-- main --><div class="sidebar">');
        &print_page( title=>'Sidebar' );
    }
    &puts('</div></body></html>');
}

sub print_sidebar_and_footer{ # for compatible with nikky.pl
    @::copyright=();
    &print_footer(); 
} 
sub print_copyright{} # for compatible.

sub is_frozen{
    if( -r &title2fname(  $#_>=0            ? $_[0]
                        : exists $::form{p} ? $::form{p}
                        : $::config{FrontPage}))
    {
        ! -w _;
    }else{
        &is('lonely');
    }
}

sub auth_check{ # If password is right, return true.
    !$::config{crypt} ||
    grep(crypt($_,'wk') eq $::config{crypt},@{$::forms{password}})>0;
}

sub ninsho{ # If password is wrong, then die.
    &auth_check() or die('!Administrator\'s Sign is wrong!');
}

sub print_signarea{
    &puts('Sign: <input type="password" name="password">');
}

sub check_frozen{
    if( !is_signed() && &is_frozen() ){
        die( '!This page is frozen.!');
    }
}
sub check_conflict{
    my $current_source = &read_object($::form{p});
    my $before_source  = $::form{orgsrc_t};
    if( $current_source ne $before_source ){
        die( "!Someone else modified this page after you began to edit."  );
    }
}

sub read_object{
    &read_file(&title2fname(@_));
}

sub read_file{
    open(FP,$_[0]) or return '';
    local $/; undef $/;
    my $object = <FP>;
    close(FP);
    defined($object) ? $object : '';
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
        open(FP,">${fname}") or die("can't write the file ${fname}.");
            binmode(FP);
            print FP ref($body) ? ${$body} : $body;
        close(FP);
        &cacheoff;
        1;
    }
}

sub action_new{
    &print_header( title=>'Create Page' );
    &putenc(qq(<form action="%s" method="post" accept-charset="%s">
        <p><input type="text" name="p" size="40">
        <input type="hidden" name="a" value="edt">
        <input type="submit" value="Create"></p></form>)
        , $::postme , $::charset );
    &print_footer;
}

sub load_config{
    grep( (/^\#?([^\#\!\t ]+)\t(.*)$/ and $::config{$1}=&deyen($2),0)
        , split(/\n/,&read_file('index.cgi') ) );
}

sub is_signed{
    if( defined($::signed) ){
        return $::signed;
    }
    if( exists $::form{signing}  &&  &auth_check() ){
        &touch_session();
        return $::signed=1;
    }

    # time(TAB)ip(TAB)key
    grep( (/^\#(\d+)\t([^\t]+)\t(.*)$/ 
        and $1 > time - 24*60*60
        and $::ip{$2}=[$3,$1],0)
        , split(/\n/,&read_file('session.cgi') ) );
    
    my $remote_addr=$ENV{REMOTE_ADDR}||0;
    if( exists $::ip{$remote_addr} && 
        $::ip{$remote_addr}->[0] eq $::cookie{$::session_cookie} )
    {
        &touch_session();
        $::signed=1;
    }else{
        $::signed=0;
    }
}

sub touch_session{
    my $remote_addr = $ENV{REMOTE_ADDR}||0;
    if( exists $::ip{$remote_addr} && 
        $::ip{$remote_addr}->[0] eq $::cookie{$::session_cookie} )
    {
        ### update current session ###
        $::ip{$remote_addr}->[1] = time;
    }else{
        ### create new session ###
        my $key=rand();
        $::ip{$remote_addr} = [ $key , time ];
        push( @::http_header , "Set-cookie: $::session_cookie=$key" );
    }
    &save_session();
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
    &print_header( title=>'Signin form' );
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
    &print_footer;
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
        if( $::form{text_t} ne $::form{orgsrc_t}  &&  $::config{archivemode} ){
            &archive();
        }
        &do_submit();
    };
    &do_preview( &errmsg($@) ) if $@;
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
        &do_preview( &errmsg($@) );
    }else{
        &do_preview;
    }
}

sub action_passwd{
    goto &signin unless is_signed();

    my ($p1,$p2) = ( $::form{p1} , $::form{p2} );
    ( $p1 ne $p2 ) and die('!New signs differ from each other!');
    $::config{crypt} = crypt($p1,'wk');
    &save_config;
    &transfer_url($::me);
}

sub action_tools{
    goto &action_signin unless is_signed();

    &print_header( title=>'Tools' );
    &begin_day('Change Administrator\'s Sign');
    &putenc('<form action="%s" method="post"
        ><p>Old Sign:<input name="password" type="password" size="40"
        ><br>New Sign(1):<input name="p1" type="password" size="40"
        ><br>New Sign(2):<input name="p2" type="password" size="40"
        ><br><input name="a" type="hidden"  value="pwd"
        ><input type="submit" value="Submit"></p></form>',$::postme);
    &end_day();
    &begin_day('Preferences');
    &putenc('<form action="%s" method="post">',$::postme);

    foreach my $section(sort keys %::preferences){
        &putenc('<div class="section"><h3>%s</h3><div class="sectionbody"><p>'
                    ,$section);
        foreach my $i ( @{$::preferences{$section}} ){
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
            }else{ # text
                &putenc(
                    '%s <input type="text" name="config__%s" value="%s" size="%s"><br>'
                    , $i->{desc} , $i->{name}
                    , exists $::config{$i->{name}} ? $::config{$i->{name}} : ''
                    , $i->{size} || 10
                );
            }
        }
        &puts('</p></div></div>');
    }
    &puts('<input type="hidden" name="a" value="preferences">',
          '<input type="submit" value="Submit"></form>');
    &end_day();

    &print_footer;
}

sub action_preferences{
    goto &action_signin unless is_signed();

    foreach my $section (values %::preferences){
        foreach my $i (@{$section}){
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
    }
    &save_config;
    &transfer_url($::me);
}

sub action_rename{
    goto &signin unless &is_signed();

    my $newtitle = $::form{newtitle};
    my $title    = $::form{p};
    my $fname    = &title2fname($title);
    my $newfname = &title2fname($newtitle);

    my @list;
    foreach my $suffix ( @{$::dir_cache{$fname}} ){
        my $older=$fname    . $suffix ;
        my $newer=$newfname . $suffix ;
        -f $newfname and die("!The new page name '$newtitle' is already used.!");
        push(@list, [ $older , $newer ] );
    }
    rename( $_->[0] , $_->[1] ) foreach @list;
    &transfer_page($newtitle);
}

sub action_seek{
    my $keyword=$::form{keyword};
    my $ekeyword=&enc( $keyword );

    &print_header( title=>qq(Seek: "$ekeyword") , userheader=>1 );
    &begin_day(qq(Seek: "$ekeyword"));
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
    &print_footer();
}

sub action_delete{
    goto &action_signin if &is_frozen() && !&is_signed();

    foreach my $f ( @{$::forms{f}} ){
        my $fn=&title2fname( $::form{p} , $f );
        if( -w $fn || &is_signed() ){
            unlink( $fn ) or rmdir( $fn );
        }
    }
    &cacheoff;
    &do_preview;
}

sub action_freeze_or_fresh{
    goto &action_signin unless &is_signed();

    foreach my $f ( @{$::forms{f}} ){
        my $fn=&title2fname( $::form{p} , $f );
        if( -w $fn ){
            chmod 0444,$fn;
        }else{
            chmod 0666,$fn;
        }
    }
    &cacheoff;
    &do_preview;
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
        my $fname  = &title2fname($title,"comment.${comid}");
        local *FP;
        open(FP,">>${fname}") or die("Can not open $fname for append");
            my @tm=localtime;
            printf FP "%04d/%02d/%02d %02d:%02d:%02d\t%s\t%s\r\n"
                , 1900+$tm[5],1+$tm[4],@tm[3,2,1,0]
                , &yen($who) , &yen($comment) ;
        close(FP);
    }
    my $ecomid = &enc($comid);
    &transfer_page;
}

sub begin_day{
    &puts('<div class="day">');
    &putenc('<h2><span class="title">%s</span></h2>',$_[0]);
    &puts('<div class="body">');
}

sub end_day{ &puts('</div></div>'); }

sub do_index{
    my $t=shift;
    my $n=shift;

    &print_header( title=>'IndexPage' , userheader=>1 );
    &begin_day('IndexPage');
        &puts('<ul><li><tt>' . &anchor(' Last Modified Time' , { a=>$t } ) .
                '&nbsp' . &anchor('Page Title' , { a=>$n } ) .
                '</tt></li>' , &ls(@_) , '</ul>' );
    &end_day();
    &print_footer();
}

sub action_upload{
    exists $::form{p} or die('not found pagename');
    &check_frozen;
    my $fn=&title2fname( $::form{p} , $::form{'newattachment_b.filename'} );
    if( -r $fn && !-w _ ){
        &do_preview('The attachment is frozen.');
    }else{
        &write_file( $fn , \$::form{'newattachment_b'} );
        &do_preview;
    }
}

sub lockdo{
    my $code=shift;
    push(@_,'LOCK');
    my $lock=&title2fname(@_);
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

    &is_frozen() and chmod(0644,$fn);

    defined($::hook_submit) and $::hook_submit->(\$title , \$::form{text_t});
    if( &lockdo( sub{ &write_file( $fn , \$::form{text_t} ) },$::form{p} )){
        chmod 0444,$fn if $::form{to_freeze};
        utime($sagetime,$sagetime,$fn) if $::form{sage};
        &transfer_page();
    }else{
        &transfer_url($::me.'?a=recent');
    }
}

sub transfer_url{
    my $url=(shift || $::me);
    print join("\r\n",@::http_header),"\r\n\r\n";
    print <<"BODY";
<html>
<head>
<title>Moving...</title>
<meta http-equiv="refresh" content="1;URL=${url}">
</head>
<body><a href="${url}">Wait or Click Here</a></body>
</html>
BODY
    exit(0);
}

sub transfer_page{
    &transfer_url( &myurl( { p=>( $#_ >= 0 ? $_[0] : $::form{p} ) } ) );
}

sub do_preview{
    goto &action_signin if is_frozen() && !&is_signed();

    my $e_message = shift;
    my $title = $::form{p};

    &print_header(title=>'Preview');
    defined($e_message) and &puts(qq(<div class="warning">${e_message}</div>));
    &begin_day($title);
        &print_page( title=>$title , source=>\$::form{text_t} , index=>1 , main=>1 );
    &end_day();
    &print_form( $title , \$::form{text_t} , \$::form{orgsrc_t} );
    &print_footer();
}

sub action_edit{
    goto &action_signin if is_frozen() && !&is_signed();

    my $title = $::form{p};
    &print_header(title=>'Edit');
    &begin_day($title);
    my $fn=&title2fname($title);
    my $source=&read_file($fn);
    &print_form( $title , \$source , \$source );
    &end_day();

    if( &object_exists($::form{p}) && &is_signed() ){
        &begin_day('Rename');
        &putenc('<p><form action="%s" method="post">
            <input type="hidden"  name="a" value="ren">
            <input type="hidden"  name="p" value="%s">
            Title: <input type="text" name="newtitle" value="%s" size="80">'
            , $::postme , $::form{p} , $::form{p} );
        &puts('<br><input type="submit" name="ren" value="Submit"></form></p>');
        &end_day();
    }
    &print_footer();
}

sub action_view{
    my $title = $::form{p} = shift;
    &print_header( userheader=>1 );
    &begin_day( $title );
        &print_page( title=>$::form{p} , index=>1 , main=>1 );
    &end_day();
    &print_page( title=>'Footer' , class=>'terminator' );
    &print_footer();
}

sub action_cat{
    my $attach=$::form{f};
    my $path=&title2fname($::form{p},$attach);

    open(FP,$path) or die('Can not found the filename');
    binmode(FP);
    binmode(STDOUT);

    my $type= $attach =~ /\.gif$/i ? 'image/gif'
            : $attach =~ /\.jpg$/i ? 'image/jpeg'
            : $attach =~ /\.png$/i ? 'image/png'
            : $attach =~ /\.pdf$/i ? 'application/pdf'
            : $attach =~ /\.txt$/i ? 'text/plain'
            : 'application/octet-stream';

    print  qq(Content-Disposition: attachment; filename="${attach}"\r\n);
    print  qq(Content-Type: ${type}\r\n);
    printf qq(Content-Length: %d\r\n),( stat(FP) )[7];
    printf qq(Last-Modified: %s, %02d %s %04d %s GMT\r\n) ,
                (split(' ',scalar(gmtime((stat(FP))[9]))))[0,2,1,4,3];
    print  qq(\r\n);
    print <FP>;
    close(FP);
    exit(0);
}

sub cache_update{
    unless( defined(@::dir_cache) ){
        opendir(DIR,'.') or die('can\'t read work directory.');
        while( my $fn=readdir(DIR) ){
            push( @::dir_cache , $fn );
            if( $fn =~ /^((?:[0-9a-f][0-9a-f])+)(__(?:[0-9a-f][0-9a-f])+)?$/ ){
                push( @{$::dir_cache{$1}} , $2||'' );
            }
        }
        closedir(DIR);
    }
}

sub directory{
    &cache_update() ; @::dir_cache;
}

sub list_page{
    &cache_update() ; keys %::dir_cache;
}

sub object_exists{
    &cache_update() ; exists $::dir_cache{ &title2fname($_[0]) }
}

sub list_attachment{
    &cache_update();
    map{ &fname2title(substr($_,2)) }
        grep{ defined($_) && /^__/ }
            @{ $::dir_cache{ &title2fname( shift ) } };
}

sub print_page{
    my %args=( @_ );
    my $title=$args{title};
    my $html =&enc( exists $args{source} ? ${$args{source}} : &read_object($title));
    return 0 unless $html;

    push(@::outline,
        { depth => -1 , text  => $title , title => $title , sharp => '' }
    );

    my %attachment;
    foreach my $attach ( &list_attachment($title) ){
        my $e_attach = &enc( $attach );
        my $url=&attach2url($title,$attach);
        $attachment{ $e_attach } = {
            # for compatible #
            name => $attach ,
            url  => $url ,
            tag  => $attach =~ /\.(png|gif|jpg|jpeg)$/i
                    ? qq(<img src="${url}" alt="${e_attach}">)
                    : qq(<a href="${url}" title="${e_attach}">${e_attach}</a>) ,
        };
    }
    my %session=(
        title      => $title ,
        attachment => \%attachment ,
        index      => $args{index} ,
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

sub verb{
    "\a".unpack('h*',$_[0])."\a";
}
sub unverb{
    ${$_[0]} =~ s|\a((?:[0-9a-f][0-9a-f])*)\a|pack('h*',$1)|ges;
}
sub strip_tag{
    my $text=shift;
    &unverb( \$text );
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

sub inner_link{
    my ($session,$symbol,$title,$sharp)
        = ($_[0], $_[1] , split(/(?=#[pf][0-9mt])/,$_[2]) );
    if( $title =~ /^#/ ){
        ($title,$sharp)=($session->{title},$title);
    }else{
        $title = &denc($title);
    }

    if( &object_exists($title) ){
        &anchor( $symbol , { p=>$title } , undef , $sharp);
    }else{
        qq(<blink>${symbol}?</blink>);
    }
}

sub plugin_menubar{
    shift;
    $::flag{menubar_printed}=1;
    my $i=50;
    my %bar=(%::menubar , map( (sprintf('%03d_argument',++$i) => $_) , @_));
    '<p class="adminmenu menubar">'. join("\r\n",
        map('<span class="adminmenu">'.$_.'</span>',
            map( $bar{$_} , sort keys %bar) , @::menubar )
    ).'</p>';
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
    $session->{index} and $attr{name}="fm${i}";
    '<sup>' .
    &anchor("*${i}", { p=> $::form{p} } , \%attr , "#ft${i}" ) .
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
    &puts(qq(</div><!--footnote-->));
    delete $session->{footnotes};
}

sub plugin_outline{
    "\x1B(outline)";
}

sub final_outline{
    my ($print)=@_;
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

    $$print =~ s/\x1B\(outline\)/$ss/g;
}

sub ls_core{
    my $opt = shift;
    my @list;
    push(@_,'*') unless @_;

    foreach (@_){
        my $pat=$_;
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
    exists $opt->{r}         and @list = reverse @list;
    exists $opt->{number} && $#list > $opt->{number}
        and splice(@list,$opt->{number});
    exists $opt->{countdown} and splice(@list,$opt->{countdown});
    @list;
}

sub parse_opt{
    my $opt=shift;
    my $arg=shift;
    foreach my $p (@_){
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
    my $buf = '';
    my %opt=();
    my @arg=();
    &parse_opt(\%opt,\@arg,@_);

    foreach my $p ( &ls_core(\%opt,@arg) ){
        $buf .= '<li>';
        exists $opt{l} and $buf .= '<tt>'.$p->{mtime}.' </tt>';
        exists $opt{i} and $buf .= '<tt>'.scalar(@{$::dir_cache{ $p->{fname} }}).' </tt>';

        $buf .= &anchor( &enc($p->{title}) , { p=>$p->{title} } );
        $buf .= "</li>\r\n";
    }
    $buf;
}

sub plugin_comment{
    my $session=shift;
    my @arg; my %opt;
    &parse_opt( \%opt , \@arg , @_ );
    my $etitle= &enc($::form{p});
    my $comid = ($arg[0] || '0');
    my $caption = $#arg >= 1
        ? '<div class="caption">'.join(' ',@arg[1..$#arg]).'</div>'
        : '';

    exists $session->{"comment.$comid"} and return '';
    $session->{"comment.$comid"} = 1;

    my $ecomid = &enc($comid);
    my $fname=&title2fname( $::form{p} , "comment.$comid" );
    my $buf = '<div class="comment">'.$caption.'<div class="commentshort">';
    if( open(FP, $fname) ){
        while( <FP> ){
            chomp;
            my ($dt,$who,$say) = split(/\t/,$_,3);
            my $text=&enc(&deyen($say)); $text =~ s/\n/<br>/g;
            $buf .= sprintf('<p><span class="commentator">%s</span>
                %s <span class="comment_date">(%s)</span></p>'
                    , &enc(&deyen($who)), $text , &enc($dt) );
        }
        close(FP);
    }
    unless( exists $opt{f} ){
        $buf .= <<HTML
<div class="form">
<form action="$::postme" method="post" class="comment">
<input type="hidden" name="p" value="$etitle">
<input type="hidden" name="a" value="comment">
<input type="hidden" name="comid" value="$ecomid">
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
    grep{
        s|\x05([^\x05]*)\x05|pack('h*',$1)|ge;
        s|\x02+|"\x02"x(length($&)>>1)|ge;
        0;
    } @param;

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

    if( exists $session->{attachment}->{$nm} ){
        if( $nm =~ /\.png$/i || $nm =~ /\.gif$/i  || $nm =~ /\.jpe?g$/i ){
            &img(   $label ,{ p=>$p , f=>$f } );
        }else{
            &anchor($label ,{ p=>$p , f=>$f } , { title=>$label } )
        }
    }else{
        "<blink>$nm</blink>";
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
    my ($depth,$text,$session)=(@_);
    $text = &preprocess($text,$session);
    my $section = ($session->{section} ||= [0,0,0,0,0]) ;

    if( $depth < 0 ){
        &puts( "<h1>$text</h1>" );
    }else{
        grep( $_ && &puts('</div></div>'),@{$section}[$depth .. $#{$section}]);
        $section->[ $depth ]++;
        grep( $_ = 0 , @{$section}[$depth+1 .. $#{$section} ] );

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

        $text =~ s/^\+/${tag}. /;
        $text = &anchor( '<span class="sanchor">' .
                         &enc($::config{"${cls}mark"}) .
                         '</span>'
                  , { p     => $session->{title} }
                  , { class => "${cls}mark sanchor" }
                  , "#p${tag}"
                  ) . qq(<span class="${cls}title">$text</span>) ;

        if( $session->{main} ){
            &puts(qq(<div class="${cls} x${cls}">));
        }else{
            &puts(qq(<div class="x${cls}">));
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
    foreach my $p ( sort keys %::call_syntax_plugin ){
        $::call_syntax_plugin{$p}->( $ref2html , $session );
    }
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
            $nest > 0    and &puts( "<li>${text}" );
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
    &puts('<p class="centering" align="center">',$s,'</p>');
    1;
}

sub block_quoting{ ### "" ...
    my ($fragment,$session)=@_;
    return 0 unless $fragment =~ /\A&quot;&quot;/s;

    $fragment =~ s/^&quot;&quot;//gm;
    &puts('<blockquote>'.&preprocess($fragment,$session).'</blockquote>' );
    1;
}

sub block_table{ ### || ... | ... |
    my ($fragment,$session)=@_;
    return 0 unless $fragment =~ /\A\s*\|\|/;

    my $i=0;
    &puts('<table>');
    foreach my $tr ( split(/\|\|/,&preprocess($',$session) ) ){
        my $tag='td';
        if( $tr =~ /\A\|/ ){
            $tag = 'th'; $tr = $';
        }
        &puts( '<tr class="'.(++$i % 2 ? "odd":"even").'">',
               map("<${tag}>$_</${tag}>",split(/\|/,$tr) ) , '</tr>' );
    }
    &puts('</table>');
    1;
}

sub block_htmltag{ ### <blockquote> or <center>
    my ($fragment,$session)=@_;
    return 0 unless
        $fragment =~ /\A\s*&lt;(blockquote|center)&gt;(.*)&lt;\/\1&gt;\s*\Z/si ;

    &puts( "<$1>",&preprocess($2,$session),"</$1>" );
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
            &puts( "<div>${s}</div>" );
        }else{
            &puts("<p>${s}</p>");
        }
    }
    1;
}
