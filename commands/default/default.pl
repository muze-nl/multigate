#!/usr/bin/perl
use strict;
use warnings;

my $realuser    = $ENV{'MULTI_REALUSER'};
my $userlevel   = $ENV{'MULTI_USERLEVEL'};          # userlevel of invoking user
my $commandline = defined $ARGV[0] ? $ARGV[0] : '';

my $adminlevel = 500;    #from this level up, no admin rights needed

my ( $command, $rest ) = split ' ', $commandline, 2;

# some helper functions

sub command_exists {
  my $command = shift;
  
  #some safety
  unless ($command =~ m/^\w+$/) {
    return 0; #only accept words
  }
  return (-d "../$command")

}


# Options for command: (list|ls), (remove|del|delete|rm), $command, admin 
$command = lc($command);

if ( lc($command) eq "list" or lc($command) eq "ls") {
  my $dirname = "../../var/default/$realuser";
  my @defaults;
  if ( opendir( DIR, $dirname )) {
    while ( defined( my $file = readdir(DIR) ) ) {
      next if ($file =~ m/\.+/);
      push @defaults, $file;
    }
    closedir(DIR);
  }  
  if ( @defaults ) {
    print "Defaults set for $realuser: ", join ", ", sort @defaults;
  } else {
    print "No defaults set for $realuser\n";
  }

} elsif ( $command eq "remove" or $command eq "del" or $command eq "delete" or $command eq "rm" ) {
  $rest = lc($rest);
  if ( command_exists($rest) ) {
    if ( -e "../../var/default/$realuser/$rest") {
      unlink "../../var/default/$realuser/$rest";
      print "Removed default for $rest for $realuser\n";
    } else {
      print "No default set for $rest for $realuser\n";
    }
  } else {
    print "No such command: $rest\n";
  }
  
} elsif ( command_exists($command) ) {
  my $file = "../../var/default/$realuser/$command";
  if ((not defined $rest) or ($rest eq '') ) {
    if ( -e $file) {
      if ( open(DEFAULT, "<$file") ){
        my $new_args = <DEFAULT>; # should work, because we expect a newline after the default args
        close DEFAULT;
        print "Default for $command for $realuser: $new_args";
      } else {
        #unable to open file...
      }        
    } else {
      print "No default set for $command for $realuser\n";
    }  
  } else {
    unless (-d "../../var/default/$realuser") {
      mkdir "../../var/default/$realuser";
    }
    if ( open(DEFAULT, ">$file") ) {
      print DEFAULT "$rest\n";
      close DEFAULT;
      print "Default for $command for $realuser: $rest\n"; 
    } else {
      #unable to open file...
    }
  }
} elsif ( $command eq "admin" and ($userlevel >= $adminlevel) ) {
  my ($user, $lcommand, $args) = split ' ', $rest, 3;
  $lcommand = lc($lcommand);
  if (command_exists($lcommand)) { 
    my $file = "../../var/default/$user/$lcommand";
    if ( (not defined $args) or ($args eq '')) {
      if ( -e $file) {
        if ( open(DEFAULT, "<$file") ){
          my $new_args = <DEFAULT>; # should work, because we expect a newline after the default args
          close DEFAULT;
          print "Default for $lcommand for $user: $new_args";
        } else {
          #unable to open file...
        }        
      } else {
        print "No default set for $lcommand for $user\n";
      }  
    } else {
      unless (-d "../../var/default/$user") {
        mkdir "../../var/default/$user";
      }
      if ( open(DEFAULT, ">$file") ) {
        print DEFAULT "$args\n";
        close DEFAULT;
        print "Default for $lcommand for $user: $args\n"; 
      } else {
        #unable to open file...
      }
    }
  } else {
    print "No such command: $lcommand\n";
  }
} else {
  print "Unknown option: $command\n";
}
