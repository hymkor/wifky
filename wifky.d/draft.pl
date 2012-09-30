# 0.6_0 # draft.pl

package wifky::draft;

my $version = '0.6_0';

# use strict;use warnings;

if( &::is_signed() ){
    $::form_list{'350_draft'} = sub{
        &::puts('<input type="submit" name="a" value="SaveAsDraft">');
    };
    $::action_plugin{SaveAsDraft} = sub{
        &save_draft();
        &::transfer_page();
    };
    if( $::config{draft__autosave} ){
        my %original_action;
        foreach $a ('Preview' , 'Upload' , 'Freeze/Fresh' , 'Cut' , 'Delete'){
            next unless $::action_plugin{$a};
            $original_action{$a} = $::action_plugin{$a};
            $::action_plugin{$a} = sub {
                &save_draft();
                $original_action{$::form{a}}->(@_);
            };
        }
    }
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
    if( exists $::form{p} &&
        grep($_ eq "draft.txt",(my @attach=&::list_attachment($::form{p})))<=0 )
    {
        push( @{$::menubar{'300_Edit'}} , 
              &::anchor('Hide',{ a=>'hide' , p=>$::form{p}},{ rel=>'nofollow' }) );

        $::action_plugin{hide} = sub {
            rename( &::title2fname($::form{p}) ,
                    &::title2fname($::form{p},"draft.txt") );
            my @labels = grep(/^\0/,@attach);
            if( @labels ){
                &::write_object(
                    $::form{p} ,
                    "draft_label.txt" ,
                    join(" ",map{ substr($_,1) } @labels )
                );
                foreach my $label (@labels){
                    &::write_object( $::form{p} , $label , '' );
                }
            }
            &::transfer_page();
        };
    }
    my $hook_submit=$::hook_submit;
    $::hook_submit = sub{
        &::write_object($::form{p},'draft.txt','');
        &::write_object($::form{p},'draft_label.txt','');
        $hook_submit->(@_) if $hook_submit;
    };
    push( @{$::menubar{'600_Index'}} , &::anchor('DraftList',{a=>'draftlist'}));
    $::action_plugin{draftlist} = \&action_draft_list;

    $::preferences{"Draft Plugin $version"} = [
        { desc=>'Auto Save' , 
          name=>'draft__autosave' ,
          type=>'checkbox' }
    ];
}

sub save_draft{
    my $title=$::form{p};
    my $fn = &::title2fname($title,'draft.txt');
    chmod(0666,$fn);
    &::write_file($fn,$::form{text_t});
    my $label=$::form{label_t};
    if( $label ){
        my $afn = &::title2fname($title,'draft_label.txt');
        &::write_file($afn,$label);
    }
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
