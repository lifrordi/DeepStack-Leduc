#!/usr/bin/perl -w

# Copyright (C) 2011 by the Computer Poker Research Group, University of Alberta

use strict;

use POSIX;
use File::Path;
use File::Copy;
use File::Spec;
use File::stat;
use Getopt::Long;
use Pod::Usage;

###############
# Main script #
###############

# There are several variables that should be set here by the competition
# organizer specifying what minimum length of testing is desired

my $max_submission_size = 50 * ( 1024 ** 3 ); # 50Gb of disk
my $max_avg_millisec_per_hand = 7 * 1000; # 7 sec average per hand
my $max_response_millisec = 10 * 60 * 1000; #10 minute max per response
my $max_millisec_per_hand = $max_avg_millisec_per_hand * 3000; # Unconstrained
my $max_shutdown_secs = 10; # Agents have 10 seconds to shutdown after a match
my $min_test_hands = 12000; 
my $num_test_hands = 12000;

my %game_types = (
  "submission_2pl" => {
    game_def => "holdem.limit.2p.reverse_blinds.game",
    chump => "example_player.limit.2p.sh",
    num_hands => 3000,
    big_blind => 10,
    players => 2
  },
  "submission_2pn" => {
    game_def => "holdem.nolimit.2p.reverse_blinds.game",
    chump => "example_player.nolimit.2p.sh",
    num_hands => 3000,
    big_blind => 100,
    players => 2
  },
  "submission_3pl" => {
    game_def => "holdem.limit.3p.game",
    chump => "example_player.limit.3p.sh",
    num_hands => 1000,
    big_blind => 10,
    players => 3
  }
# For the possibility of future 3p_nolimit games
#  "3p_nolimit" => {
#    gamedef => "holdem.nolimit.3p.game",
#    chump => "example_player.nolimit.3p.sh",
#    num_hands => 1000,
#    big_blind => 100,
#    players => 3
#  }
);

my $man;
my $help;

# Parse command line arguments
GetOptions( 'help' => \$help, 'man' => \$man, 
            'num_hands=i' => \$num_test_hands )
  or pod2usage( -exitstatus => 2,
                -message => "Invalid arguments.\n" .
                            "Use --help or --man for detailed usage." );

pod2usage( -verbose => 1 ) if( $help );
pod2usage( -verbose => 2 ) if( $man );
$#ARGV >= 0
  or pod2usage( -exitstatus => 2,
                -message => "Insufficient arguments.\n" .
                            "Use --help or --man for detailed usage." );

( $num_test_hands >= $min_test_hands )
  or die "Must play at least $min_test_hands hands for validation, stopped";

# Set up file paths
my $submission_path = File::Spec->rel2abs( $ARGV[ 0 ] ) ;
my ( $submission_volume, $submission_dir, $submission_last_comp )
  = File::Spec->splitpath( $submission_path );

my $validation_dir = "$submission_path.validation";
my $validation_path
  = File::Spec->catfile( $validation_dir, "$submission_last_comp.validation" );

# XXX: Script relies on its relative position with the rest of the code.  This
# isn't great, but avoids other configuration files specifying this
my ( $volume, $directories, $test_script_file )
  = File::Spec->splitpath( File::Spec->rel2abs( $0 )  );
my $scripts_dir = File::Spec->catpath( $volume, $directories, '' );
my $server_dir = File::Spec->catpath( $volume, $directories, '' );
my $test_script_path = File::Spec->catfile( $scripts_dir, $test_script_file );
my $dealer_path = File::Spec->catfile( $server_dir, "dealer" );
my $example_player_path = File::Spec->catfile( $server_dir, "example_player" );
my $play_match_path = File::Spec->catfile( $server_dir, "acpc_play_match.pl" );

# Ensure we aren't overwriting an existing validation file
( ! -e $validation_dir ) 
  or die "ERROR: $validation_dir already exists.  Move/remove it and rerun\n";

mkpath( $validation_dir );

# Open the validation file for writing
my $VALIDATION;
open( $VALIDATION, '>', $validation_path ) 
  or die "ERROR: Cannot open validation file $validation_path" . 
         "for writing: $!\n";

