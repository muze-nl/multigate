#
# (C) 2000 - 2005 Wieger Opmeer, Casper Joost Eyckelhof, Yvo Brevoort
#
# This package is free software; you can redistribute it and/or modify it
# under the terms of the "Artistic License".
#

package Multigate::Wrapper;

use strict;

use vars qw($VERSION $max_length);

use FileHandle;
use IPC::Open2;

use Multigate;
use Multigate::Debug;
use Multigate::Config qw(readconfig getconf);
use Multigate::NBRead;
use Multigate::Dispatch qw( dispatch_incoming );

$VERSION = '0.01';

#
#
#
sub new {
    my $protocol = shift;
    readconfig('multi.conf');    # reread config file on (re)start
    $max_length = getconf('max_message_length');

    # and now for some magic...

    my ( $reader, $writer ) = ( FileHandle->new, FileHandle->new );
    my $pid = open2( $reader, $writer, "wrappers/$protocol/wrapper.pl" );

    make_non_blocking($reader);
    make_non_blocking($writer);

    my $wrapper = {
        "protocol" => $protocol,
        "pid"      => $pid,
        "reader"   => $reader,
        "writer"   => $writer
    };
    bless $wrapper, "Multigate::Wrapper";

    Multigate::register_read_handler( $reader, $wrapper );

    return $wrapper;
}

#
#
#
sub die {
    my $wrapper = shift;
    $wrapper->write("DIEDIEDIE\n");
    Multigate::unregister_read_handler( $wrapper->{'reader'} );
    sleep(1);    # hier ook?
    close $wrapper->{'reader'};
    close $wrapper->{'writer'};
}

#
#
#
sub write {
    my $wrapper = shift;
    my $msg     = shift;
    my $fh      = $wrapper->{'writer'};
    my ( $len, $written );

    chomp $msg;
    $msg = "$msg\n";
    $len = length($msg);
    if ( $len > $max_length ) {
        $msg = substr $msg, 0, $max_length;
        $msg .= "\n";
        $len = length($msg);
    }
    if ( ( $written = syswrite( $fh, $msg, $len ) ) < $len ) {
        debug( 'Wrapper', "Pipe full, sleeping 1 second\n" );
        sleep 1;
        $written += syswrite( $fh, $msg, $len, $written );

        # throw away the rest if there is any..
        if ( $written < $len ) {
            debug( 'Wrapper',
                "Could not write all of message, even after sleep\n" );
        }
    }
}

#
# return protocolname
#
sub protocolname {
    my $wrapper = shift;
    return $wrapper->{'protocol'};
}

#
# return protocolname
#
sub protocol {
    my $wrapper = shift;
    return $wrapper->{'protocol'};
}

#
#
#
sub read_handler {
    my $wrapper =
      shift;    # $wrapper is bijvoorbeeld: Multigate::Wrapper=HASH(0x8233278)
    my $in = shift;

    # INCOMING ICQ 9472354 !weer
    # INCOMING IRC #dnd !weer
    # INCOMING IRC titanhead !weer
    # FIXME: Check for "INCOMING" in the message so we know which message is
    # intended for us to work on.

    my ( $snip_incoming, $protocol, $sender, $msg ) = split " ", $in, 4;

    # Send the incoming message to the dispatcher. It will see what to do with
    # that information.
    if ( defined $snip_incoming and $snip_incoming eq "INCOMING" ) {
        dispatch_incoming( $wrapper, $sender, $msg );
    }
}

#
# This is called (by main loop) when the wrapper.pl dies unexpectedly
#
sub close_handler {
    my $wrapper = shift;
    debug( 'Wrapper', "close handler called ", $wrapper->{'protocol'} );
    Multigate::unregister_wrapper( $wrapper->{'protocol'} );
    Multigate::unregister_read_handler( $wrapper->{'reader'} );
    close $wrapper->{'reader'};
    close $wrapper->{'writer'};
}

1;

