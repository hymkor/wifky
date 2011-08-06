package wifky::draft;

# use strict;use warnings;

if( &::is_signed() ){
    $::form_list{'350_draft'} = sub{
        &::puts('<input type="submit" name="a" value="SaveAsDraft">');
    };
    $::action_plugin{SaveAsDraft} = sub{
        my $title=$::form{p};
        &::write_object($title,'draft.txt',$::form{text_t});
        my $label=$::form{label_t};
        if( $label ){
            &::write_object($title,'draft_label.txt',$label);
        }
        &::transfer_page();
    };
    $::action_plugin{edt} = sub{
        my $title=$::form{p};
        my $body_time  = &::title2mtime($title);
        my $draft_time = &::title2mtime($title,'draft.txt');

        goto &::action_edit if $body_time ge $draft_time ;

        my @attachment=&::list_attachment($title);

        local $::form{a} = 'draftedit';
        local $::form{label_t} = &::read_object($title,'draft_label.txt') || '';

        &::print_template(
            template => $::edit_template || $::system_template ,
            Title => 'Edit(load draft)' ,
            main  => sub {
                &::begin_day( $title );
                my $source=&::read_object($title);
                my $draft = &::read_object($title,'draft.txt');
                &::print_form( $title , \$draft , \$source );
                &::end_day();
            }
        );
    };
    my $hook_submit=$::hook_submit;
    $::hook_submit = sub{
        &::write_object($::form{p},'draft.txt','');
        &::write_object($::form{p},'draft_label.txt','');
        $hook_submit->(@_) if $hook_submit;
    };
    push( @{$::menubar{'600_Index'}} , &::anchor('DraftList',{a=>'draftlist'}));
    $::action_plugin{draftlist} = \&action_draft_list;
}

sub action_draft_list{
    &::print_template(
        template => $::system_template ,
        main => sub{
            &::begin_day('Draft List');
            &::puts('<ul>');
            my $pattern='__'.unpack('h*','draft.txt');
            my $len=length($pattern);
            my $cnt=0;
            foreach my $p (&::directory()){
                if( length($p) > $len && substr($p,-$len) eq $pattern ){
                    my $title=pack('h*',substr($p,0,-$len));
                    &::puts('<li>'.&::anchor($title,{p=>$title,a=>'edt'}).'</li>');
                    ++$cnt;
                }
            }
            unless( $cnt ){
                &::puts('<li>no draft pages</li>');
            }
            &::puts('</ul>');
            &::end_day();
        },
    );
}
