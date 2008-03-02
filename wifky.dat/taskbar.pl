package wifky::taskbar;

# use strict;use warnings;

die("required wifky 1.3.1 or later") if $::version lt '1.3.1';

my $form_cnt=0;

$::inline_plugin{'taskbar'} = sub {
    my $q=shift;
    my $title=$q->{title};
    my $attach=shift || 'tasklist.txt';

    my $task=&load_task($title,$attach);
    local $::print='';

    my $updatable=( !&::is_frozen() || &::is_signed());

    if( $updatable ){
        push( @::html_header , <<HTML );
<script type="text/javascript">
<!--
function doCleanUp(title){
    if( window.confirm('Are you sure to clean all completed tasks') ){
        window.location = '$::me?a=cleanup_task;p=' + title;
    }
    return undefined;
}
// -->
</script>
HTML
    }
    &::putenc('<form name="tasks%03d" action="%s" method="POST">',++$form_cnt,$::postme);
    &::putenc('<input type="hidden" name="a" value="complete_task">');
    &::putenc('<input type="hidden" name="p" value="%s">',$title);
    &::putenc('<input type="hidden" name="f" value="%s">',$attach);

    &::puts('<div class="active_tasks">');
    my $cnt=0;
    foreach my $id ( reverse sort keys %$task ){
        my $t=$task->{$id};
        unless( $t->{status} ){
            &::putenc('<div><input type="checkbox" name="id" value="%s" />%s</div>',
                $id , $t->{title} 
            );
            ++$cnt;
        }
    }
    &::puts('<input type="submit" value="Complete">') if $cnt && $updatable;
    &::puts('</div><dl class="completed_tasks">');
    $cnt=0;
    my $yyyymmdd="";
    foreach my $id ( reverse sort keys %$task ){
        my $t=$task->{$id};
        if( $t->{status} ){
            if( substr($t->{update_dt},0,8) ne $yyyymmdd ){
                $yyyymmdd = substr($t->{update_dt},0,8);
                &::putenc('<dt>(%4s.%2s.%2s) completed.</dt>',
                    substr($yyyymmdd,0,4) ,
                    substr($yyyymmdd,4,2) ,
                    substr($yyyymmdd,6,2) );
            }
            &::putenc('<dd><input type="checkbox" name="id" value="%s" /><strike>%s</strike></dd>',
                $id, $t->{title} 
            );
            ++$cnt;
        }
    }
    &::puts('</dl>');
    if( $cnt && $updatable ){
        &::puts('<div><input type="submit" value="Undo">');
        &::puts('<a href="#" onClick="JavaScript:doCleanUp(document.tasks%03d.p.value)"',$form_cnt);
        &::puts('>Clean-up all-finished tasks</a></div>');
    }
    &::puts('</dl></form>');
    if( $updatable ){
        &::putenc('<div class="edit_task"><form action="%s" method="POST">',$::postme);
        &::putenc('<input type="hidden" name="a" value="edit_task">');
        &::putenc('<input type="hidden" name="p" value="%s">',$title);
        &::putenc('<input type="hidden" name="f" value="%s">',$attach);
        &::puts('<input type="hidden" name="id" value="" />');
        &::puts('<input type="text" name="title" value="" size="60" />');
        &::puts('<input type="submit" value="Add"></form></div>');
        &::puts('');
    }
    $::print;
};

$::action_plugin{complete_task} = sub{
    my @title=($::form{p},$::form{f}||'tasklist.txt');
    my $task=&load_task(@title);
    $task->{$::form{id}}->{status} ^= 1;
    &save_task( $task , @title );
    &::transfer_page($::form{p});
};

$::action_plugin{'cleanup_task'} = sub{
    my @title=($::form{p},$::form{f}||'tasklist.txt');
    my $task=&load_task(@title);
    my $newtask={};
    while( my ($key,$val) = each %{$task} ){
        unless( $val->{status} ){
            $newtask->{$key} = $val;
        }
    }
    &save_task( $newtask  , @title );
    &::transfer_page($::form{p});
};


$::action_plugin{'edit_task'} = sub{
    my @title=($::form{p},$::form{f}||'tasklist.txt');
    my $task=&load_task(@title);
    my @tm=localtime();
    my $stamp= sprintf("%04d%02d%02d%02d%02d%02d",
            1900+$tm[5],1+$tm[4],$tm[3], $tm[2],$tm[1],$tm[0] );
    $task->{$::form{id} || "id$stamp" } = { 
        title     => $::form{title} ,
        status    => 0 ,
        priority  => 0 ,
        update_dt => $stamp ,
        deadline  => 0 ,
    };
    &save_task( $task , @title );
    &::transfer_page($::form{p});
};

sub load_task{
    my (@title)=@_;
    my $task={};
    foreach( split(/\n/,&::read_object(@title))){
        if( /^entry=/ ){
            my @t = map{ &::deyen($_) } split(/\t/,$');
            $task->{ $t[0] } = {
                title => $t[1] ,
                status => $t[2] ,
                priority => $t[3] ,
                update_dt => $t[4] ,
                deadline => $t[5] ,
            };
        }
    }
    $task;
}

sub save_task{
    my ($task,@title)=@_;

    my $fn = &::title2fname(@title);
    if( &::is_frozen() && !&::is_signed() ){
        die('!This is frozen page.');
    }
    &::write_file($fn ,
        join("\n",
            map{ 
                my $t=$task->{$_};
                'entry=' .
                join("\t",map{ &::yen($_ ) } 
                    ($_, $t->{title},$t->{status},
                     $t->{priority},$t->{update_dt},$t->{deadline}) )
            } sort keys %$task 
        )
    );
}
