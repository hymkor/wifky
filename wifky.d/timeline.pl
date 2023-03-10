# 0.1_1 # timeline
package wifky::timeline;

BEGIN{
    eval{ require 'strict.pm';   }; strict  ->import() unless $@;
    eval{ require 'warnings.pm'; }; warnings->import() unless $@;
}

$::preferences{Timeline} = [
    { desc=>'articles number' , name=>'timeline__count' },
    { desc=>'filter' , name=>'timeline__filter' },
    { desc=>'default Frontpage' , name=>'timeline__default' , type=>'checkbox' } ,
    { desc=>'order by' , name=>'timeline__orderby' , type=>'select' ,
      option=>[ ['timestamp','timestamp'],['name','name'] ] }
];

$wifky::timeline::template ||= '
    <div class="main">
        <div class="header">
            &{header}
        </div><!-- header -->
        <div class="autopagerize_page_element">
            &{main} <!-- contents and footers -->
        </div>
        <div class="autopagerize_insert_before"></div>
        <div class="footest">
            %{Footest}
        </div>
        <div class="copyright footer">
            &{copyright}
        </div><!-- copyright -->
    </div><!-- main -->
    <div class="sidebar">
    %{Sidebar}
    </div><!-- sidebar -->
    &{message}';

sub each_three{
    my @list=@_;
    my $cursor;
    return sub{
        my $prev=$cursor;
        $cursor=shift(@list);
        if( $cursor ){
            return $list[0],$cursor,$prev;
        }else{
            return ();
        }
    };
}

sub concat_article{
    # 引数で与えられた「ページ名」を全て Footer 付きで連結して出力する。
    # undef なページ名・本文が存在しないページは無視する。
    my $count=shift(@_);
    my $iter=&each_three(@_);
    while( my ($prev,$curr,$next)=$iter->() ){
        last if --$count < 0;
        next unless defined $curr && -f $curr->{fname};
        local $::inline_plugin{next} = sub {
            $next ? &::anchor( $next->{title},{ p=>$next->{title} } ) : '';
        };
        local $::inline_plugin{prev} = sub {
            $prev ? &::anchor( $prev->{title},{p=>$prev->{title} } ) : '';
        };

        my $pagename=$curr->{title};
        &::puts('<div class="day">');
        &::putenc('<h2><span class="title"><a href="%s">%s</a></span></h2><div class="body">',
                    &::title2url( $pagename ) , $pagename );
        local $::form{p} = $pagename;
        &::print_page( title=>$pagename );
        &::puts('</div></div>');
        &::print_page( title=>'Footer' , class=>'terminator' );
    }
}

sub mkopt{
    my $option={r=>1,@_};
    if( $::config{timeline__orderby} ne 'name' ){
        $option->{t} = 1;
    }
    $option;
}

sub action_timeline{
    &::print_template(
        template => $wifky::timeline::template ,
        main => sub {
            my $count=$::config{'timeline__count'} || 3;
            my $filter=$::config{'timeline__filter'} || '(????.??.??)*';
            my @list=&::ls_core(&mkopt(number=>$count+1),$filter);
            &concat_article( $count , @list );
        }
    );
}

$::action_plugin{timeline} = \&action_timeline;

if( $::config{'timeline__default'} ){
    *::action_default = *wifky::timeline::action_timeline;
}

sub neighbor{
    return '' unless $::form{p};
    my $offset=(1+shift);
    my @list=&::ls_core(
        { r=>1 },$::config{'timeline__filter'} || '(????.??.??)*');
    my $iter=&each_three(@list);
    while( my @neighbor=$iter->() ){
        if( $neighbor[1]->{title} eq $::form{p} ){
            my $p=$neighbor[$offset];
            if( $p && $p->{title} ){
                return &::anchor($p->{title},{p=>$p->{title}});
            }
            return '';
        }
    }
    return '';
};

$::inline_plugin{'next'} = sub{ &neighbor(+1); };
$::inline_plugin{'prev'} = sub{ &neighbor(-1); };
