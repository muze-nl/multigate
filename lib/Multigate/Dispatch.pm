#
# Decide what to do with a message...
#
# (C) 2000 - 2005 Wieger Opmeer, Casper Joost Eyckelhof, Yvo Brevoort
#
# This package is free software; you can redistribute it and/or modify it
# under the terms of the "Artistic License".
#

package Multigate::Dispatch;

use strict;

use vars qw( $VERSION @ISA @EXPORT );

use Exporter;
use Multigate::Debug;
use Multigate::Config;
use Multigate::Scheduler;
use Multigate::Users;
use Multigate::Util;
use Multigate::Accounting;

#use Multigate::CommandSimple;

Multigate::Config::readconfig("multi.conf");
my $simple = getconf('simple_command');

if ($simple) {
    require Multigate::CommandSimple;
    Multigate::CommandSimple->import();
    debug( 'Dispatch', "Using CommandSimple" );
}
else {
    require Multigate::Command;
    Multigate::Command->import();
    debug( 'Dispatch', "Using Command" );
}

@ISA     = qw( Exporter );
@EXPORT  = qw( dispatch_incoming dispatch_outgoing );
$VERSION = '0.02';

#
# Sends message(s) to a protocol, after doing some accounting
#
sub dispatch_outgoing {
    my ( $command_info, $msg ) = @_;

    #all interesting stuff in $command_info
    my $user          = $command_info->{'user'};
    my $protocol      = $command_info->{'to_protocol'};
    my $from_protocol = $command_info->{'from_protocol'};
    my $to_address    = $command_info->{'to_address'};
    my $from_address  = $command_info->{'from_address'};

    my $max_size = getconf('max_message_length');

    my $result = 0;    #was anything actually sent?

    #Save wrappers from "overflows"
    if ( length($msg) > $max_size ) {
        debug( 'Dispatch',
            "Message of size " . length($msg) . " received. Cutting." );
        $msg = substr( $msg, 0, $max_size );
    }

    if ( ref($to_address) ) {

        # do something special
        debug( 'Dispatch_debug', 'Someone called expand with a reference: ',
            caller );
        return;
    }
    else {
        my @msg_chunks;
        debug( 'Dispatch_debug', "TOTAL chunk: $protocol $to_address $msg" );

        init_users_module();

        my $max_prot_size = get_protocol_maxmsgsize($protocol);
        my $accounting    = 1;
        my $balance_ok    = 0;

        if ($max_prot_size) {
            @msg_chunks = cut_pieces( $msg, $max_prot_size );
            my $chunk_count = @msg_chunks;

            #check if user has credits for that number of chunks
            my $prot_balance = get_box( $protocol, $user );
            $balance_ok =
              (      ( defined $prot_balance )
                  && ( $prot_balance >= $chunk_count ) );
        }
        else {    #no max_prot_size --> no accounting neccesary
            push @msg_chunks, $msg;
            $accounting = 0;
            $balance_ok = 1;    # no accounting --> balance is ok :)
        }

        if ($balance_ok) {
            account_log( $protocol, $user, $from_protocol, $from_address,
                time(), $accounting ? scalar(@msg_chunks) : "0",
                "OK", "Dispatch" );
            foreach my $chunk (@msg_chunks) {

                # do not send empty messages!
                if ( $chunk =~ /^\s*$/ ) {
                    debug( 'Dispatch',
                        "Not sending empty msg to $to_address ($protocol)" );
                }
                else {
                    debug( 'Dispatch',
                        "OUTGOING $protocol $to_address $chunk" );
                    if ( Multigate::is_wrapper($protocol) ) {
                        Multigate::write_to_wrapper( $protocol,
                            "OUTGOING $protocol $to_address $chunk" );

                        # Lower balance, if needed
                        if ($accounting) {
                            dec_box( $protocol, $user, 1 );
                        }
                        $result++;    #one more message-chunk actually sent
                    }
                    else {

               #trying to send to non-running or non-existing wrapper. what now?
                        debug( 'Dispatch',
                            "protocol '$protocol' not running? (does it exist?)"
                        );
                    }
                }
            }
        }
        else {

            #user not authorized to send, what's next?
            debug( 'Dispatch',
                "User '$user' has not enough credits for '$protocol'" );
            account_log( $protocol, $user, $from_protocol, $from_address,
                time(), scalar(@msg_chunks), "FAILED", "Dispatch" );
        }
    }
    cleanup_users_module();
    return $result;
}

