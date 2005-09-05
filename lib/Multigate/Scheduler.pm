#
# Scheduler interface
#
# (C) 2000 - 2005 Wieger Opmeer, Casper Joost Eyckelhof, Yvo Brevoort
#
# This package is free software; you can redistribute it and/or modify it
# under the terms of the "Artistic License".
#

package Multigate::Scheduler;

use strict;

use vars qw( $VERSION $scheduler );

use IO::Handle;
use POSIX;
use IPC::Open2;

use Multigate;
use Multigate::Debug;
use Multigate::NBRead;
use Multigate::Dispatch;
use Multigate::Users;

$VERSION = '0.01';

#
#
#
sub schedule {
    my $protocol     = shift;
    my $sender       = shift;
    my $msg          = shift;
    my $protocolname = $protocol->protocolname();
    $scheduler->write("TOSCHEDULER $protocolname $sender $msg\n");
}

#
#
#
sub write {
    my $scheduler = shift;
    my $out       = shift;
    my $fh        = $scheduler->{'child_stdin'};
    print $fh $out;
    $fh->flush;
    debug( 'Scheduler_debug', "Schrijven naar de Scheduler $out\n" );
}

#
#
#
sub die {
    $scheduler->write("DIEDIEDIE\n");
    sleep 1;    # toch?

    #Tell the core not to listen anymore
    unregister_read_handler( $scheduler->{'child_stdout'} );
    Multigate::unregister_scheduler();

    close $scheduler->{'child_stdin'};
    close $scheduler->{'child_stdout'};
    undef $scheduler;
}

#
# The Scheduler has something to say... This is the tricky part:
# Can be a msg for a protocol or a command object has to be set up
#
sub read_handler {
    debug( 'Scheduler_debug', "Multigate::Scheduler::read_handler started\n" );
    my $scheduler = shift;
    my $in        = shift;

    debug( 'Scheduler_debug', "Scheduler::read_handler |$in|\n" );
    my ( $what, $rest ) = split( " ", $in, 2 );
    if ( $what eq 'TOPROTOCOL' ) {
        my ( $protocol, $sender, $msg ) = split( " ", $rest, 3 );

        # dispatch_outgoing needs a user
        Multigate::Users::init_users_module();
        my ( $user, $userlevel ) =
          Multigate::Users::get_user( $protocol, $sender );
        Multigate::Users::cleanup_users_module();

        Multigate::Dispatch::dispatch_outgoing(
            {
                'user'          => $user,
                'to_protocol'   => $protocol,
                'to_address'    => $sender,
                'from_address'  => $sender,
                'from_protocol' => $protocol
            },
            $msg
        );

    }
    elsif ( $what eq 'TODISPATCHER' ) {
        my ( $protocol, $sender, $msg ) = split( " ", $rest, 3 );
        my $wrapper_object = Multigate::get_wrapper_object($protocol);
        Multigate::Dispatch::dispatch_incoming( $wrapper_object, $sender,
            $msg );
    }
    else {
        print STDERR "WARNING: unkwown message from Scheduler: $in\n";
    }
}

#
# return protocolname
#
sub protocolname {
    my $scheduler = shift;
    return $scheduler->{'protocol'};
}

#
# return protocolname
#
sub protocol {
    my $scheduler = shift;
    return $scheduler->{'protocol'};
}

#
# This is called (by main loop) when the scheduler.pl dies unexpectedly
#
sub close_handler {
    my $scheduler = shift;
    debug( 'Scheduler', "close handler called ", $scheduler->{'protocol'} );

    #Tell the core not to listen anymore
    unregister_read_handler( $scheduler->{'child_stdout'} );
    Multigate::unregister_scheduler();

    close $scheduler->{'child_stdin'};
    close $scheduler->{'child_stdout'};
    undef $scheduler;
}

#
# Start the scheduler...
#
sub new {
    my ( $child_stdin, $child_stdout ) =
      ( IO::Handle->new(), IO::Handle->new() );

    my $pid =
      open2( $child_stdout, $child_stdin, './scheduler.pl', 'scheduler.pl' );

    make_non_blocking($child_stdin);
    make_non_blocking($child_stdout);

    $scheduler = {
        "protocol"     => "scheduler",
        "pid"          => $pid,
        "child_stdin"  => $child_stdin,
        "child_stdout" => $child_stdout
    };

    print STDERR "Scheduler has pid $pid\n";

    bless $scheduler, "Multigate::Scheduler";

    # Register. This way the core will pick it up
    register_read_handler( $child_stdout, $scheduler );
    Multigate::register_scheduler();
    return $scheduler;

}

1;
