#!/usr/bin/perl -w 
#
# (C) 2000 - 2005 Wieger Opmeer, Casper Joost Eyckelhof, Yvo Brevoort
#
# This package is free software; you can redistribute it and/or modify it
# under the terms of the "Artistic License".
#

#
# Wrapper to handle email for multigate
# Incoming mail is received via procmail and a named pipe
# example procmail rule:
#-----------------------
# :0:
# * Subject: \!.*
# /home/multilink/multigate/modules/email/email.fifo
#-----------------------

use Mail::Mailer;
use IO::Select;
use strict;
use lib 'lib';
use Multigate::Debug;

$| = 1;

my $protocol = "email";
my $fifo     = "wrappers/email/email.fifo";    # where is our fifo?

#
# Checks for valid input and acts accordingly
#
sub process_input {
    my $from_multigate = shift;

    # Is it an outgoing message for us? If so, send it away.
    if ( $from_multigate =~ /OUTGOING $protocol (.*?) (.*)/ ) {
        my $target_address = $1;
        my $target_message = $2;
        send_email( $target_address, $target_message );
    }
    elsif ( $from_multigate =~ /^DIEDIEDIE/ ) {
        exit;
    }

    #Other options not implemented yet...
}

#
# sends email from multigate to an address. The message will be in the body
#
sub send_email {
    my ( $address, $message ) = @_;
    if ( $address !~ /\@/ ) {
        debug( 'email', "Email-Wrapper: Not a valid email address ($address)" );
        return 1;
    }
    $message =~ s/\xb6/\n/g;    #Multiline messages
    my ( $subject, $body ) = split /\n/, $message, 2;    #First line = subject

    my $mailer = Mail::Mailer->new("sendmail");

    $mailer->open(
        {
            From    => 'Multigate <multilink@ringbreak.dnd.utwente.nl>',
            To      => $address,
            Subject => $subject
        }
      )
      or die "Can't open: $!\n";

    print $mailer $message . "\n";
    print $mailer "-- \nThis message was brought to you by Multigate";
    $mailer->close();

    debug( 'email_debug', "Email-Wrapper: sent mail to $address" );
}

unless (-p $fifo) {
   #no fifo available, let's create it ourselves
   require POSIX;
   POSIX::mkfifo($fifo, 0666) or die "unable to create fifo \"$fifo\": $!";
}


open( FIFO, "+< $fifo" ) or die $!;

#select on STDIN and fifo
my $readset = IO::Select->new();
$readset->add( fileno(STDIN) );
$readset->add( fileno(FIFO) );

## Some variables needed in the main program
my $r_ready;
my $ready;
my $exit = 0;
my ( $sender, $message, $readline );
my $newlineseen = 1;
my $newmail     = 1;
my $mailindex   = 0;
my $fromseen    = 0;
my $subjectseen = 0;

while ( !$exit ) {
    ($r_ready) = IO::Select->select( $readset, undef, undef, undef );
    foreach $ready (@$r_ready) {

        #print "ready: $ready\n";
        if ( $ready == fileno(STDIN) ) {
            my $input = <STDIN>;
            chomp $input;
            unless ( defined $input ) {

                #Error with STDIN, parent probably died...
                debug( 'email', "email wrapper going down. (parent died?)" );
                exit 0;
            }
            process_input($input);
        }
        else {    #Something in the FIFO: parse emails.

            #Warning: this is blocking.
            #No problem if procmail delivers entire messages into the fifo

            while ( $readline = <FIFO> ) {
                if ( ($newmail) && ( $readline =~ /^From:(.*?)$/ ) ) {
                    my @fromdingen = split /\s/, $1;
                    $sender = pop @fromdingen;
                    $sender =~ s/[<>]//g;
                    $fromseen = 1;
                }
                elsif ( ($newmail) && ( $readline =~ /^Subject:(.*?)$/ ) ) {
                    $message = $1;
                    $message =~ s/^\s*//;
                    $subjectseen = 1;

                }
                elsif ( $newlineseen && ( $readline =~ /^From / ) ) {
                    $newmail = 1;
                    $mailindex++;
                    debug( 'email_debug', "New Mail ($mailindex)" );
                }

                if ( $subjectseen && $fromseen ) {
                    print "INCOMING email $sender $message\n";

                    #We have seen everything we want. Wait for new mail:
                    $message     = "";
                    $sender      = "";
                    $newlineseen = 0;
                    $newmail     = 0;
                    $fromseen    = 0;
                    $subjectseen = 0;
                }

                #Was the last line (this one..) a newline?
                if ( $readline =~ /^\n/ ) {
                    $newlineseen = 1;
                    last;
                }
                else {
                    $newlineseen = 0;
                }
            }
        }
    }
}