# Begin validation tests
print $VALIDATION "Validating $submission_path\n\n";
print "Validating $submission_path\n";
print "Validation files will be placed in $validation_dir\n";
print "Matches in progress will have output in $server_dir\n";
print "Check $validation_path for more detailed progress or errors\n\n";

# Test the versions of the files using checksums
print $VALIDATION "Gathering file versions (md5sums)...\n\n";

# Ensure the testing script is the right version
my $test_script_version_cmd = "md5sum $test_script_path";
print $VALIDATION "Testing script: $test_script_path\n";
print $VALIDATION "$test_script_version_cmd\n";

my $test_script_version_output = `$test_script_version_cmd 2>&1`;
print $VALIDATION "$test_script_version_output\n";
if( $? != 0 ) {
  print $VALIDATION "FAILED.\n";
  print $VALIDATION "Validation FAILED.\n";
  die "$test_script_version_cmd\n$test_script_version_output\n" . 
      "ERROR: Unable to verify testing script version, stopped";
}

# Verify the version of the dealer program
my $dealer_version_cmd = "md5sum $dealer_path";
print $VALIDATION "dealer: $dealer_path\n";
print $VALIDATION "$dealer_version_cmd\n";

my $dealer_version_output = `$dealer_version_cmd 2>&1`;
print $VALIDATION "$dealer_version_output\n";
if( $? != 0 ) {
  print $VALIDATION "FAILED.\n";
  print $VALIDATION "Validation FAILED.\n";
  die "$dealer_version_cmd\n$dealer_version_output\n" . 
      "ERROR: Unable to verify dealer version, stopped";
}

# Verify the version of the example_player program
my $example_player_version_cmd = "md5sum $example_player_path";
print $VALIDATION "example_player: $example_player_path\n";
print $VALIDATION "$example_player_version_cmd\n";

my $example_player_version_output = `$example_player_version_cmd 2>&1`;
print $VALIDATION "$example_player_version_output\n";
if( $? != 0 ) {
  print $VALIDATION "FAILED.\n";
  print $VALIDATION "Validation FAILED.\n";
  die "$example_player_version_cmd\n$example_player_version_output\n" . 
      "ERROR: Unable to verify example_player version, stopped";
}

# Verify the version of the play_match program
my $play_match_version_cmd = "md5sum $play_match_path";
print $VALIDATION "play_match: $play_match_path\n";
print $VALIDATION "$play_match_version_cmd\n";

my $play_match_version_output = `$play_match_version_cmd 2>&1`;
print $VALIDATION "$play_match_version_output\n";
if( $? != 0 ) {
  print $VALIDATION "FAILED.\n";
  print $VALIDATION "Validation FAILED.\n";
  die "$play_match_version_cmd\n$play_match_version_output\n" . 
      "ERROR: Unable to verify play_match.pl version, stopped";
}

# Test for what kind of submission it is (i.e., which game)
my $game_label = undef;
print $VALIDATION "Checking for game label... ";
foreach my $game ( keys( %game_types ) ) {
  if( $submission_last_comp eq $game ) {
    $game_label = $game;
    print $VALIDATION "PASSED.  Found $game_label\n\n";
    last;
  }
}

if( not defined $game_label ) {
  $, = ", "; # Sets the list printing separator
  print $VALIDATION " FAILED.\n";
  print $VALIDATION "Unrecognized directory name $submission_last_comp\n";
  print $VALIDATION "Submission directory must be one of: ",
  print $VALIDATION keys( %game_types );
  print $VALIDATION "\n";
  print $VALIDATION "Validation FAILED.\n";
  die "ERROR: Unrecognized submission directory name, stopped";
}

my $agent_name;
if( -d $submission_path ) {
  $agent_name = ( File::Spec->splitdir( $submission_path ) )[ -1 ];
} else {
  print $VALIDATION "FAILED.\n";
  print $VALIDATION "$submission_path is not a directory.\n";
  print $VALIDATION "Validation FAILED.\n";
  die "ERROR: Expected a directory, stopped";
}