#
# send a message to a group (also upcall for Command)
# expands group and calls dispatch_outgoing
#
sub groupsend {
    my ( $command_info, $msg ) = @_;

    my $result = 0;    # number of messages sent

    #all interesting stuff in $command_info
    my $groupname     = $command_info->{'groupname'};
    my $from_protocol = $command_info->{'from_protocol'};
    my $from_address  = $command_info->{'from_address'};

    #connect to database
    init_users_module();
    my %addresses =
      get_group_addresses($groupname)
      ;    # $user => (address , protocol) (e.g. titanhead => (981077 , 'icq') )
    cleanup_users_module();

    foreach my $gr_user ( keys %addresses ) {
        my $rcpt     = shift @{ $addresses{$gr_user} };
        my $rcptprot = shift @{ $addresses{$gr_user} };
        $result += dispatch_outgoing(
            {
                'user'          => $gr_user,
                'to_protocol'   => $rcptprot,
                'to_address'    => $rcpt,
                'from_address'  => $from_address,
                'from_protocol' => $from_protocol
            },
            $msg
        );
    }
    return $result;
}

#
# returns the users of a group and their (address, prefprot) given a groupname (or username)
#  user => (address, prefprot)
# FIXME: this function shouldn't be here...
#
sub get_group_addresses {
    my $groupname = shift;

    my %addresses = ();

    init_users_module();

    # first check on username, this overrules groupname

    if ( user_exists($groupname) ) {    # !msg to username?  "followme"
        my $prefprot = get_preferred_protocol($groupname);
        my $fm_address = get_address( $groupname, $prefprot );
        push @{ $addresses{$groupname} }, $fm_address, $prefprot;
        debug( 'Dispatch_group',
            "Added $groupname => ($fm_address , $prefprot) (single user: level "
              . get_userlevel($groupname)
              . ")" );
    }
    else {

        # group -> users , user -> prefpot , user+prot->address
        foreach my $gr_user ( get_group_members($groupname) ) {

          #check if there is an override protocol for this (groupname, username)
            my $prefprot = get_group_protocol( $groupname, $gr_user );
            unless ( defined $prefprot ) {
                $prefprot = get_preferred_protocol($gr_user);
            }
            if ( defined $prefprot ) {
                my $gr_address = get_address( $gr_user, $prefprot );
                push @{ $addresses{$gr_user} }, $gr_address, $prefprot;
                debug( 'Dispatch_group',
                    "Added $gr_user => ($gr_address , $prefprot)" );
            }
        }
    }
    cleanup_users_module();
    return %addresses;
}

#
# Decide what to do with a msg from a wrapper...
#
# Warning: the order in which things are handled is important!
# (!at, !wrapper, !command)

