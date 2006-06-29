#!/usr/bin/perl -w

# -- SOAP::Lite -- soaplite.com -- Copyright (C) 2001 Paul Kulchenko --
use lib '/home/multilink/multigate/lib';

use SOAP::Lite +autodispatch => uri => 'https://ringbreak.dnd.utwente.nl:8888/Multisoap/Multisoap',
  proxy => 'http://ringbreak.dnd.utwente.nl:8888/',    # local tcp server
  on_fault => sub {
    my ( $soap, $res ) = @_;
    die ref $res ? $res->faultdetail : $soap->transport->status, "\n";
};

#print getStateName(1), "\n\n";
#print getStateNames(12,24,26,13), "\n\n";
#print getStateList([11,12,13,42])->[0], "\n\n";
#print getStateStruct({item1 => 10, item2 => 4})->{item2}, "\n\n";
#print getFrop(""), "\n\n";
#print Frop(""), "\n\n";
#print Dispatch("YvoBrevoort", "irc", "#dnd", "Hallo daar") . "\n";
my $session = StartSession("YvoBrevoort");
print $session;

#print Dispatch( "YvoBrevoort", "irc", "ylebre", "Hallo daar" ) . "\n";
#print StopSession($session);