# Check if the directory contains a README file
print $VALIDATION "Checking for README file... ";
if( -e File::Spec->catfile( $submission_path, "README" ) ) {
  print $VALIDATION "PASSED.\n\n";
} else {
  print $VALIDATION "FAILED.\n";
  print $VALIDATION "Validation FAILED.\n";
  die "ERROR: Missing README file, stopped";
}

# Check if the directory contains an executable startme.sh script
print $VALIDATION "Checking for executable startme.sh script... ";
my $startme_stat = stat( File::Spec->catfile( $submission_path, "startme.sh" ) );
if( $startme_stat ) {
  my $mode = $startme_stat->mode;
  my $perm_mask = S_IRWXU | S_IRGRP | S_IXGRP | S_IROTH | S_IXOTH;
  my $perm_str = sprintf( "%03o", $perm_mask & 00777 );
  # Test if the file has the same permissions as the mask
  if( ( $mode & $perm_mask ) == $perm_mask ) {
    print $VALIDATION "PASSED.\n\n";
  } else {
    print $VALIDATION "FAILED.\n";
    print $VALIDATION "startme.sh must have at least $perm_str permissions\n";
    print $VALIDATION "Validation FAILED.\n";
    die "ERROR: startme.sh must have at least $perm_str permissions, stopped";
  }
} else {
  print $VALIDATION "FAILED.\n";
  print $VALIDATION "Validation FAILED.\n";
  die "ERROR: Unable to stat startme.sh file: $!, stopped";
}

# Check if the uncompressed size of the agent submission directory is too big 
# NOTE: This isn't done is a very platorm independent way.  du does not always
# have -b available (not to mention other OSes).  Should probably just walk the
# file structure ourselves.
print $VALIDATION "Checking $submission_path for uncompressed file size... ";
my $agent_size_cmd = "du -bc $submission_path";
my @agent_size_output = `$agent_size_cmd 2>&1`;
# $? is the return value of the backtick command, test it for failure
if( $? == 0 ) {
  my @fields = split( /\W/, $agent_size_output[ -1 ] );
  my $agent_size = $fields[ 0 ];
  if( $agent_size <= $max_submission_size ) {
    print $VALIDATION "PASSED.  ($agent_size bytes)\n\n";
  } else {
    print $VALIDATION "FAILED.\n";
    print $VALIDATION "Validation FAILED.\n";
    die "ERROR: $submission_path is too large, stopped";
  }
} else {
  $, = ""; # Sets the list printing separator
  print $VALIDATION "FAILED.\n";
  print $VALIDATION "Validation FAILED.\n";
  die "$agent_size_cmd\n@agent_size_output\n" . 
      "ERROR: Unable to get agent directory size, stopped";
}

# Run the submitted agent for the specified number of trial hands.
my $matches_played = 0;
my $min_matches = ceil( $num_test_hands / 
                        $game_types{ $game_label }{ num_hands } );

my $total_decision_time = 0;
my $total_score = 0;

my $game_def = $game_types{ $game_label }{ game_def };
my $num_players = $game_types{ $game_label }{ players };
my $num_hands = $game_types{ $game_label }{ num_hands };
my $big_blind = $game_types{ $game_label }{ big_blind };
my $example_player_startme_path
  = File::Spec->catfile( $server_dir, $game_types{ $game_label }{ chump } );

