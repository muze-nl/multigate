#!/usr/bin/perl -w

use strict;

package Multisoap::Multisoap;

$| = 1;

my %requests;
my $count = 1;

sub Dispatch {
    my $self    = shift;
    my $sender  = shift;
    my $session = shift;
    my $command = shift;
    my $args    = shift;
    my $allargs;
    while ( defined $args ) {
        $allargs .= " $args";
        $args = shift;
    }

    $sender =~ s/ //g;

    if ( $command eq "get_messages" ) {
        if ( CheckSession( $sender, $session ) ) {
            open DATA, "< wrappers/soap/data/$sender";
            my $messages;
            while (<DATA>) {
                $messages .= $_;
            }
            close DATA;

            open DATA, "> wrappers/soap/data/$sender";
            close DATA;
            return $messages;
        } else {
            return "Not logged in.\n";
        }
    }

    if ( $command eq "login" ) {

        #       print STDERR "Login called\n";
        return StartSession($sender);
    }

    if ( $command eq "logout" ) {
        if ( CheckSession( $sender, $session ) ) {
            return StopSession($session);
        }
    }

    if ( CheckSession( $sender, $session ) ) {
        print "INCOMING soap $sender $command$allargs\n";
        return "Command dispatched.\n";
    } else {
        return "Not logged in.\n";
    }
}

sub StartSession {
    my $sender  = shift;
    my $session = $sender . time;
    open SESSION, "> wrappers/soap/sessions/$session";
    print SESSION $sender;
    close SESSION;
    return $session;
}

sub CheckSession {
    my $sender  = shift;
    my $session = shift;
    open SESSION, "< wrappers/soap/sessions/$session";
    my $filesender = <SESSION>;
    close SESSION;
    if ( $sender eq $filesender ) {
        return 1;
    } else {
        return 0;
    }
}

sub StopSession {
    my $session = shift;
    unlink "wrappers/soap/sessions/$session";
    return "Session stopped.\n";
}

sub Test {
   my $self = shift;
   my $result;
   
#   my $command = SOAP::Server::Parameters::byName([qw(command)], @_);
   my $command = shift;
   my $user = shift;
   print "INCOMING soap $user !echo $count !$command\n";
   $requests{$count} = 1;
   
   # Wait for the command to return something
   
   # 5 seconds timeout
   my $timeout = 15;
   
   $result = "Dienst is momenteel niet beschikbaar\n";
   
   while ($timeout) {
      select(undef, undef, undef, 0.5);
      
#      foreach my $client ($select->can_read(1)) {
#         if ($client == $parent) {
#            # Parent is telling us something, we must have a result back.
#            $result = <$parent>;
#            last;         
#         }
#      }
      
      if (-e "wrappers/soap/data/$count") {
         # We have output;
         open RESULT, "< wrappers/soap/data/$count";
         undef $/;
         $result = <RESULT>;
         delete($requests{$count});
         close RESULT;
         unlink "wrappers/soap/data/$count";
         last;
      }
      $timeout--;
   }
   $count++;
   
   return SOAP::Data->name(arraylist => [map {SOAP::Data->name(item => $_)->type('string')} $result]);
}

sub DispatchWait {
   my $self = shift;
   my @result;
   
   my $command = shift;
   
}

1;
