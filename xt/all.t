use strict;
use warnings;
use Test::More;
use ExtUtils::Installed;
use Capture::Tiny qw/capture/;

my @FAILED;

do_tests( ExtUtils::Installed->new->modules );

foreach my $item (@FAILED) {
  diag "$$item[0] failed\n$$item[1]";
}

done_testing;

sub do_tests {
  my @target = @_;

  foreach my $module (@target) {
    my ($out, $err) = capture { system("perldocjp $module") };

    if ($err) {
      $err = join "\n", grep { !/does not map to/ } split "\n", $err;
    }

    SKIP: {
      skip "$module has no pod", 1 unless $out;
      ok !$err, "$module got no errors";
    }

    if ($out and $err) {
      push @FAILED, [$module, $err];
    }
  }
}
