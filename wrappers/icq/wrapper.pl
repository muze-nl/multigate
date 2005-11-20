#!/usr/bin/perl -w
# (C) 2002 Wieger Opmeer, Casper Joost Eyckelhof, Yvo Brevoort
# Based on code from 'vicq'

use strict;
use lib "lib";
use Multigate::Debug;
use Multigate::NBRead;
use Multigate::Util;

use Net::ICQ2000_Easy;
use IO::Select;
use IO::Handle;

use Multigate::Config qw(readconfig getconf);
readconfig('multi.conf');    # reread config file on wrapper start

my $login = getconf('icq_number');
my $pass  = getconf('icq_pass');

my $icq;
my $details;
my $message;
my $target_uin;
my %Contact_List = ();

Multigate::Debug::setdebug('icq');

sub connect {

    # 1= min connect, 2 = normal (larger, and not needed..)

    debug( 'icq', "Connecting to server using \"$login-$pass\"" );

    $icq = ICQ2000_Easy->new( $login, $pass, "1" );    #Normal multi account
                                                       #$icq = ICQ2000_Easy->new("89081684", "blikkie", "1");   #Backup account

    # Empty contact list, we have users in the multigate database instead of in
    # our own contact list.

    $icq->Setup_Contact_List( \%Contact_List );

    #Auto-ack offline messages.
    $icq->Auto_Ack_Offline_Messages(1);

    # Set debugging value.
    # 0 = non, 1 = ICQ2000_Easy only, 2 = ICQ2000.pm only, 3 = all.
    $icq->Set_Debugging(0);

    # Because the Mods are event driven, we register "Hooks" on certain events,
    # so after the event has occured, the hooked function is run, and the data
    # from the event is passed to the function, so it can do extra things..

    $icq->Add_Hook( "Srv_Mes_Received", \&RecMessage );
    $icq->Add_Hook( "Srv_Srv_Message",  \&SrvMessage );

    #$icq->Add_Hook("Srv_BLM_Contact_Online", \&User_Online);
    #$icq->Add_Hook("Srv_BLM_Contact_Offline", \&User_Offline);
    $icq->Add_Error_Hook( \&General_Error_Notice );

    # Since MOTD is no longer used, use this notice to tell when we've finished
    # logging on.. Eg if u want to have something send as soon as we're online,
    # chuck the command it the function you hook to this command, but be warned,
    # this function is also run whenever the script changes online status (eg to
    # invisible etc..)

    #$icq->Add_Hook("Srv_GSC_User_Info", \&GSC_User_Info);
}

#Catch Ctrl_C etc and die cleanly..
$SIG{INT} = \&disconnect;

#Just exits the program...
sub disconnect {
    debug( 'icq', "Exiting ICQ.." );
    exit(0);
}

# This function will send a "normal" ICQ message to someone..
# Called using Send_Normal_Message(uin, text);
sub Send_Normal_Message {
    $target_uin = shift;
    my $text    = shift;
    my %details = (
        uin  => $target_uin,
        text => $text
    );

    #   print "Target UIN: $target_uin\n";
    #   print "Message:\n$text\n";

    $icq->Send_Command( "Cmd_Mes_Send", \%details );
}

sub DisplayDetails {
    my ( $Object, $details ) = @_;

    foreach ( keys %$details ) {
        print "[$_][$details->{$_}]\n";
    }
    print "\n";
}

sub General_Error_Notice {
    my ( $Object, $ErrID, $ErrMes ) = @_;
    debug( 'icq', "Error [$ErrID] occured : [$ErrMes]" );
}

sub SrvMessage {
    my ( $Object, $details ) = @_;

    #These are responces from the server which r unique to ICQ..

    if ( $details->{Responce_Type} ) {

        #the server is replying to one of our data requests (sending us the ads/update locations..)
        #not strictly needed..

        #$details->{Responce_Type}  - Request message server is responding to..
        #$details->{value}          - Data value returned by server (usally an IP)
    }

    elsif ( $details->{MessageType} eq "Offline_Message" ) {

        #These are the messages that our UIN recieved while we were offline..

        #$details->{deliverable}    - The Time/date the message was sent
        #$details->{Our_UIN}        - Our UIN (not really very useful)
        #$details->{Text}           - The Message Sent
        #$details->{Senders_UIN}    - The Sender's UIN

        $message = $details->{Text};

        # Newline tekens omzetten naar intern multigate newlines.
        $message =~ s/\r\n/\xb6/g;
        $message =~ s/\r/\n/g;
        $message =~ s/\n/\xb6/g;
        print "INCOMING icq " . $details->{Senders_UIN} . " " . $message . "\n";
    }
}

sub RecMessage {
    my ( $Object, $details ) = @_;
    if ( $details->{MessageType} eq "Normal_Message" ) {

        #deal with a normal ICQ message..
        #$details->{Sender}         - Sender's ICQ number
        #$details->{SignOn_Date}    - Sender's Logon Date (in UTC)
        #$details->{Time_Online}    - Sender's Online length of Time (in secs)
        #$details->{Text}           - Sender's message

        $message = $details->{Text};

        # Newline tekens omzetten naar intern multigate newlines.
        $message =~ s/\r\n/\xb6/g;
        $message =~ s/\r/\n/g;
        $message =~ s/\n/\xb6/g;
        print "INCOMING icq " . $details->{Sender} . " " . $message . "\n";
    }

    # Debug info, uncomment if needed.
    #   else {
    #      print "Unknown trans\n";
    #      foreach (keys %$details){
    #         print "[$_][$details->{$_}]\n";
    #      }
    #      print "\n";
    #      print "\n";
    #   }

}

#Takes one (long) line and a maximum line length, and turns it into n shorter lines

sub split_pieces {
    my ( $to_split, $maxlength ) = @_;
    my @hasBeenSplit = ();
    while ( length $to_split > $maxlength ) {
        my $head = substr( $to_split, 0, $maxlength );
        $to_split = substr( $to_split, $maxlength );
        push @hasBeenSplit, $head;
    }
    push @hasBeenSplit, $to_split;
    return @hasBeenSplit;
}

#main Execution loop.. please be carefull what u place in here!!!

&connect;

#select on STDIN, build a readset with only STDIN
my $stdin = new IO::Handle;
$stdin->fdopen( fileno(STDIN), 'r' );
make_non_blocking($stdin);

my $readset = IO::Select->new();
$readset->add($stdin);

my $r_ready;    #to store read_ready filehandles
$| = 1;

my $fh;
my $input;

while (1) {
    $icq->Execute_Once();

    if ( $icq->Connected() ) {
        ($r_ready) = IO::Select->select( $readset, undef, undef, 1 );
        foreach $fh (@$r_ready) {

            #We have someone knocking on STDIN, lets read what it is
            while ( $input = nbread($fh) ) {
                chomp($input);
                if ( $input =~ m/OUTGOING icq (\d+) (.*)/ ) {
                    $target_uin = $1;
                    $message    = $2;
                    $message =~ s/\xb6/\r\n/g;

                    foreach my $piece ( cut_pieces( $message, 400 ) ) {
                        Send_Normal_Message( $target_uin, $piece );
                        sleep 2;    #why can't we send messages closely after eachother?
                    }
                } elsif ( $input =~ m/^DIEDIEDIE/ ) {
                    disconnect();
                }
                unless ( defined $input ) {

                    # $fh has closed... should we do something now?
                }
            }
        }
    } else {
        undef $icq;

        #lets wait for a while 
        sleep 5;
        &connect;
    }
}