print "Running matches...\n";
# Change directory to the server directory as play_match relies on relative
# paths from that directory
chdir( $server_dir ) or die "Unable to chdir to $server_dir: $!, stopped";
# Play all of the matches needed to at least meet the minimum hand count
while( $matches_played < $min_matches ) {
  my ( $match_start_time, $match_end_time );
  my $match_name = "$agent_name.test_match.$matches_played";

  # TODO?: Should the generated shell scripts be used to run the agent
  # If not, then files could be left over or we may not detect issues with
  # using the scripts

  # Construct the command for running a match
  my $match_cmd = "$play_match_path $match_name $game_def $num_hands " . 
                  "$matches_played $agent_name $submission_path/startme.sh";
  # Add the remaining players 
  for( my $player = 1; $player < $num_players; $player++ ) {
    $match_cmd = $match_cmd .  " chump" . 
      ( $num_players > 2 ? "-$player" : "" ) . " $example_player_startme_path"
  }
  # Add the server timing options
  $match_cmd = $match_cmd . " --t_per_hand $max_avg_millisec_per_hand " .
               "--t_response $max_response_millisec " . 
               "--t_hand $max_millisec_per_hand";

  # Give some visual output of progress
  print "Match ", $matches_played + 1, 
        " of $min_matches: $match_name\n";
  print $VALIDATION "========== Match ", $matches_played + 1, 
        " of $min_matches: $match_name ==========\n";

  # Ensure no other startme.sh script are running prior to the next match
  print $VALIDATION "Checking for existing agents... ";
  my $lingering_agent_cmd = "ps -eo command";
  my @lingering_agent_output = `$lingering_agent_cmd 2>&1`;
  # $? is the return value of the backtick command, test it for failure
  if( $? == 0 ) {
    my @lingering_agents = grep { /startme\.sh/ } @lingering_agent_output;
    if( @lingering_agents == 0 ) {
      print $VALIDATION "PASSED.\n\n";
    } else {
      $, = "\n"; # Sets the list printing separator
      print $VALIDATION "FAILED.\n";
      print $VALIDATION "Found the following existing agents:\n";
      print $VALIDATION @lingering_agents;
      print $VALIDATION "\n";
      print $VALIDATION "Stop other agents before proceeding with testing\n";
      print $VALIDATION "Validation FAILED.\n";
      die "ERROR: lingering startme.sh found before match $match_name, stopped";
    }
  } else {
    $, = ""; # Sets the list printing separator
    print $VALIDATION "FAILED.\n";
    print $VALIDATION "Validation FAILED.\n";
    die "$lingering_agent_cmd\n@lingering_agent_output\n" . 
        "ERROR: Unable to get processes to check for lingering agents, stopped";
  }

  print $VALIDATION "$match_cmd\n\n";

  # Collect timing statistics for the run.
  $match_start_time = time();
  my $match_output = `$match_cmd 2>&1`;
  $match_end_time = time();

  # Move any available output files to the $validation_dir
  foreach my $file ( glob( "$server_dir/$match_name*" ) ) {
    move( $file, $validation_dir );
  }

  chomp( $match_output );
  print $VALIDATION "$match_output\n";

  if( $? != 0 ) {
    print $VALIDATION "FAILED.\n";
    print $VALIDATION "Validation FAILED.\n";
    die "$match_cmd\n$match_output\n" . 
        "ERROR: Match $agent_name.test_match.$matches_played FAILED " .
        "(returned $?).\n" .
        "Check match log files in validation directory for cause, stopped";
  }

  # Extract the score from the dealer output 
  # e.g., SCORE:-1430|1430:2p_limit_foo|chump
  my $scores = ( split( /:/, $match_output ) )[ 1 ];
  $total_score += ( split( /\|/, $scores ) )[ 0 ];
  $matches_played++;
  $total_decision_time += $match_end_time - $match_start_time;

  # Verify that the agent is shutting down correctly 
  print $VALIDATION "Checking for lingering agents... ";
  # Wait a short while to give the agent time to exit after the match 
  sleep( $max_shutdown_secs );
  @lingering_agent_output = `$lingering_agent_cmd 2>&1`;
  # $? is the return value of the backtick command, test it for failure
  if( $? == 0 ) {
    my @lingering_agents = grep { /startme\.sh/ } @lingering_agent_output;
    if( @lingering_agents == 0 ) {
      print $VALIDATION "PASSED.\n\n";
    } else {
      $, = "\n"; # Sets the list printing separator
      print $VALIDATION "FAILED.\n";
      print $VALIDATION "Found the following lingering agents:\n";
      print $VALIDATION @lingering_agents;
      print $VALIDATION "\n";
      print $VALIDATION "Validation FAILED.\n";
      die "ERROR: lingering startme.sh found after match $match_name, stopped";
    }
  } else {
    print $VALIDATION "FAILED.\n";
    print $VALIDATION "Validation FAILED.\n";
    die "$lingering_agent_cmd\n@lingering_agent_output\n" . 
        "ERROR: Unable to get processes to check for lingering agents, stopped";
  }
  
  # Check for any warnings in the output
  print $VALIDATION "Checking $match_name.err output for errors/warnings... ";

  if( not open( DEALER_STDERR, 
      File::Spec->catfile( $validation_dir, "$match_name.err" ) ) ) {
    print $VALIDATION "FAILED.\n";
    print $VALIDATION "Unable to open $match_name.err for reading: $!\n";
    print $VALIDATION "Validation FAILED.\n";
    die "ERROR: Cannot open $match_name.err for reading to check for " . 
        "errors in match $match_name: $!, stopped";
  }

  my @match_warnings = grep { /(WARNING|ERROR)/ } <DEALER_STDERR>;
  close DEALER_STDERR;
  
  if( @match_warnings == 0 ) {
    print $VALIDATION "PASSED.\n\n";
  } else {
    $, = ""; # Sets the list printing separator
    print $VALIDATION "FAILED.\n";
    print $VALIDATION "Found the following warnings/errors:\n";
    print $VALIDATION @match_warnings;
    print $VALIDATION "\n";
    print $VALIDATION "Validation FAILED.\n";
    die "ERROR: dealer warnings detected in match $match_name, stopped";
  }
}

