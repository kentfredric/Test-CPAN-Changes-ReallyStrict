use strict;
use warnings;
use utf8;

package Test::CPAN::Changes::ReallyStrict::Object;
BEGIN {
  $Test::CPAN::Changes::ReallyStrict::Object::AUTHORITY = 'cpan:KENTNL';
}
{
  $Test::CPAN::Changes::ReallyStrict::Object::VERSION = '0.2.0';
}

# ABSTRACT: Object Oriented Guts to C<::ReallyStrict>

use Test::Builder;
use Try::Tiny;

my $TEST       = Test::Builder->new();
my $version_re = '^[._\-[:alnum:]]+$';    # "Looks like" a version


use Class::Tiny {
  testbuilder => sub { $TEST },
  filename    => sub { 'Changes' },
  next_token  => sub {
    return unless defined $_[0]->next_style;
    return qr/{{\$NEXT}}/ if $_[0]->next_style eq 'dzil';
    return;
  },
  next_style => sub { undef },
  changes    => sub {
    my ($self) = @_;
    require CPAN::Changes;
    my @extra;
    push @extra, ( next_token => $self->next_token ) if defined $self->next_token;
    return CPAN::Changes->load( $self->filename, @extra );
  },
  normalised_lines => sub {
    my ($self) = @_;
    if ( $self->delete_empty_groups ) {
      $self->changes->delete_empty_groups;
    }
    my $string = $self->changes->serialize;
    return [ split /\n/, $string ];
  },
  source_lines => sub {
    my ($self) = @_;
    my $fh;
    ## no critic (ProhibitPunctuationVars)

    if ( not open $fh, '<', $self->filename ) {
      $self->testbuilder->ok( 0, $self->filename . ' failed to open' );
      $self->testbuilder->diag( 'Error ' . $! );
      return;
    }
    my $str = do {
      local $/ = undef;
      scalar <$fh>;
    };
    close $fh or $self->testbuilder->diag( 'Warning: Error Closing ' . $self->filename );
    return [ split /\n/, $str ];
  },
  delete_empty_groups => sub { },
  keep_comparing      => sub { },
};


sub changes_ok {
  my ( $self, ) = @_;
  my $exi;
  $self->testbuilder->subtest(
    'changes_ok' => sub {
      return unless $self->loads_ok;
      return unless $self->has_releases;
      return unless $self->valid_releases;
      return unless $self->compare_lines;

      #$self->testbuilder->ok(1, 'All Subtests for ' . $self->filename . ' done' );
      $exi = 1;
    }
  );
  return unless $exi;
  return 1;
}


sub loads_ok {
  my ($self) = @_;
  my ( $error, $success );
  try {
    $self->changes();
    $success = 1;
  }
  catch {
    undef $success;
    $error = $_;
  };
  if ( not $error and $success ) {
    $self->testbuilder->ok( 1, $self->filename . ' is loadable' );
    return 1;
  }
  $self->testbuilder->ok( 0, $self->filename . ' is loadable' );
  $self->testbuilder->diag($error);
  return;
}


sub has_releases {
  my ($self)     = @_;
  my (@releases) = $self->changes->releases;
  if (@releases) {
    $self->testbuilder->ok( 1, $self->filename . ' contains at least one release' );
    return 1;
  }
  $self->testbuilder->ok( 0, $self->filename . ' does not contain any release' );
  return;
}


sub valid_release_date {
  my ( $self, $release, $release_id ) = @_;
  if ( not defined $release->date and defined $self->next_token ) {
    $self->testbuilder->ok( 1, "release $release_id has valid date (none|next_token)" );
    return 1;
  }
  if ( $release->date =~ m/^${CPAN::Changes::W3CDTF_REGEX}\s*$/ ) {
    $self->testbuilder->ok( 1, "release $release_id has valid date (regexp match)" );
    return 1;
  }
  $self->testbuilder->ok( 0, "release $release_id has an invalid release date" );
  $self->testbuilder->diag( '  ERR:' . $release->date );
  return;
}


sub valid_release_version {
  my ( $self, $release, $release_id ) = @_;
  if ( not defined $release->version and defined $self->next_token ) {
    $self->testbuilder->ok( 1, "release $release_id has valid version (none|next_token)" );
    return 1;
  }
  if ( defined $self->next_token and $release->version =~ $self->next_token ) {
    $self->testbuilder->ok( 1, "release $release_id has valid version (regexp match on next_token)" );
    return 1;
  }
  if ( $release->version =~ m/$version_re/ ) {
    $self->testbuilder->ok( 1, "release $release_id has valid version (regexp match version re)" );
    return 1;
  }
  $self->testbuilder->ok( 0, "release $release_id has valid version." );
  $self->testbuilder->diag( '  ERR:' . $release->version );
  return;
}


