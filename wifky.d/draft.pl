package wifky::draft;

use strict;use warnings;

if( &::is_signed() ){
    $::form_list{'350_draft'} = sub{
        &::puts('<input type="submit" name="a" value="SaveAsDraft">');
    };
    $::action_plugin{SaveAsDraft} = sub{
        my $title=$::form{p};
        &::write_object($title,'draft.txt',$::form{text_t});
        &::transfer_page();
    };
    $::action_plugin{edt} = sub{
        my $title=$::form{p};
        my $body_time  = &::title2mtime($title);
        my $draft_time = &::title2mtime($title,'draft.txt');

        goto &::action_edit if $body_time ge $draft_time ;

        my @attachment=&::list_attachment($title);

        &::print_template(
            template => $::system_template ,
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
        $hook_submit->(@_) if $hook_submit;
    };
}
