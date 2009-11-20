package Pod::PerldocJp::ToText;

use strict;
use warnings;
use base 'Pod::Perldoc::ToText';
use Encode;
use Term::Encoding;

my $encoding = Term::Encoding::get_encoding() || 'utf-8';

{
  no warnings 'redefine';

  sub Pod::Text::cmd_encoding {
    my ($self, $text, $line) = @_;
    ($self->{encoding}) = $text =~ /^(\S+)/;
  }

  sub Pod::Text::preprocess_paragraph {
    my $self = shift;
    local $_ = shift;
    if ($self->{encoding}) {
      $_ = decode($self->{encoding}, $_);
    }

    1 while s/^(.*?)(\t+)/$1 . ' ' x (length ($2) * 8 - length ($1) % 8)/me;
    $self->output_code ($_) if $self->cutting;
    $_;
  }

  sub Pod::Text::output {
    my ($self, $text) = @_;
    $text =~ tr/\240\255/ /d;
    unless ($$self{opt_utf8} || $$self{CHECKED_ENCODING}) {
      if ($encoding) {
        eval { binmode ($$self{output_fh}, ":encoding($encoding)") };
      }
      $$self{CHECKED_ENCODING} = 1;
    }
    print { $$self{output_fh} } $text;
  }
}

1;

__END__

=head1 NAME

Pod::PerldocJp::ToText

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 AUTHOR

Kenichi Ishigaki, E<lt>ishigaki@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2009 by Kenichi Ishigaki.

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
