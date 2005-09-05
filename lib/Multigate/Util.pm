#
# Util
# Various helper functions that are used on many places within Multigate
#
# (C) 2000 - 2005 Wieger Opmeer, Casper Joost Eyckelhof, Yvo Brevoort
#
# This package is free software; you can redistribute it and/or modify it
# under the terms of the "Artistic License".
#

package Multigate::Util;

use strict;

use vars qw( $VERSION @ISA @EXPORT @EXPORT_OK $all %cats );

use Exporter;

@ISA    = qw( Exporter );
@EXPORT = qw( cut_pieces timestamp check_multicast to_unicast stripnick);

#@EXPORT_OK = qw(  );
$VERSION = '0.01';

#Takes one (long) line and a maximum line length, and turns it into n shorter lines
#Cuts on spaces, unless pieces become shorter than 0.9* maxlenght

sub cut_pieces {
    my ( $to_split, $maxlength ) = @_;
    my @hasBeenSplit = ();
    my $endrange     = int( 0.1 * $maxlength );
    my $splitlength;

    while ( length $to_split > $maxlength ) {
        my $pos     = $maxlength - $endrange;
        my $lastpos = $maxlength;
        while (( ( $pos = index( $to_split, " ", $pos ) ) > -1 )
            && ( $pos < $maxlength ) )
        {
            $lastpos = $pos;
            $pos++;
        }
        $splitlength = $lastpos;

        my $head = substr( $to_split, 0, $splitlength );
        $to_split = substr( $to_split, $splitlength );
        $to_split =~ s/^\s+//;    #remove prefix spaces
        push @hasBeenSplit, $head;
    }
    push @hasBeenSplit, $to_split;
    return @hasBeenSplit;
}

# generates a timestamp
#

sub timestamp {
    my ( $sec, $min, $hour ) = localtime();
    my $timestamp = sprintf( "[%02d:%02d]", $hour, $min );
}

#
# Checks whether an address is a multicast address
# (e.g. private message (0) vs. channel message (1))

sub check_multicast {
    my ( $protocol, $address ) = @_;

# currently only applies to irc, private msg starts with #! , multicast starts with #name
    return ( $address =~ /^#\w+/ ) ? 1 : 0;
}

#
# changes a multicast_address to unicast (if possible)
#
sub to_unicast {
    my ( $protocol, $address ) = @_;
    if ( $protocol eq 'irc' ) {
        $address =~ s/^#[^!]+/#/;
    }
    return $address;
}

#
# This function will remove the first part of an address, especially for irc
# stripnick("#something!somenick![~]user@host") will return somenick!user@host
# It sucks that multigate needs something like this for a random protocol...
# But then again: irc sucks for developers... (not for users :)
#

sub stripnick {
    my $nick = shift;
    if ( $nick =~ /^(#.*?)!(.*?)!(.*?)$/ ) {
        my $channel  = $1;
        my $ircnick  = $2;
        my $userhost = $3;
        $userhost =~ s/^[\+\-\^\~]*//;
        $nick = $ircnick . "!" . $userhost;
    }
    return $nick;
}

1;

