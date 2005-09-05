#!/usr/bin/perl -w 
#
# (C) 2000 - 2005 Wieger Opmeer, Casper Joost Eyckelhof, Yvo Brevoort
#
# This package is free software; you can redistribute it and/or modify it
# under the terms of the "Artistic License".
#

# Basic wrapper part for clients of the Multigate.
# Requires the client to return unbuffered output to work properly
# The following line fixes that part.
# $| = 1;

# The wrapper uses IPC::Open2 to open bidirectional communication to the
# client.

# All clients must return Sender address: <address> and Message text: <text>
# If that is done this wrapper will work.

# Most of the code is from O'Reilly's camel book (Programming perl) and
# modified by Yvo Brevoort.

use FileHandle;
use IPC::Open2;

$| = 1;

# Configuration information. Fill these in with the appropriate settings.
$client_location = "";    # Your client program, full path.
$protocol        = "";    # What is it we are talking.

#declarations
$sender_address = "";
$message_body   = "";
$target_address = "";
$target_message = "";

sub kill_client() {
    close Writer;
    close Reader;
    kill 2, $client_pid;
}

sub start_client() {
    $client_pid = open2( \*Reader, \*Writer, "$client_location" );
    Writer->autoflush();    #This is default, actually.
}

# Install the REAPER to kill the child processes.
# This saves us from having to call in Buffy the Vampire Slayer to go kill
# all the zombies we make.

sub REAPER {
    $waitedpid = wait;
    $SIG{CHLD} = \&REAPER;  # loathe sysV
}
$SIG{CHLD} = \&REAPER;

# Start the client process for reading and writing.

&start_client();

# Messages from the Multigate telling us to send something look like this:
# OUTGOING <protocol> <destination> <message>
# FIXME: fork to make 2 while loops. One for reading from the client, and
# the other one to read from STDIN.

if ( $multigate_pid = fork ) {

    # See if Multigate is telling us anything.
    while (<STDIN>) {
        $from_multigate = $_;

        # Is it an outgoing message for us? If so, send it away.
        if (/OUTGOING $protocol (\d+) (.*)/) {
            $target_address = $1;
            $target_message = $2;
            print Writer "How to talk to the client.";
        }
        if (/$protocol DIE/) {
            print "Got DIE from Multigate. Commiting suicide...\n";
            &kill_client();
            exit 1;
        }
        if (/$protocol RESTART/) {
            print "Got RESTART from Multigate.\n";
            &kill_client();
            &start_client();
        }
    }
}
else {

    # See what the client is telling us, and process the information
    # accordingly.

    while (<Reader>) {
        $readline = $_;

     # When my client receives a message it will return something like this on
     # STDOUT:
     # Sender address: <sender>
     # Message body: <message body>
     # The wrapper will ignore all other lines, leaving us with nothing more but
     # the bare information we want.

        # FIXME: should use a case statement here?

        if (/Sender address: (.*)/) {
            $sender_address = $1;
        }
        if (/Message body: (.*)/) {
            $message_body = $1;
        }

  # At this point we have a sender address and a message text and we will pass
  # this information to the Multigate process using a simple print. The
  # Multigate process receives the information in the same manner as the wrapper
  # does.
        if ( ($sender_address) && ($message_body) ) {
            print "INCOMING $protocol $sender_address $message_body\n";
            $sender_address = "";
            $message_body   = "";
        }
    }

    # FIXME: Filter out all the creepy shell symbols for more security.
    #        Should this be done here?
    # FIXME: Think of a consistent format to communicate with the Multigate
    #        process
}