print $VALIDATION "========= Test match statistics ==========\n";
print $VALIDATION "Matches played: $matches_played\n";
print $VALIDATION "Hands played: ", ( $matches_played * $num_hands ), "\n";
print $VALIDATION "Average time per hand (seconds): ", 
                  $total_decision_time / ( $matches_played * $num_hands ), "\n";
print $VALIDATION "Average time per match (seconds): ", 
                  $total_decision_time / $matches_played, "\n";

my $performance
  = ( 1000 * $total_score ) / ( $big_blind * $matches_played * $num_hands );
print $VALIDATION "Performance (milli big blinds per hand): ", 
                  $performance, "\n";

print $VALIDATION "Checking for winning performance... ";
if( $performance >= 0 ) {
  print $VALIDATION "PASSED.\n\n";
} else {
  print $VALIDATION "FAILED.\n";
  print $VALIDATION "Validation FAILED.\n";
  die "ERROR: Submission unable to beat chump in test matches, stopped";
}

# Print completion messages
print "Validation PASSED.\n";

print $VALIDATION "Validation PASSED.\n";

close $VALIDATION;

# POD Documentation for usage message
__END__

=head1 NAME

B<validate_submission.pl> - Checks that the sepcified submission file for the
Annual Computer Poker Competition is well formed and works.

=head1 SYNOPSIS

B<validate_submission.pl> [options] submission_dir

=head1 DESCRIPTION

B<validate_submission.pl> - Tests that the specified submission file passes
basic sanity checks expected of entries in the Annual Computer Poker
Competition.  This process could take a long time depending on the
size of your submission file and the rate at which it plays.

Note that this script expects that your agent:

=over 8

=item *

Is contained in a single directory named submission_2pl, submission_2pn
or submission_3pl

=item * 

Has an startme.sh script with permissions of at least 755 at the root of your
directory

=item * 

Has a README file at the root of your directory

=item * 

Is within the size limit

=item * 

Plays only valid actions

=item * 

Cleans itself up once the match is over 

=item * 

Beats an agent that plays randomly and does not look at its cards

=back 

Failure on any of these points will cause the validation to fail.  Futhermore,
ensure that you are B<only running one test script at a time> as they will
interfere with each other.

The required argument is:

=over 8

=item B<submission_dir>

A path to a submission directory that you want to check for basic correctness

=back

=head1 OPTIONS

=over 8

=item B<--help>

Print a brief help message and exits.

=item B<--man>

Prints the manual page and exits.

=item B<--num_hands=[positive integer]>

Set the number of hands you want to test for.  Defaults to the minimum number
of hands for validation.  Please run as many as you can.

=back

=cut
