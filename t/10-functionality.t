#!perl -T
use 5.006;
use strict;
use warnings;

use File::Temp;
use Path::Class qw(file);
use Test::More;
use IO::ReadHandle::Include;

my @tempfiles;
my @tempdirs;

my $skipped = 0;

my $regex = qr#<include>(.*?)</include>#;

my $tfh = prepare_files(
                        <<EOD,
Main file line 1.
Main file line 2 start <INC> Main file line 2 end
Main file line 3.
EOD
                        <<EOD,
Include file A line 1 start <INC> Include file A line 1 end
Include file A line 2
EOD
                        <<EOD,
Include file B line 1
Include file B line 2
EOD
                       );

my $ifh = IO::ReadHandle::Include->new({ source => "$tfh",
                                         include => $regex });
# Main file line 1.
# Main file line 2 start Include file A line 1 start Include file B line 1
# Include file B line 2
#  Include file A line 1 end
# Include file A line 2
#  Main file line 2 end
# Main file line 3.

my @results;
while (my $line = <$ifh>) {
  push @results,
    {
     line => $line,
     end_of_data => eof($ifh),
     end_of_data_OO => $ifh->eof,
    };
}

my @expected = (
                "Main file line 1.\n",
                "Main file line 2 start Include file A line 1 start Include file B line 1\n",
                "Include file B line 2\n",
                " Include file A line 1 end\n",
                "Include file A line 2\n",
                " Main file line 2 end\n",
                "Main file line 3.\n"
               );

