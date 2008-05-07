#!/usr/bin/perl -w
#
# (C) 2008 Yvo Brevoort
#
# This package is free software; you can redistribute it and/or modify it
# under the terms of the "Artistic License".
#

use strict;

# TCP socket wrapper for Multigate. Listens for tcp clients to connect
# to this and relays the messages to Multigate.

use POSIX;
use IO::Socket;
use IO::Select;
use Socket;
use Fcntl;
use Tie::RefHash;

use lib 'lib';
use Multigate;
use Multigate::Debug;
use Multigate::Config qw(readconfig getconf hasconf);
use Multigate::Users qw(authenticate_user);

Multigate::Debug::setdebug("tcp");
Multigate::Debug::setdebug("tcp_debug");

my $server_port = 30000; # Default port number.
if (hasconf('tcp_port')) {
  $server_port = getconf('tcp_port');
}

# Listen to port.
my $server = IO::Socket::INET->new(
    LocalPort => $server_port,
    Listen    => 50
  )
  or die "Can't make server socket: $@\n";

# begin with empty buffers
my %inbuffer  = ();
my %outbuffer = ();
my %ready     = ();

my %clients = ();
my %users   = ();

tie %ready, 'Tie::RefHash';

nonblock($server);
my $select = IO::Select->new($server);

$select->add( fileno(STDIN) );

# Main loop: check reads/accepts, check writes, check ready to process
while (1) {
    my $client;
    my $rv;
    my $data;

    # check for new information on the connections we have

    # anything to read or accept?
    foreach $client ( $select->can_read(1) ) {

        if ( $client == $server ) {

            # accept a new connection
            debug( "tcp", "Client connecting..." );

            $client = $server->accept();
            $select->add($client);
            nonblock($client);
        }
        elsif ( $client eq fileno(STDIN) ) {
            my $line = <STDIN>;
            chomp $line;
            unless ( defined $line ) {

                #Error with STDIN, parent probably died...
                debug( 'tcp',
                    "TCP wrapper going down. (parent died?)" );
                exit 0;
            }
            if ( $line =~ /OUTGOING tcp (.*?) (.*)/ ) {
                my $username = $1;
                my $rest     = $2;
                if ( defined $users{$username} ) {
                    my $targetclient = $users{$username};
                    print $targetclient "$rest\n";
                }
                else {

                    # Save the message for later use?
                    debug( "tcp",
                        "User $username is not logged on at the moment" );
                }
            }
            elsif ( $line =~ /^DIEDIEDIE/ ) {
                debug( 'tcp', 'tcp wrapper going down.' );
                $server->close();
                exit 0;
            }
        }
        else {

            # read data
            $data = '';
            $rv   = $client->recv( $data, POSIX::BUFSIZ, 0 );

            unless ( defined($rv) && length $data ) {

                # This would be the end of file, so close the client
                delete $inbuffer{$client};
                delete $outbuffer{$client};
                delete $ready{$client};

                $select->remove($client);
                close $client;
                debug( "tcp", "Client left" );
                delete $users{ $clients{$client} };
                delete $clients{$client};
                next;
            }

            $inbuffer{$client} .= $data;

            # test whether the data in the buffer or the data we
            # just read means there is a complete request waiting
            # to be fulfilled.  If there is, set $ready{$client}
            # to the requests waiting to be fulfilled.
            while ( $inbuffer{$client} =~ s/(.*\n)// ) {
                push( @{ $ready{$client} }, $1 );
            }
        }
    }

    # Any complete requests to process?
    foreach $client ( keys %ready ) {
        handle($client);
    }

    # Buffers to flush?
    foreach $client ( $select->can_write(1) ) {

        # Skip this client if we have nothing to say
        next unless exists $outbuffer{$client};

        $rv = $client->send( $outbuffer{$client}, 0 );
        unless ( defined $rv ) {

            # Whine, but move on.
            warn "I was told I could write, but I can't.\n";
            next;
        }
        if ( $rv == length $outbuffer{$client} || $! == POSIX::EWOULDBLOCK ) {
            substr( $outbuffer{$client}, 0, $rv ) = '';
            delete $outbuffer{$client} unless length $outbuffer{$client};
        }
        else {

            # Couldn't write all the data, and it wasn't because
            # it would have blocked.  Shutdown and move on.
            delete $inbuffer{$client};
            delete $outbuffer{$client};
            delete $ready{$client};

            $select->remove($client);
            close($client);
            delete $users{ $clients{$client} };
            delete $clients{$client};
            next;
        }
    }

    # Out of band data?
    foreach $client ( $select->has_exception(0) ) {    # arg is timeout
            # Deal with out-of-band data here, if you want to.
    }
}

sub authenticate {
    my $client  = shift;
    my $request = shift;

    my ( $username, $password ) = split " ", $request;

    Multigate::Users::init_users_module();
    
    if (Multigate::Users::authenticate_user($username, $password)) {
        debug( "tcp", "User $username authenticated" );
        $users{$username} = $client;
        $clients{$client} = $username;
    }
    else {
        debug( "tcp", "Invalid login, disconnecting client" );
        delete $inbuffer{$client};
        delete $outbuffer{$client};
        delete $ready{$client};

        $select->remove($client);
        close($client);
    }
    Multigate::Users::cleanup_users_module();
}

# handle($socket) deals with all pending requests for $client
sub handle {

    # requests are in $ready{$client}
    # send output to $outbuffer{$client}
    my $client = shift;
    my $request;

    foreach $request ( @{ $ready{$client} } ) {

        # $request is the text of the request
        # put text of reply into $outbuffer{$client}
        chomp($request);
        if ( defined $clients{$client} ) {
            my $username = $clients{$client};
            print "INCOMING tcp $username $request\n";
        }
        else {
            #debug( "tcp_debug", "$request" );
            authenticate( $client, $request );
        }
    }
    delete $ready{$client};
}

# nonblock($socket) puts socket into nonblocking mode
sub nonblock {
    my $socket = shift;
    my $flags;

    $flags = fcntl( $socket, F_GETFL, 0 )
      or die "Can't get flags for socket: $!\n";
    fcntl( $socket, F_SETFL, $flags | O_NONBLOCK )
      or die "Can't make socket nonblocking: $!\n";
}

END {
  $server->close();
}
