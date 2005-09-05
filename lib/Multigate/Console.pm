#
# Console
#
# (C) 2000 - 2005 Wieger Opmeer, Casper Joost Eyckelhof, Yvo Brevoort
#
# This package is free software; you can redistribute it and/or modify it
# under the terms of the "Artistic License".
#

# TODO:
# -listwrappers or status command: listing currently running wrappers and maybe some 'accounting' info
#  (example: name - uptime - count msg send during uptime)
#
# -database functions: addprotocol, adduser, getuser, deluser etc..
#  (also accounting info, when it is implemented... addcredit, getcredit etc)
#
# -send: sending messages from console to multigate(users)

package Multigate::Console;

use strict;

use vars qw( $VERSION $console $stdin %commands );

use IO::Handle;

use Multigate;
use Multigate::Debug qw( debug setdebug unsetdebug listdebug );
use Multigate::NBRead;
use Multigate::Scheduler;

$VERSION = '0.01';

#
# Command to function table...
#
%commands = (
    'stop'             => \&stopwrapper,
    'start'            => \&startwrapper,
    'restart'          => \&restartwrapper,
    'stopscheduler'    => \&stopscheduler,
    'startscheduler'   => \&startscheduler,
    'restartscheduler' => \&restartscheduler,
    'listwrappers'     => \&listwrappers,
    'listdebug'        => \&listdebugcommand,
    'setdebug'         => \&setdebugcommand,
    'unsetdebug'       => \&unsetdebugcommand,
    'help'             => \&showhelp,
    'quit'             => \&stopmultigate,
    'bufstat'          => \&bufstat,
);

#
# Start the console...
#
sub new {

    $stdin = new IO::Handle;
    $stdin->fdopen( fileno(STDIN), 'r' );

    make_non_blocking($stdin);

    $console = { "console" => 1, };

    bless $console, "Multigate::Console";

    # Register. This way the core will pick it up
    register_read_handler( $stdin, $console );

    autoflush STDOUT 1;

    print "Console now listening on STDIN\n";
    print "MultiCon> ";

    return $console;

}

#
# Somebody typed something on the console...
#
sub read_handler {
    debug( 'Console_debug', "Multigate::Console::read_handler started\n" );
    my $console = shift;
    my $in      = shift;
    chomp $in;

    debug( 'Console_debug', "Console::read_handler |$in|\n" );

    my ( $what, $rest ) = split( " ", $in, 2 );
    my $subref;

    if ( ( defined $commands{$what} ) && ( $subref = $commands{$what} ) ) {
        &$subref($rest);
    }
    else {
        print "Unknown console command '$in'. Try 'help'\n";
    }
}

#
#
#
sub close_handler {
    unregister_read_handler($stdin);
    stopmultigate();
}

#
#
#
sub listdebugcommand {
    my @cats = listdebug();
    print 'Debug categories: ', join( ', ', @cats ), ".\n";
}

#
#
#
sub setdebugcommand {
    my $cat = shift;
    setdebug($cat);
}

#
#
#
sub unsetdebugcommand {
    my $cat = shift;
    unsetdebug($cat);
}

#
#
#
sub showhelp {

    #print "This should be a helpfull helpmessage but right now it isn't.\n";
    print "Available commands: ", join( ', ', sort keys(%commands) ), ".\n";
}

#
#
#
sub listwrappers {
    print "Running wrappers: ", join( ',', Multigate::list_wrappers ), ".\n";
}

#
#
#
sub startwrapper {
    my $protocol = shift;
    if ( Multigate::start_wrapper($protocol) ) {
        print "Succesfully started wrapper for $protocol.\n";
    }
    else {
        print "Failed to start wrapper for $protocol, already running?\n";
    }
}

#
#
#
sub stopwrapper {
    my $protocol = shift;
    if ( Multigate::stop_wrapper($protocol) ) {
        print "Succesfully stopped wrapper for $protocol.\n";
    }
    else {
        print "Failed to stop wrapper for $protocol, not running?\n";
    }
}

#
#
#
sub restartwrapper {
    my $protocol = shift;
    if ( Multigate::restart_wrapper($protocol) ) {
        print "Succesfully restarted wrapper for $protocol.\n";
    }
    else {
        print "Failed to restart wrapper for $protocol\n";
    }
}

#
#
#
sub startscheduler {
    unless ( Multigate::scheduler_running() ) {
        Multigate::Scheduler::new();
        print "Succesfully started scheduler.\n";
        return 1;
    }
    else {
        print "Scheduler already running?\n";
        return 0;
    }
}

#
#
#
sub stopscheduler {
    if ( Multigate::scheduler_running() ) {
        Multigate::Scheduler::die();
        print "Stopped scheduler.\n";
        return 1;
    }
    else {
        print "Scheduler not running?\n";
        return 0;
    }
}

#
#
#
sub restartscheduler {
    startscheduler() if stopscheduler();
}

#
#
#
sub stopmultigate {

    # first stop all protcol wrappers
    foreach ( keys %Multigate::registered_wrappers ) {
        Multigate::stop_wrapper($_);
    }

    # then make the scheduler go away..
    if ( Multigate::scheduler_running() ) {
        Multigate::Scheduler::die();
    }

    # the make the mainloop exit..
    $Multigate::exit = 1;
}

#
# Buffer status from NBRead
#
sub bufstat {
    print bufferstatus();
}

1;
