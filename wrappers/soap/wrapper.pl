#!/usr/bin/perl -w

$| = 1;
use strict;
use warnings;

use lib 'lib/';
use POSIX qw(:sys_wait_h);
use SOAP::Transport::HTTP;

use IO::Handle;
use Socket;
use Multigate::Debug;
use IO::Select;

Multigate::Debug::setdebug('soap');

#$SIG{PIPE} = 'IGNORE';    # don't want to die on 'Broken pipe' or Ctrl-C
$SIG{CHLD} = \&REAPER;

sub REAPER {
    while ( waitpid( -1, WNOHANG ) > 0 ) { }
    $SIG{CHLD} = \&REAPER;
};

#my ($child, $parent);
#socketpair($child, $parent, AF_UNIX, SOCK_STREAM, PF_UNSPEC) or die "socketpair: $!";
#$child->autoflush(1);
#$parent->autoflush(1);

my $daemon =
  SOAP::Transport::HTTP::Daemon->new( 
         LocalAddr => 'ringbreak.dnd.utwente.nl', 
         LocalPort => 8888 
  )
  ->dispatch_to( 'wrappers/soap/', 'Multisoap::Multisoap', 'Multisoap::Multisoap' )->options( { compress_threshold => 10000 } )
  ;    # enable compression support

debug( "soap_debug", "SOAP server started at ", $daemon->url );

#my $select = IO::Select->new;
#$select->add($parent);

my $pid = fork;
unless ($pid) {
#   print "Boven: $pid\n";
#   close $parent;
   while (<STDIN>) {
      my $line = $_;
      debug("soap_debug", "Got input: $line");
      if ($line =~ /OUTGOING soap .*? zegt: (.*?) (.*)/) {
         my $count = $1;
         my $message = $2;
         $message =~ s/\xb6/\n/g;
         debug("soap", "Outgoing soap for $count: $message");
         open DATA, "> wrappers/soap/data/$count";
         print DATA "$message\n";
         close DATA;
#         print $child "$count $message\n";
      }
      if ($line =~ /^DIEDIEDIE/) {
         debug("soap", "Got die, exitting");         
         exit 0;
      }
   } 
} else {
#   print "Onder: $pid\n";
#   close $child;
   close STDIN;
   $daemon->handle;
#   print "Daemon dead\n";
}