sub valid_releases {
  my ($self) = @_;
  my $top_exit = 1;

  $self->testbuilder->subtest(
    'valid releases' => sub {
      my (@releases) = $self->changes->releases;
      for my $id ( 0 .. $#releases ) {
        my ($release) = $releases[$id];
        my $sub_exit;
        $self->testbuilder->subtest(
          'valid release: ' . $id => sub {
            return unless $self->valid_release_date( $release, $id );
            return unless $self->valid_release_version( $release, $id );
            $sub_exit = 1;
          }
        );
        undef $top_exit unless $sub_exit;
      }
    }
  );
  return 1 if $top_exit;
  return;
}


sub compare_line {
  my ( $self, $source, $normalised, $line_number, $failed_before ) = @_;
  if ( not defined $source and not defined $normalised ) {
    $self->testbuilder->ok( 1, "source($line_number) == normalised($line_number) : undef vs undef" );
    return 1;
  }
  if ( defined $source and not defined $normalised ) {
    $self->testbuilder->ok( 0, "source($line_number) != normalised($line_number) : defined vs undef" );
    return;
  }
  if ( not defined $source and defined $normalised ) {
    $self->testbuilder->ok( 0, "source($line_number) != normalised($line_number) : undef vs defined" );
    return;
  }
  if ( $source eq $normalised ) {
    $self->testbuilder->ok( 1, "source($line_number) == normalised($line_number) : val eq val" );
    return 1;
  }
  if ( not $failed_before ) {
    $self->testbuilder->ok( 0, "Lines differ at $line_number" );
  }
  $self->testbuilder->diag( sprintf q{[%s] Expected: >%s<}, $line_number, $normalised );
  $self->testbuilder->diag( sprintf q{[%s] Got     : >%s<}, $line_number, $source );
  return;

}


sub compare_lines {
  my ($self) = @_;

  my (@source)     = @{ $self->source_lines };
  my (@normalised) = @{ $self->normalised_lines };

  my $all_lines_passed = 1;

  $self->testbuilder->subtest(
    'compare lines source vs normalised' => sub {
      $self->testbuilder->diag( sprintf "Source: %s, Normalised: %s", $#source, $#normalised );
      my $failed_already;
      for ( 0 .. $#source ) {
        my $line_passed = $self->compare_line( $source[$_], $normalised[$_], $_, $failed_already );
        if ( not $line_passed ) {
          $failed_already = 1;
          undef $all_lines_passed;
          if ( not $self->keep_comparing ) {
            last;
          }
        }
      }
    }
  );
  return 1 if $all_lines_passed;
  return;
}
1;

__END__

=pod

=head1 NAME

Test::CPAN::Changes::ReallyStrict::Object - Object Oriented Guts to C<::ReallyStrict>

=head1 VERSION

version 0.2.0

=head1 METHODS

=head2 C<changes_ok>

=head2 C<loads_ok>

    if ( $self->loads_ok() ) {

    }

=head2 C<has_releases>

    if( $self->has_releases() ){

    }

=head2 C<valid_release_date>

    if ( $self->valid_release_date( $release, $release_id ) ) {

    }

=head2 C<valid_release_version>

    if ( $self->valid_release_version( $release, $release_id ) ) {

    }

=head2 C<valid_releases>

    if ( $self->valid_releases() ) {

    }

=head2 C<compare_line>

    if ( $self->compare_line( $source_line, $normalised_line, $line_number, $failed_before ) ) {

    }

=head2 C<compare_lines>

    if ( $self->compare_lines ) {

    }

=head1 ATTRIBUTES

=head2 C<testbuilder>

Plumbing: This is where test builder calls get made.

=head2 C<filename>

The name/path of the changes file.

B<Default>: C<Changes>

=head2 C<next_token>

The regular expression to use for C<next_token>

Defaults to C<undef>, or C<{{$NEXT}}> if C<next_style> eq C<dzil>

=head2 C<next_style>

The C<next_token> style.

Defaults to C<undef>

=head2 C<changes>

=head2 C<normalised_lines>

=head2 C<source_lines>

=head2 C<delete_empty_groups>

=head2 C<keep_comparing>

=head1 AUTHOR

Kent Fredric <kentnl@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2013 by Kent Fredric <kentnl@cpan.org>.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