foreach my $i (0..$#results) {
  is($results[$i]->{line}, $expected[$i], '<> text in scalar context');
  is($results[$i]->{end_of_data}, ($i == $#results? 1: ''), 'eof(...)');
  is($results[$i]->{end_of_data_OO}, ($i == $#results? 1: ''), '->eof');
}

$ifh->seek(0,0);
@results = <$ifh>;
is_deeply(\@results, \@expected, '<> in list context');

$ifh->seek(0,0);
@results = ();
while (my $line = $ifh->getline) {
  push @results, $line;
}
is_deeply(\@results, \@expected, '->getline');

$ifh->seek(0,0);
@results = $ifh->getlines;
is_deeply(\@results, \@expected, '->getlines');

foreach my $test
  (
   {
    contents =>
    [
     "A line of text.\n\nAnother line of text.\n"
    ],
    expect => "A line of text.\n\nAnother line of text.\n",
    title => 'multiple lines, no include, final newline'
   },
   {
    contents =>
    [
     "A line of text.\n\nThe last line has no newline"
    ],
    expect => "A line of text.\n\nThe last line has no newline",
    title => 'multiple lines, no include, no final newline'
   },
   {
    contents =>
    [
     "Main file line 1.\nMain file line 2 start <INC> Main file line 2 end\nMain file line 3 without newline.",
     "Include file line 1\nInclude file line 2 no newline"
    ],
    expect => "Main file line 1.\nMain file line 2 start Include file line 1\nInclude file line 2 no newline Main file line 2 end\nMain file line 3 without newline.",
    title => 'multiple lines with include without final newline'
   },
   {
    contents =>
    [
     "Main file line 1.\nMain file line 2 start <INC> Main file line 2 end\nMain file line 3 without newline.",
     "Include file line 1\nInclude file line 2\n"
    ],
    expect => "Main file line 1.\nMain file line 2 start Include file line 1\nInclude file line 2\n Main file line 2 end\nMain file line 3 without newline.",
    title => 'multiple lines with include with final newline'
   },
   {
    contents =>
    [
     "Main file line 1.\nMain file line 2 start <INC> Main file line 2 end\nMain file line 3.\n",
     "Include file line 1\nInclude file line 2\n"
    ],
    expect => "Main file line 1.\nMain file line 2 start Include file line 1\nInclude file line 2\n Main file line 2 end\nMain file line 3.\n",
    title => 'multiple lines with include with final newline in both'
   },
   {
    contents =>
    [
     "Main file line 1.\nMain file line 2 start <INC> Main file line 2 end\nMain file line 3.\n",
     "Include file A line 1 start <INC> Include file A line 1 end\nInclude file A line 2\n",
     "Include file B line 1\nInclude file B line 2\n"
    ],
    expect => "Main file line 1.\nMain file line 2 start Include file A line 1 start Include file B line 1\nInclude file B line 2\n Include file A line 1 end\nInclude file A line 2\n Main file line 2 end\nMain file line 3.\n",
    title => 'multiple lines with double include with final newline in both'
   },
   {
    contents =>
    [ "Main file line 1.\n<INC>\n",
      "Include file line 1.\n" ],
    expect => "Main file line 1.\nInclude file line 1.\n\n",
    title => 'include at end'
   },
   {
    contents =>
    [ "Main file line 1.\n<INC>",
      "Include file line 1.\n" ],
    expect => "Main file line 1.\nInclude file line 1.\n",
    title => 'include at end, no newline'
   },
  ) {
  my $tfh = prepare_files(@{$test->{contents}});
  my $ifh = IO::ReadHandle::Include->new({ source => "$tfh",
                                           include => $regex });
  my @lines = <$ifh>;
  is_deeply(\@lines, [split_lines($test->{expect})],
            ($test->{title} // $test->{expect}));

  $ifh = IO::ReadHandle::Include->new({ source => "$tfh",
                                        include => $regex });
  my $line = 'foo';
  my $n = read($ifh, $line, 1000, 2);
  # is($line, 'fo' . first_line_of($test->{expect}),
  #    'read text ' . ($test->{title} // $test->{expect}));
  # is($n, length(first_line_of($test->{expect})),
  #    'read length ' . ($test->{title} // $test->{expect}));
  is($line, 'fo' . $test->{expect},
     'read text ' . ($test->{title} // $test->{expect}));
  is($n, length($test->{expect}),
     'read length ' . ($test->{title} // $test->{expect}));
}

# if an include file does not exist then the include directive is not
# replaced

my $input =
                     <<EOD;
Main file line 1.
Main file line 2.
#include does_not_exist.txt
Main file line 3.
EOD

$tfh = prepare_files($input);

$ifh = IO::ReadHandle::Include->new({ source => "$tfh",
                                      include => qr/^#include (.*)$/ });
@results = <$ifh>;
is_deeply(\@results, [split_lines($input)],
          'no interpolation of nonexistent files');

done_testing();

# Write contents to one or more temporary files.  Any <INC> in each
# text value gets replaced with the name of the temporary file holding
# the next text value.  Returns the temporary file handle for the
# first text value.  The corresponding temporary file name can be
# obtained by stringifying that temporary file handle.
sub prepare_files {
  my $contents;
  # to avoid premature deletion of temporary directories and files
  @tempfiles = ();
  @tempdirs = ();
  my $tfh;
  while ($contents = pop @_) {
    # current file is in different (temporary) directory than previous
    # file
    my $td = File::Temp->newdir(@tempdirs? (DIR => $tempdirs[-1]): ());
    $tfh = File::Temp->new(DIR => "$td");
    my $prev_fn = '';
    if (@tempdirs) {
      # specify include file relative to current file's directory
      $prev_fn = file($tempfiles[-1])->relative("$td");
    }
    $contents =~ s#<INC>#<include>$prev_fn</include>#g;
    print $tfh $contents;
    $tfh->flush;
    $tfh->seek(0,0);
    push @tempfiles, $tfh; # so they don't get deleted when the local
                           # variable goes out of scope
    push @tempdirs, $td;
  }
  return $tfh;
}

# Split the concatenation of the arguments into lines with a single
# newline at the end of every line except perhaps the last one.
sub split_lines {
  return grep { $_ ne '' } split /(.*\n)/, join('', @_);
}

sub first_line_of {
  my ($text) = @_;
  my ($first_line) = $text =~ m#^(.*?$/)#;
  return $first_line if defined $first_line;
  return $text;
}
