package wifky::ngwords;

$::preferences{'NG Words'} = [
  { desc=>'pagename for NG words',
    name=>'ngwords',
    type=>'text',
    size=>30
  }];

my $hook_submit_orig;
if (defined($::hook_submit) ) {
  $hook_submit_orig = $::hook_submit;
} else {
  $hook_submit_orig = sub {};
}
$::hook_submit = sub {
  my ($title, $honbun) = @_;
  if (&main::object_exists($::config{ 'ngwords' }) &&
      $$title ne $::config{ 'ngwords' }) {
    my @ng = split(/\s*\n/, &main::read_object($::config{ 'ngwords' }));
    foreach $item (@ng) {
      $tmp = index($$honbun, $item);
      if ($tmp >= 0) {
        $tmp = 'Your subject has NG word "' . $item . '".';
        &main::do_preview($tmp);
        &main::flush();
        exit(0);
      }
    }
  }
  $hook_submit_orig->(\$title, \$honbun);
};

my $action_comment_orig = $::action_plugin{'comment'};
$::action_plugin{'comment'} = sub {
  my $comment = $::form{'comment'};
  if (&main::object_exists($::config{ 'ngwords' })) {
    my @ng = split(/\s*\n/, &main::read_object($::config{ 'ngwords' }));
    foreach $item (@ng) {
      $tmp = index($comment, $item);
      if ($tmp >= 0) {
        die('!Your comment has NG word "' . $item . '".!');
      }
    }
  }
  $action_comment_orig->();
};

1;
