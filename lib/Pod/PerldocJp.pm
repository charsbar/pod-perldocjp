package Pod::PerldocJp;

use strict;
use warnings;
use base 'Pod::Perldoc';
use Encode;
use Term::Encoding;
use LWP::UserAgent;
use File::ShareDir qw(dist_dir);
use Path::Extended;
use utf8;

my $encoding = Term::Encoding::get_encoding() || 'utf-8';

our $VERSION = '0.01';

sub opt_R { shift->_elem('opt_R', @_) }

sub grand_search_init {
  my ($self, $pages, @found) = @_;

  if ($self->opt_R) {
    my $ua  = LWP::UserAgent->new(agent => "Pod-PerldocJp/$VERSION");
    my $dir = dir(dist_dir('Pod-PerldocJp'));
    foreach my $page (@$pages) {
      $self->aside("Searching for $page\n");
      if ($page =~ /^perl\w+$/) {
        my $file = $dir->file("perl/$page.pod");
        my $url  = "http://perldoc.jp/docs/perl/5.10.0/$page.pod.pod";
        unless ($file->size) {
          $ua->mirror($url => $file->absolute);
        }
        push @found, $file->absolute if $file->size;
      }
    }
    return @found if @found;
  }

  $self->SUPER::grand_search_init($pages, @found);
}

