#!/usr/bin/perl -w
#
# (C) 2000 - 2005 Wieger Opmeer, Casper Joost Eyckelhof, Yvo Brevoort
#
# This package is free software; you can redistribute it and/or modify it
# under the terms of the "Artistic License".
#
# TODO: scalability issues, like not keeping whole list in memory
#

use strict;

use lib './lib';

use Multigate::Debug;
use IO::Select;
use DateTime;
use Time::ParseDate;

Multigate::Debug::setdebug('scheduler');

#Multigate::Debug::setdebug('scheduler_debug');

$| = 1;    # autoflush!

#
# Globals and such
#
my $multiroot    = $ENV{MULTI_ROOT} or die "\$ENV{MULTI_ROOT} undefined!";
my @events       = ();
my $schedulefile = "$multiroot/logs/events.txt";
my $tempfile     = "$multiroot/logs/events.txt.tmp";

#
# return formatted time for printing in preffered format
#
sub formattedtime {
    my $timestamp = shift;
    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) =
      localtime($timestamp);
    return sprintf(
        '%04d-%02d-%02dT%02d:%02d:%02d',
        $year + 1900,
        $mon + 1, $mday, $hour, $min, $sec
    );
}

#
# Writes current @events to file
#
sub synchronize {
    debug( 'scheduler_debug',
        '------Current list of scheduled events:-------' );
    my $event;
    open( NEW, "> $tempfile" );
    foreach $event (@events) {
        print NEW $event, "\n";
        debug( 'scheduler_debug', $event );
    }
    close NEW;
    rename( $tempfile, $schedulefile )
      or debug( 'scheduler',
        "WARNING: Couldn't rename $tempfile to $schedulefile: $!" );
    debug( 'scheduler_debug', '------End of list-------' );
}

#
# Add an entry to the list of scheduled events if it has an understandable format
# pre:  list is sorted, length = n
# post: list is sorted, length = n+1
# addentry returns success(1) or failure(0)
#
sub addentry {
    my $line = shift;
    my ( $snip_incoming, $protocol, $sender, $org_time, $msg ) = split " ",
      $line, 5;

    #  Check if we have a time specification
    unless ( defined $org_time ) {
        print "TOPROTOCOL $protocol $sender No time specification!\n";
        debug( 'scheduler', "User gave empty time specification" );
        return;
    }

    #  Check if we have a message part
    unless ( defined $msg ) {
        print "TOPROTOCOL $protocol $sender Nothing to do!\n";
        debug( 'scheduler', "User gave empty message" );
        return;
    }

    # Try to parse the time specification

    my $time = $org_time;

    $time =~ s/\./:/g;    # allow use of '.' instead of ':'
    $time =~ s/-/\//g;    # allow use of '-' instead of '/'
    $time =~ s/_/ /g;     # gross hack to introduce spaces
    $time =~ s/T/ /g;     # another gross hack to introduce spaces
    my $timestamp = time;

    # calculate the timestamp for this event
    # assume 2 possibilities:
    # +[[days:]hours:]minutes -> current_time + days:hours:minutes
    # !^+                     -> first occurence of that time from now
    # teatime                 -> first occurence of 16:00

    debug( 'scheduler_debug', "Trying to parse: $time" );

	 if( $time =~ /^teatime$/ ) { # its teatime
		 $time = "16:00";
	 }

    if ( $time =~ /^\s*\+([0-9:]+)\s*$/ ) {    # relative time
        my ( $mn, $hr, $dy, $mo, $yr ) = reverse split /:/, $1;
        my $datetime =
          DateTime->now->set_time_zone('local')->truncate( to => 'minute' );
        $datetime->add(
            years   => ( defined $yr ) ? $yr : 0,
            months  => ( defined $mo ) ? $mo : 0,
            days    => ( defined $dy ) ? $dy : 0,
            hours   => ( defined $hr ) ? $hr : 0,
            minutes => ( defined $mn ) ? $mn : 0,
        );
        $timestamp = $datetime->epoch;
    }
    else {
        $timestamp = parsedate( $time, UK => 1, PREFER_FUTURE => 1 );
        if ( defined $timestamp ) {
            my $datetime =
              DateTime->from_epoch( epoch => $timestamp )
              ->set_time_zone('local');
            if ( $timestamp <= time() ) {
                $datetime->add( days => 1 );
            }
            $timestamp = $datetime->epoch;
        }
    }

    unless ( defined $timestamp ) {
        print
"TOPROTOCOL $protocol $sender Unparsable time specification $org_time\n";
        debug( 'scheduler', "Could not parse input $time ($org_time)" );
        return;
    }

    if ( $timestamp < time ) {
        print "TOPROTOCOL $protocol $sender $org_time is in the past!\n";
        debug( 'scheduler', "User gave time in the past: $time ($org_time)" );
        return;
    }

    # Fixup $msg if it does not begin with a !command
    unless ( $msg =~ /^!/ ) {
        $msg = '!echo ' . $msg;
    }

    # Prepare scheduled_string to add to the list..

    my $scheduled_string = "$timestamp $protocol $sender $msg";

    # And notify the user..

    print "TOPROTOCOL $protocol $sender Scheduled event for ",
      formattedtime($timestamp), "\n";

    # And us..

    debug(
        'scheduler_debug',
        'Scheduled event for ',
        formattedtime($timestamp),
        ' (',
        $timestamp,
        '), now is ',
        formattedtime(time),
        ' (',
        time,
        '). Event in ',
        $timestamp - time,
        ' seconds.'
    );

 # Insert scheduled_string into the list of scheduled events, keeping it sorted!
 # First find insertion point

    my $listcounter = 0;
    my $timestamp_list
      ;  # temporary variable to store timestamps from the scheduled events list
    my $rest;

    foreach $line (@events) {
        ( $timestamp_list, $rest ) = split ' ', $line, 2;
        if ( $timestamp_list <= $timestamp ) {
            $listcounter++;    # Keep on searching
        }
        else {
            last;              # Found insertion point
        }
    }

    # Now we know where to insert our new entry:

    splice @events, $listcounter, 0, $scheduled_string;

    # Write updated @events to file:

    synchronize();

    # All done!
}

