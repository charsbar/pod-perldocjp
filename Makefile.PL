use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
  NAME          => 'Pod::PerldocJp',
  AUTHOR        => 'Kenichi Ishigaki <ishigaki@cpan.org>',
  VERSION_FROM  => 'lib/Pod/PerldocJp.pm',
  ABSTRACT_FROM => 'lib/Pod/PerldocJp.pm',
  PREREQ_PM => {
    'Encode'              => '0',
    'HTTP::Tiny'          => '0',
    'Path::Extended'      => '0.12',
    'Pod::Perldoc'        => '3.15',
    'Pod::Text'           => '3.13',
    'Pod::Simple'         => '3.08',
    'Term::Encoding'      => '0',
    'Test::More'          => '0.47',
    'Test::UseAllModules' => '0.10',
    'URI::Escape'         => '0',
  },
  EXE_FILES => [qw(perldocjp)],
  ($ExtUtils::MakeMaker::VERSION >= 6.31
    ? ( LICENSE => 'perl' )
    : ()
  ),
);