{
  # shamelessly ripped from Pod::Perldoc 3.15 and tweaked

  sub opt_o_with { # "o" for output format
    my($self, $rest) = @_;
    return unless defined $rest and length $rest;
    if($rest =~ m/^(\w+)$/s) {
      $rest = $1; #untaint
    } else {
      warn "\"$rest\" isn't a valid output format.  Skipping.\n";
      return;
    }

    $self->aside("Noting \"$rest\" as desired output format...\n");

    # Figure out what class(es) that could actually mean...

    my @classes;
    foreach my $prefix ("Pod::PerldocJp::To", "Pod::Perldoc::To", "Pod::Simple::", "Pod::") {
      # Messy but smart:
      foreach my $stem (
        $rest,  # Yes, try it first with the given capitalization
        "\L$rest", "\L\u$rest", "\U$rest" # And then try variations

      ) {
        push @classes, $prefix . $stem;
        #print "Considering $prefix$stem\n";
      }

      # Tidier, but misses too much:
      #push @classes, $prefix . ucfirst(lc($rest));
    }
    $self->opt_M_with( join ";", @classes );
    return;
  }

  sub init_formatter_class_list {
    my $self = shift;
    $self->{'formatter_classes'} ||= [];

    # Remember, no switches have been read yet, when
    # we've started this routine.

    $self->opt_M_with('Pod::Perldoc::ToPod');   # the always-there fallthru
    $self->opt_o_with('text');

    # XXX: man requires external pod2man, thus hard to tweak
    # $self->opt_o_with('man') unless IS_MSWin32 || IS_Dos
    #   || !($ENV{TERM} && (
    #       ($ENV{TERM} || '') !~ /dumb|emacs|none|unknown/i
    #      ));

    return;
  }

  sub maybe_generate_dynamic_pod {
    my ($self, $found_things) = @_;
    my @dynamic_pod;

    $self->search_perlfunc($found_things, \@dynamic_pod)  if  $self->opt_f;

    $self->search_perlvar($found_things, \@dynamic_pod)   if  $self->opt_v;

    $self->search_perlfaqs($found_things, \@dynamic_pod)  if  $self->opt_q;

    if( ! $self->opt_f and ! $self->opt_q and ! $self->opt_v ) {
      Pod::Perldoc::DEBUG > 4 and print "That's a non-dynamic pod search.\n";
    } elsif ( @dynamic_pod ) {
      $self->aside("Hm, I found some Pod from that search!\n");
      my ($buffd, $buffer) = $self->new_tempfile('pod', 'dyn');

      push @{ $self->{'temp_file_list'} }, $buffer;
      # I.e., it MIGHT be deleted at the end.

      my $in_list = $self->opt_f || $self->opt_v;
      print $buffd "=encoding utf-8\n\n";
      print $buffd "=over 8\n\n" if $in_list;
      print $buffd map {encode_utf8($_)} @dynamic_pod  or die "Can't print $buffer: $!";
      print $buffd "=back\n"     if $in_list;

      close $buffd        or die "Can't close $buffer: $!";

      @$found_things = $buffer;
        # Yes, so found_things never has more than one thing in
        #  it, by time we leave here

      $self->add_formatter_option('__filter_nroff' => 1);

    } else {
      @$found_things = ();
      $self->aside("I found no Pod from that search!\n");
    }

    return;
  }

  sub search_perlfunc {
    my($self, $found_things, $pod) = @_;

    Pod::Perldoc::DEBUG > 2 and print "Search: @$found_things\n";

    my $perlfunc = shift @$found_things;
    open(PFUNC, "<", $perlfunc) # "Funk is its own reward"
        or die("Can't open $perlfunc: $!");

    # Functions like -r, -e, etc. are listed under `-X'.
    my $search_re = ($self->opt_f =~ /^-[rwxoRWXOeszfdlpSbctugkTBMAC]$/)
                        ? '(?:I<)?-X' : quotemeta($self->opt_f) ;

    Pod::Perldoc::DEBUG > 2 and
     print "Going to perlfunc-scan for $search_re in $perlfunc\n";

    my $re = 'Alphabetical Listing of Perl Functions';
    if ( $self->opt_L ) {
      my $tr = $self->{'translators'}->[0];
      $re =  $tr->search_perlfunc_re if $tr->can('search_perlfunc_re');
    }

    # Skip introduction
    local $_;
    my $func_encoding = 'utf-8';
    while (<PFUNC>) {
      if (/^=encoding\s+(\S+)/) {
        $func_encoding = $1;
      }
      last if /^=head2 $re/;
    }

    # Look for our function
    my $found = 0;
    my $inlist = 0;
    while (<PFUNC>) {  # "The Mothership Connection is here!"
      if ( m/^=item\s+$search_re\b/ )  {
        $found = 1;
      }
      elsif (/^=item/) {
        last if $found > 1 and not $inlist;
      }
      next unless $found;
      if (/^=over/) {
        ++$inlist;
      }
      elsif (/^=back/) {
        --$inlist;
      }
      push @$pod, decode($func_encoding, $_);
      ++$found if /^\w/;        # found descriptive text
    }
    if (!@$pod) {
      die sprintf
        "No documentation for perl function `%s' found\n",
        $self->opt_f
        ;
    }
    close PFUNC                or die "Can't open $perlfunc: $!";

    return;
  }

  sub search_perlvar {
    my ($self, $found_things, $pod) = @_;

    my $opt = $self->opt_v;

    if ( $opt !~ /^ (?: [\@\%\$]\S+ | [A-Z]\w* ) $/x ) {
      die "'$opt' does not look like a Perl variable\n";
    }

    Pod::Perldoc::DEBUG > 2 and print "Search: @$found_things\n";

    my $perlvar = shift @$found_things;
    open(PVAR, "<", $perlvar)               # "Funk is its own reward"
        or die("Can't open $perlvar: $!");

    if ( $opt =~ /^\$\d+$/ ) { # handle $1, $2, ..., $9
      $opt = '$<I<digits>>';
    }
    my $search_re = quotemeta($opt);

    Pod::Perldoc::DEBUG > 2 and
      print "Going to perlvar-scan for $search_re in $perlvar\n";

    # Skip introduction
    local $_;
    my $var_encoding = 'utf-8';
    while (<PVAR>) {
      if (/^=encoding\s+(\S+)/) {
        $var_encoding = $1;
      }
      last if /^=over 8/;
    }

    # Look for our variable
    my $found = 0;
    my $inheader = 1;
    my $inlist = 0;
    while (<PVAR>) {  # "The Mothership Connection is here!"
      last if /^=head2 Error Indicators/;
      # \b at the end of $` and friends borks things!
      if ( m/^=item\s+$search_re\s/ )  {
        $found = 1;
      }
      elsif (/^=item/) {
        last if $found && !$inheader && !$inlist;
      }
      elsif (!/^\s+$/) { # not a blank line
        if ( $found ) {
          $inheader = 0; # don't accept more =item (unless inlist)
	    }
        else {
          @$pod = (); # reset
          $inheader = 1; # start over
          next;
        }
      }

      if (/^=over/) {
        ++$inlist;
      }
      elsif (/^=back/) {
        --$inlist;
      }
      push @$pod, decode($var_encoding, $_);
#     ++$found if /^\w/;        # found descriptive text
    }
    @$pod = () unless $found;
    if (!@$pod) {
      die "No documentation for perl variable '$opt' found\n";
    }
    close PVAR                or die "Can't open $perlvar: $!";

    return;
  }

  sub usage {
    my $self = shift;
    warn "@_\n" if @_;

    # Erase evidence of previous errors (if any), so exit status is simple.
    $! = 0;

    my $usage = <<"EOF";
perldoc [options] PageName|ModuleName|ProgramName...
perldoc [options] -f BuiltinFunction
perldoc [options] -q FAQRegex
perldoc [options] -v PerlVariable

オプション:
    -h   このヘルプを表示する
    -V   バージョンを表示する
    -r   再帰検索 (時間がかかります)
    -i   大文字小文字を無視する
    -t   pod2manとnroffではなくpod2textを使って表示(デフォルト)
    -u   整形前のPODを表示する
    -m   指定したモジュールのコードも含めて表示する
    -n   nroffのかわりを指定する
    -l   モジュールのファイル名を表示する
    -F   引数はモジュール名ではなくファイル名である
    -D   デバッグメッセージを表示する
    -T   ページャを通さずに画面に出力する
    -d   保存するファイル名
    -o   出力フォーマット名
    -M   フォーマット用のモジュール名(FormatterModuleNameToUse)
    -w   フォーマット用のオプション:値(formatter_option:option_value)
    -L   国別コード。（あれば）翻訳を表示します
    -X   あれば索引を利用する (pod.idxを探します)
    -R   perldoc.jpの日本語訳も検索
    -q   perlfaq[1-9]の質問を検索
    -f   Perlの組み込み関数を検索
    -v   Perlの定義済み変数を検索

PageName|ModuleName...
    表示したいドキュメント名です。「perlfunc」のようなページ名、
    モジュール名(「Term::Info」または「Term/Info」)、「perldoc」
    のようなプログラム名を指定できます。

BuiltinFunction
    Perlの関数名です。「perlfunc」からドキュメントを抽出します。

FAQRegex
    perlfaq[1-9]を検索して正規表現にマッチした質問を抽出します。

PERLDOC環境変数で指定したスイッチはコマンドライン引数の前に適用されます。
PODの索引には(あれば)ファイル名の一覧が(1行に1つ)含まれています。

[PerldocJp v$Pod::PerldocJp::VERSION based on Perldoc v$Pod::Perldoc::VERSION]
EOF

    die encode($encoding => $usage);
  }

  sub usage_brief {
    my $me = $0;		# Editing $0 is unportable

    $me =~ s,.*[/\\],,; # get basename

    my $usage =<<"EOUSAGE";
使い方: $me [-h] [-V] [-r] [-i] [-D] [-t] [-u] [-m] [-n nroffer_program] [-l] [-R] [-T] [-d output_filename] [-o output_format] [-M FormatterModuleNameToUse] [-w formatter_option:option_value] [-L translation_code] [-F] [-X] PageName|ModuleName|ProgramName
       $me -f PerlFunc
       $me -q FAQKeywords
       $me -A PerlVar

-hオプションをつけるともう少し詳しいヘルプが表示されます。
詳細は"perldocjp perldoc"をご覧ください。
[PerldocJp v$Pod::PerldocJp::VERSION based on Perldoc v$Pod::Perldoc::VERSION]
EOUSAGE

    die encode($encoding => $usage);
  }
}

1;

__END__

=head1 NAME

Pod::PerldocJp - perldoc that also checks perldoc.jp

=head1 SYNOPSIS

  perldocjp Some::Module

=head1 DESCRIPTION

This is a drop-in-replacement for C<perldoc> for Japanese people. Usage is the same, except it can look for a translation at L<http://perldoc.jp> with -R option.

=head1 TWEAKED METHODS

=head2 opt_R

to support -R option.

=head2 grand_search_init

looks for a 5.10.0 translation at perldoc.jp if -R option is set.

=head2 opt_o_with

looks also under Pod::PerldocJp namespace.

=head2 init_formatter_class_list

always try to use "text" formatter.

=head2 usage, usage_brief

are translated.

=head1 AUTHOR

Kenichi Ishigaki, E<lt>ishigaki@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2009 by Kenichi Ishigaki.

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