#
# Execute all events from the list that have a scheduled timestamp <= now
# Remove those events from the list
# Return the timeout untill the next event
#
sub checkschedule {

    #only check if there are events
    if (@events) {
        my $changes = 0;
        my $now     = time;
        my $timestamp;
        my $rest;
        my $line;
        my $timeout;

   # We know that @events is sorted, find all items that have a timestamp < $now

        foreach $line (@events) {
            ( $timestamp, $rest ) = split ' ', $line, 2;
            $timeout = $timestamp - $now;
            debug( 'scheduler_debug',
"Checking event: ($rest) scheduled in $timestamp - $now = $timeout seconds"
            );
            if ( $timeout <= 0 ) {
                print 'TODISPATCHER ', $rest, "\n";
                debug( 'scheduler_debug', 'Sent to dispatcher: ', $rest );
                $changes++;
            }
            else {
                last;    # exit loop if we're past $now
            }
        }

        # kick first n entries from @events
        splice @events, 0, $changes;

        # write all changes to file if necesarry
        synchronize() if $changes > 0;

        return $timeout;

    }
    else {
        return undef;
    }
}

#
# Main program:
# restore @events from file
#

if ( ( -e $schedulefile ) && ( !-z $schedulefile ) ) {
    open( EVENTS, "< $schedulefile" );
    @events = <EVENTS>;
    close EVENTS;
    chomp @events;
}

debug( 'scheduler', 'Restored ', scalar @events, ' entries from file.' );

#
# for select on STDIN, build a readset with only STDIN
#
my $readset = IO::Select->new();
$readset->add( fileno(STDIN) );
my $r_ready;    # to store read_ready filehandles
my $timeout = checkschedule();

#
# mainloop
#
while (1) {

    debug( 'scheduler_debug', 'Timeout: ',
        ( defined $timeout ) ? $timeout : 'undef' );

    ($r_ready) = IO::Select->select( $readset, undef, undef, $timeout );

    if ($r_ready) {

        # We have someone knocking on STDIN, lets read what it is
        my $line = <STDIN>;
        unless ( defined $line ) {
            debug( 'scheduler', 'Going down. (parent died?)' );
            exit 0;
        }
        chomp($line);

        debug( 'scheduler_debug', 'Reading: ', formattedtime( time() ),
            ' ', $line );
        exit if ( $line eq 'DIEDIEDIE' );    # die without a fuzz

        # add the line to the scheduled list
        addentry($line);

    }
    else {

        # timeout occured
        #debug('scheduler_debug', 'Timeout: ', scalar(localtime) );

    }

    # Now that we are awake, check if something has to be done:
    $timeout = checkschedule();

}

#
# The end
#
