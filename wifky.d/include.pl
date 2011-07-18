$::inline_plugin{'include.pl_version'} = sub{ 'include.pl 1.2' };

#use strict;use warnings;

my $nest=0;
$::inline_plugin{include} = sub{
    my $session = shift;
    my $tag=( $_[0] =~ /^\-\d+$/ ? 'h'.(-shift) : 'div' );

    my $title_ = join(' ',@_);
    my $title  = &::denc($title_);
    unless( &::object_exists($title) ){
        return '<blink>${title_} not found</blink>';
    }

    local $::form{p} = $title;
    local $::print = "";

    &::print_page(title=>$title) unless $nest++;
    --$nest;
    
    my $url=&::title2url($title);
    qq(<$tag><a href="$url">$title_</a></$tag>\n$::print);
};

1;