sub dispatch_incoming {
    my $wrapper      = shift;    # wrapper-object of sender
    my $from_address = shift;    # address of sender
    my $msg          = shift;

    # Don't make these global, so the config can change runtime.
    my $atlevel  = getconf('atlevel');     # userlevel needed to use !at
    my $msglevel = getconf('msglevel');    # userlevel needed to use !msg

    my $from_protocol = $wrapper->protocolname();
    my $protocollevel =
      getconf('protocollevel');            # userlevel needed to use !protocol
    my $stripped_sender = stripnick($from_address);
    my $is_multicast    =
      check_multicast( $from_protocol, $from_address );    #logical??

    chomp $msg;

#temporary sanity checking: what to do with internal newlines in INCOMING messages?
    $msg =~ s/\xb6/ /g;

    #connect to database
    init_users_module();

    # realsender is the name we know this user by in our user-database
    my ( $user, $userlevel ) = get_user( $from_protocol, $stripped_sender );
    debug( 'Dispatch',
        "$from_address (is $user) sent using $from_protocol: $msg" );

    #parse message, decide what to do. 4 options: !at, !msg, !protocol, !command

    #Things we already know
    #Although we might change some of them later on :)
    my %command_info = (
        "from_address"  => $from_address,
        "from_protocol" => $from_protocol,
        "is_multicast"  => $is_multicast,
        "user"          => $user,
        "userlevel"     => $userlevel,
        "upcall"        => \&dispatch_outgoing
    );

    my $result;

    #AT
    if (    ( $msg =~ /^!at\s+/i )
        and ( Multigate::scheduler_running() )
        and ( $userlevel >= $atlevel ) )
    {
        $msg =~ s/^(!at\s+)//;    # scheduler doesn't eat !at
        Multigate::Scheduler::schedule( $wrapper, $from_address, $msg );

        # disconnect
        cleanup_users_module();
    }

    #MSG
    elsif ( ( $msg =~ /^!msg\s+(\S+)\s+(.*)$/i )
        and ( $userlevel >= $msglevel ) )
    {

        # !msg is also a bit special...
        my $msgrcpt = $1;
        my $rest    = $2;

        debug( 'Dispatch_group', "MSG: $msgrcpt $rest" );

        my $out;

        # Does this user or group exist?
        if ( user_exists($msgrcpt) or ( group_exists($msgrcpt) ) ) {
            $out = "message will be sent to $msgrcpt.";
        }
        else {

  # no !msg to unknown address, because we don't know the corresponding protocol
            $out = "unknown user or group: $msgrcpt";
            return;
        }
        $result = dispatch_outgoing(
            {
                'user'          => $user,
                'to_protocol'   => $from_protocol,
                'to_address'    => $from_address,
                'from_protocol' => $from_protocol,
                'from_address'  => $from_address
            },
            $out
        );

        # disconnect before spawn...
        cleanup_users_module();

        if ( $rest =~ /^!/ ) {
            $command_info{"to_address"} = "group"
              ;    # Could this introduce a name-conflict somewhere sometime?
            $command_info{"to_protocol"} = "group"
              ;    # Could this introduce a name-conflict somewhere sometime?
            $command_info{"msg"}       = $rest;
            $command_info{"prepend"}   = "<$user:$from_protocol>";
            $command_info{"upcall"}    = \&groupsend;
            $command_info{"groupname"} = $msgrcpt;

            spawn_command( \%command_info );

        }
        else {     #no commands, just redirect
            $result = groupsend(
                {
                    'groupname'     => $msgrcpt,
                    'from_address'  => $from_address,
                    'from_protocol' => $from_protocol
                },
                "<$user:$from_protocol> $rest"
            );
        }
        return;
    }

    #PROTOCOL
    elsif ( ( $msg =~ /^!(\w+)\s+(\S+)\s+(.*)$/i )
        and Multigate::is_wrapper( lc($1) )
        and ( $userlevel >= $protocollevel ) )
    {

        # !<protocol> is also a bit special...

        my $to_protocol = lc($1);
        my $rcpt        = $2;
        my $rest        = $3;

        debug( 'Dispatch_debug', "PROTOCOL: $to_protocol $rcpt $rest\n" );

        my $dest = get_address( $rcpt, $to_protocol );
        my $out;

        if ($dest) {
            $out  = "$to_protocol message will be sent to $rcpt.";
            $rcpt = $dest;
        }
        else {
            $out =
"$to_protocol message will be sent to unknown destination: $rcpt.";
        }

        # recheck multicast
        $is_multicast = check_multicast( $to_protocol, $rcpt );
        $command_info{'is_multicast'} = $is_multicast;

        # disconnect before spawn...
        cleanup_users_module();

        if ( $rest =~ /^!/ ) {
            $command_info{"to_address"}     = $rcpt;
            $command_info{"to_protocol"}    = $to_protocol;
            $command_info{"msg"}            = $rest;
            $command_info{"prepend"}        = "<$user:$from_protocol>";
            $command_info{"notify_success"} = $out;

            spawn_command( \%command_info );
        }
        else {    #no commands, just redirect
            my $success = dispatch_outgoing(
                {
                    'user'          => $user,
                    'to_protocol'   => $to_protocol,
                    'to_address'    => $rcpt,
                    'from_address'  => $from_address,
                    'from_protocol' => $from_protocol
                },
                "<$user:$from_protocol> $rest"
            );
            if ($success) {
                dispatch_outgoing(
                    {
                        'user'          => $user,
                        'to_protocol'   => $from_protocol,
                        'to_address'    => $from_address,
                        'from_address'  => $from_address,
                        'from_protocol' => $from_protocol
                    },
                    $out
                );
            }
        }
        return;
    }

    #COMMAND
    elsif ( $msg =~ /^!/ ) {

        # just do the !<command>s...

        # disconnect before spawn...
        cleanup_users_module();

        $command_info{"to_address"}  = $from_address;
        $command_info{"to_protocol"} = $from_protocol;
        $command_info{"msg"}         = $msg;

        spawn_command( \%command_info );

        return;
    }
    else {
        return;
    }
}

1;
