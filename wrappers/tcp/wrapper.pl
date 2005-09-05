#!/usr/bin/perl -w
#
# (C) 2000 - 2005 Wieger Opmeer, Casper Joost Eyckelhof, Yvo Brevoort
#
# This package is free software; you can redistribute it and/or modify it
# under the terms of the "Artistic License".
#
# biclient - bidirectional forking client
#

use strict;
use IO::Socket;

$| = 1;    #autoflush pipes, no buffer

my ( $client_pid, $server_port, $kidpid, $server, $line, $client );

$server_port = 4444;

# TODO: What does Reuse do? why 1 ?
$server = IO::Socket::INET->new(
    LocalPort => $server_port,
    Type      => SOCK_STREAM,
    Reuse     => 1,
    Listen    => 10
  )        # or SOMAXCONN
  or die "Couldn't be a tcp server on port $server_port : $@\n";

$server->autoflush();

while ( $client = $server->accept() ) {
    $client->autoflush();

    # $client is the new connection

    # split the program into two processes, identical twins
    die "can't fork: $!" unless defined( $kidpid = fork() );

    if ($kidpid) {

        # parent copies the socket to standard output
        while ( defined( $line = <$client> ) ) {
            print "INCOMING tcp localuser $line";
        }
        kill( "TERM" => $kidpid );    # send SIGTERM to child
    }
    else {

        # child copies standard input to the socket
        while ( defined( $line = <STDIN> ) ) {
            if ( $line =~ /OUTGOING tcp localuser (.*)/ ) {
                print $client "$1\n";
            }
            else {
                print $client "Troep: $line\n";
            }
        }
    }
}

close($server);
