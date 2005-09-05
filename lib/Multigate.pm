#
# Multigate.pm : Select loop state-engine stuff
#
# (C) 2000 - 2005 Wieger Opmeer, Casper Joost Eyckelhof, Yvo Brevoort
#
# This package is free software; you can redistribute it and/or modify it
# under the terms of the "Artistic License".
#

package Multigate;

use strict;

use vars
  qw( $VERSION @ISA @EXPORT %fh_to_object $readset $writeset $errorset $exit %registered_wrappers $scheduler %restart_queue $restart_waiting);

use Exporter;
use Socket;
use IO::Handle;
use IO::Select;
use POSIX;

use Multigate::Debug;
use Multigate::NBRead;
use Multigate::Config qw(readconfig getconf);

$VERSION = '1.0';
@ISA     = qw( Exporter );
@EXPORT = qw( register_read_handler unregister_read_handler make_non_blocking );

$exit = 0;

#
# Initialisation in a BEGIN block
# FIXME: is this right?
#
BEGIN {
    $readset         = IO::Select->new();
    $writeset        = IO::Select->new();
    $errorset        = IO::Select->new();
    $restart_waiting = 0;
}

#
#
#
sub register_read_handler {
    my ( $fh, $obj ) = @_;
    my $fd = fileno($fh);
    debug( 'multicore_debug', "register_read_handler: $fh ($fd): $obj" );
    $fh_to_object{$fh} = $obj;
    $readset->add($fh);
    $errorset->add($fh);
}

#
#
#
sub unregister_read_handler {
    my ($fh) = @_;
    my $fd = fileno($fh);
    debug( 'multicore_debug', "unregister_read_handler: $fh ($fd)" );
    $readset->remove($fh);
    $errorset->remove($fh);
    delete $fh_to_object{$fh};
}

#
#
#
sub register_wrapper {
    my ( $protocol, $obj ) = @_;
    $registered_wrappers{$protocol} = $obj;
}

#
#
#
sub unregister_wrapper {
    my ($protocol) = @_;
    delete $registered_wrappers{$protocol};
}

#
#
#
sub write_to_wrapper {
    my ( $protocol, $msg ) = @_;
    $registered_wrappers{$protocol}->write($msg);
}

#
# Is $protocol registered?
#
sub is_wrapper {
    my ($protocol) = @_;
    return exists $registered_wrappers{$protocol};
}

#
# return registered wrappers
#
sub list_wrappers {
    return keys(%registered_wrappers);
}

#
# protocolname to wrapperobject
#
sub get_wrapper_object {
    my ($protocol) = @_;
    return $registered_wrappers{$protocol};
}

#
# start wrapper
#
sub start_wrapper {
    my $protocol = shift;

    # Check if we are not already running the wrapper for $protocol
    if ( !is_wrapper($protocol) ) {
        my $wrapper = Multigate::Wrapper::new($protocol);
        Multigate::register_wrapper( $protocol, $wrapper );
        return 1;
    }
    else {
        debug( 'multicore',
            "Wrapper for $protocol already running. Not starting." );
        return 0;
    }
}

#
# stop wrapper
#
sub stop_wrapper {
    my $protocol = shift;
    if ( is_wrapper($protocol) ) {
        my $wrapper = get_wrapper_object($protocol);
        unregister_wrapper($protocol);
        $wrapper->die();
        return 1;
    }
    else {
        debug( 'multicore',
            "Wrapper for $protocol not running. Unable to stop" );
        return 0;
    }
}

#
# restart wrapper
#
sub restart_wrapper {
    my $protocol = shift;
    my $success  = stop_wrapper($protocol);
    sleep(1);    # won't hurt
    return ( start_wrapper($protocol) && $success );
}

# Scheduler Administrivia

# is the scheduler running
sub scheduler_running {
    return $scheduler;
}

sub unregister_scheduler {
    $scheduler = 0;
}

sub register_scheduler {
    $scheduler = 1;
}

#
# Add protocol to restart-queue, if necessary
#
sub auto_restart_check_add {
    my $dead_protocol = shift;
    readconfig("multi.conf");    # reread configfile every time
     # people might have editted it to prevent continuous restarts of faulty wrappers

    my $restart_timeout = getconf('restart_timeout');
    my $restartline     =
      getconf('restart_protocols');    # space separated in config file
    my @restartprotocols = split " ", $restartline;

    foreach my $protocol (@restartprotocols) {
        if ( $dead_protocol eq $protocol ) {
            my $restart_time = time() + $restart_timeout;
            $restart_queue{$restart_time} = $dead_protocol;   # time => protocol
                 # Possible problem: time is not unique??
            $restart_waiting++;
            debug( 'multicore',
                "Restart scheduled for $protocol at $restart_time" );
            return 1;
        }
    }
    return 0;
}

#
# Start wrappers that need to be restarted
#
sub run_auto_restart_queue {

    my $now = time();
    foreach my $timestamp ( keys %restart_queue ) {
        if ( $timestamp < $now ) {
            my $protocol = $restart_queue{$timestamp};
            delete $restart_queue{$timestamp};
            $restart_waiting--;
            debug( 'multicore', "Restarted $protocol from restart_queue" );
            if ( $protocol eq 'scheduler' ) {
                unless ( Multigate::scheduler_running() ) {
                    Multigate::Scheduler::new();
                }
            }
            else {
                start_wrapper($protocol)
                  ;    #start_wrapper checks for already running wrappers
            }
        }
    }
}

#
# This is what multigate is all about: wait for a message to come in
# and then call the appropriate handler...
#
sub mainloop {
    my ( $r_ready, $w_ready, $e_ready );
    my ( $fh, $fd, $obj, $line );
    while ( !$exit ) {
        ( $r_ready, $w_ready, $e_ready ) =
          IO::Select->select( $readset, $writeset, $errorset, 60 )
          ;    # timeout optional
               # handle closed pipes etc.
        foreach $fh (@$e_ready) {
            debug( 'multicore_debug', "Select error: $fh" );
            $fh_to_object{$fh}->error_handler();
        }

        # feed lines to handler...
        foreach $fh (@$r_ready) {
            my $fd = fileno($fh);

            #debug('multicore', "Select read ready: $fh ($fd)");
            $obj = $fh_to_object{$fh};
            while ( $line = nbread($fh) ) {

                #debug( 'multicore_debug', "Select read: $fh: $line" );
                debug( 'multicore_debug',
                    "Select read: $fh: " . length($line) . "bytes" );
                $obj->read_handler($line);
            }
            unless ( defined $line ) {

                # $fh has closed...
                debug( 'multicore_debug',
                    "calling close handler $obj: $fh ($fd)" );

                # Close original and check for auto_restart
                my $protocolname = $obj->protocolname();
                $obj->close_handler();
                auto_restart_check_add($protocolname);
            }

            # done feeding lines to handler...
        }

        # Check restart queue; we get here on timeout and all fh activity
        if ($restart_waiting) {
            run_auto_restart_queue();
        }
    }
}

1;

