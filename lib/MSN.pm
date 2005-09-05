package MSN;

use strict;
use warnings;

use Exporter();
use vars qw ($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

$VERSION = 1.3.10;
my $strVERSION = "MSN Module v. 1.3.10";

@ISA         = qw (Exporter);
@EXPORT      = qw ();
@EXPORT_OK   = qw ();
%EXPORT_TAGS = ();

$| = 1;

=head1 NAME

MSN Protocol Connector Version 1.3.10

=head1 DESCRIPTION

MSN protocol connection that creates a simple interface to the MSN protocol

=head1 USAGE

Here is a quick echo bot.

	 use MSN;
	 my $msn = MSN->new(Handle => `email@msn.com`, Password => `secret`);
	 $msn->set_handler(Message	  => \&on_message);
	 $msn->connect();
	 
	 while(1) {
		  $msn->do_one_loop
	 }
	 
	 sub on_message {
		  my ($self, $email, $name, $msg) = @_;
		  $msg =~ s/<(|\n)+?>//g;
		  $self->sendmsg($msg);
	 }

=head1 BUGS

No known bugs at this time.

=head1 CHANGE LOG

Development Updates (currently versioned as 1.3.10) (Mar 20, 2004)
      ejh - rewrote the socket interface completely :) fixed buffering issues
      ejh - rewrote MSG handler to work with new buffers
      wtk - fixed yet more issues with the contact list and adding etc
      ejh - added recording of Group names and GUID's in $msn->{Groups}

Version 1.3.8 (Feb 18, 2004)
      ejh - fixed bug in list sync
      wtk - fixed bug in _add_to_list for MSNP10 (latest)

Version 1.3.7 to 1.3.8 (Feb 7, 2004)
      ehj - massive adding of croak and carp to catch errors
      ejh - moved version info all to one spot, fixed it so you could do 'use MSN 1.3.6' to require a certain version
      ejh - moved all editing of lists to use _add_to_list and _rem_from_list
      ejh - added Error events so clients can respond intellegently
      ejh - fixed unblock to actualy unblock :)
      ejh - converted large if/else to more maintainable methods
      

Version 1.3.6 to 1.3.7 (Jan 31, 2004)

	  wtk - implemented the list code changes we discussed (added private add/rem methods, modified others to use those)
	  wtk - friendly name is now passed to the Connected handler (as per sgf's code)
	  wtk - user and friendly name are now passed to the Update_Chat_Buddies handler
	  wtk - uri_unescape'd anywhere we pass friendly name to a handler (why don't we have to do this with user too??)
	  wtk - call_event now returns the value it gets from the handler (which could be undef)
	  wtk - RNG event now decides whether to answer or not based on the return value of the Ring handler
	  wtk - removed the 2nd argument (self) from all call_event calls, since it was already being passed in
	  wtk - merged the very very small amount of code from Event::Handler directly into this module
	  wtk - Event::Handler is NO LONGER NEEDED

Version 1.3.5 to 1.3.6 (Jan 25, 2004)

	  sgf - added code to allow excessively long messages with sendmsg
	  sgf - added code to make sure name is under 129 characters with set_name
	  sgf - tweaked remcontact/addcontact's multiprotocol support

Version 1.3.4 to 1.3.5 (Jan 25, 2004)

	  wtk - added methods addcontact and remcontact to add/rem items from the FL list (actual contacts list)
	  wtk - added Status sub to example code (shows how to get online/offline contact notifications)
	  ejh - added code to skip some MSGs with Content-Type of application

Version 1.3.3 to 1.3.4 (Jan 13, 2004)

	  ejh - fixed response to BYE. now deletes the socket correctly
	  
Version 1.3.2 to 1.3.3 (Jan 5, 2004)

	  wtk - fixed variable masking warning

Version 1.3.1 to 1.3.2 (Jan 3, 2004)

	  fixed assigning and deleting buddies with JOI and BYE
	  fixed deleting empty sockets
	  fixed password and handle error for new SB session

Version 1.3 to 1.3.1 (Jan 1, 2004)

	 fixed small bug in adding users

Version 1.2.3 to 1.3 (Dec 31, 2003)

	 added isVer and Ver to check which protocol version is in use
	 fixed to run on both MSNP9 and MSNP10 with no code changes
	 added getlist(AL|RL|BL|FL) to return the respective lists.
	 added block and unblock
	 fixed the need for haveing a blank string as first parameter to new.
			 (still accepts it for backwards compatibility) 

Version 1.2.2 to 1.2.3

	 fixed minor error when people left a chat

Version 1.2.1 to 1.2.2

	 Moved over to using carp and croak for user errors
	 Added a checksum to help in the problem solving phases
	 Moved the print for both checksum and version up to where they are always called

=head1 REQUIRMENTS

	 URI::Escape
	 HTTP::Request
	 LWP::UserAgent
	 IO::Socket
	 IO::Select
	 Data::Dumper
	 Digest::MD5
	 LWP::Simple

=cut

#used in authenticate
use URI::Escape;
use HTTP::Request;
use LWP::UserAgent;

#general
use IO::Socket;
use IO::Select;
use Carp;

#debug
use Data::Dumper;

#use Event::Handler;

#used in the challenge phase
use Digest::MD5 qw(md5 md5_hex md5_base64);
use LWP::Simple;

use constant CVER9  => '0x0409 winnt 5.0 i386 MSNMSGR 6.0.0268 MSMSGS ';
use constant CVER10 => '0x0409 winnt 5.0 i386 MSNMSGR 6.1.0203 MSMSGS ';

use constant VER => 'MSNP10 MSNP9 CVR0';

#use constant VER => 'MSNP9 CVR0';
my $VER = 'MSNP10 MSNP9 CVR0';

use constant strMethodOnly => 'Must be called as a method of an MSN object';

sub checksum {
    my $o = tell(DATA);
    seek DATA, 0, 0;
    local $/;
    my $t = unpack( "%32C*", <DATA> ) % 65535;
    seek DATA, $o, 0;
    return $t;
}

#print $strVERSION . "\nChecksum:" . checksum() . "\n\n";

my $Select = IO::Select->new();

=head1 METHODS (Common)

=head2 new

To create a normal connection

	 my $msn = MSN->new(Handle => $Email,
							  Password => $Password);

if you want to connect to a different host or port

	 my $msn = MSN->new( Handle	=> $Email,
								Password => $Password,
								Host		=> 'messenger.hotmail.com',
								Port		=> 1863
							 );								  

Other options include Debug (0 by defualt)

=cut

sub new {
    my $proto = shift;
    my $type  = shift || "";

    if ( $type ne "" && $type ne "SB" ) { unshift( @_, $type ) }

    my $class = ref($proto) || $proto;
    my $self = {
        Calls => {},
        Host  => 'messenger.hotmail.com',
        Port  => 1863,
        Debug => 0,
        Type  => 'NS',
        @_
    };

    if ( $self->{Type} eq 'NS' ) {
        $self->{handler} = {};
    }

    unless ( ( $self->{Type} eq "NS" ) && $self->{Handle} && $self->{Password}
        || $self->{Type} eq "SB" )
    {
        croak
          "Cannont create object without both Handle and Password being set.\n";
    }

    bless( $self, $class );

    return $self;
}

=head2 connect

Takes no arguments at all.  Initiates the connect;

	 $msn->connect();

=cut

sub connect {

    # added as wrapper for connect by Eric H. Oct 23
    my $self = shift || croak(strMethodOnly);

    # Create the socket and add to the Select object.

    $self->{Socket} = IO::Socket::INET->new(
        PeerAddr => $self->{Host},
        PeerPort => $self->{Port},
        Proto    => 'tcp'
      )
      or croak "Connection error: $!";

    #$self->{Socket}->autoflush(1);
    #$self->{Socket}->blocking(0);
    $Select->add( $self->{Socket} );
    $self->GetMaster->{Socks}->{ $self->{Socket}->fileno } = $self;

    # Kick off the conversation!!!
    $self->send( 'VER', VER );    # Get version info

}

=head2 do_one_loop

Runs a single round of listening to all sockets for communitcation.

Should be called shortly after connect() in a loop.

	 while(1) {
		  $msn->do_one_loop
	 }

=head2 set_name

Sets your display name.
returns 1 on success, 0 on error

	 $msn->set_name("Dude");

=cut

sub set_name {
    my $self    = shift || croak(strMethodOnly);
    my $newName = shift || carp("Must be passed new name.");

    my $Master = $self->GetMaster();

    unless ( length $newName <= 129 ) {
        carp "Display name to long to set";
        return 0;
    }

    $newName = uri_escape($newName);

    $Master->send( 'PRP', 'MFN ' . $newName ) if $self->isVer('MSNP10');
    $Master->send( 'REA', $Master->{Handle} . ' ' . $newName )
      if $self->isVer('MSNP9');

    return 1;
}

=head2 Ver

Returns the protocol version currently being used to communicate with the MSN servers

#	 print "Using " . $self->Ver() . "\n";

=cut

sub Ver {
    my $self = shift || croak(strMethodOnly);
    return $self->GetMaster->{protocol};
}

=head2 isVer

Checks the version microsoft is using so you can act accordingly. this way if you are using MSNP10 specific commands they don't break if it goes back to MSNP9 for a week.

	 $self->set_name("They are on MSNP10") if $self->isVer('MSNP10');
	 
although this may not provide a lot of functionality at the moment it may be key later on.

=cut

sub isVer {
    my $self = shift || croak(strMethodOnly);
    my $version = shift
      || ( carp("Must pass a version to check") and return 0 );
    return ( $self->Ver() eq $version );
}

=head2 set_status

Sets your away status.

	 $msn->set_status("NLN");

=cut

sub set_status {
    my $self   = shift || croak(strMethodOnly);
    my $status = shift || 'NLN';
    $self->GetMaster->send( 'CHG', $status );
}

=head2 Handling Events

=head3 set_handler

Sets a handler for an event.  Takes the event name followed by a code ref

	 $msn->set_handler(Connected => \&Connected);

=cut

sub set_handler {
    my $self = shift || croak(strMethodOnly);
    my ( $event, $handler ) = @_;

    # handles internal representation of events.
    # can be overiden but its not likely to be neccessary
    return $self->{handler}->{$event} = $handler;
}

=head3 set_handlers

Sets multiple handlers in a single call.  Takes a hash of "Event" => &handler.

	 $msn->set_handlers(Connected => \&Connected,
							  Message => \&Message);

=cut

=head3 Events

=item Log($msg)

anytime the module wants to log something

=item Disconnected()

when all sockets are closed

=item Connected()

after 'OK NS' recieved

=item Join($user,$friendly) 

when JOI is recieved

=item Update_Chat_Buddies()

when IRO is recieved

=item Chat_Buddy_Left() 

when BYE is revieved

=item Chat_Room_Closed() 

when last buddy leaves a conversation

=item Status($username,$status)

=item Ring($user,$friendly)

when somebody rings you (RNG)

=item Answer()

when ANS is recieved

=item Typing($user,$friendly)

when Typeing message is sent to you

=item Message($user,$friendly,$msg)

when Message is sent to you

=item SystemMessage($user,$friendly,$msg)

when message is send to the NF isntead of SB

=item Uknown_Command($cmd,@data)

when an unhandled even comes in

=cut

sub set_handlers {
    my $self = shift || croak(strMethodOnly);
    my $handlers = {@_};
    for my $event ( keys %$handlers ) {
        $self->set_handler( $event, $handlers->{$event} );
    }
}

sub call_event {
    my $self  = shift || croak(strMethodOnly);
    my $event = shift;

    my $function = $self->GetMaster->{handler}->{$event};

    #print "EVENT: $event\n" unless $event eq 'Log';

    return &$function( $self, @_ ) if ( defined $function );

    # there never was a default handler setup
    # we might want to actually implement this
    #	  $function = $self->{default};
    #	  return &$function(@_) if (defined $function);

    return undef;
}

sub get_events {
    my $self = shift || croak(strMethodOnly);
    return sort keys %{ $self->GetMaster->{handler} };
}

=head2 getlist

Gets a list of names on a specific list (RL,BL,AL,FL)

	  print @{$self->getlist("RL")};			 # print out the RL list
	  
	  print scalar @{$self->getlist("FL")); # print out how many people have added this bot

=cut

sub getlist {
    my $self = shift || croak(strMethodOnly);
    my $list = shift || carp("You must specify a list to check");
    unless ( exists $self->GetMaster->{Lists}->{$list} ) {
        carp "That list does not exists. Please try RL,BL,AL or FL";
    }

    return keys %{ $self->GetMaster->{Lists}->{$list} };
}

=head2 sendmsg

Sends a message to the current conversation.
Has a simple form

	 $self->sendmsg("message here");

and a more complex form

	 $self->sendmsg("message here",Font => "Arial", Color => '00ff00');

The complex form supports

	 Font
	 Color
	 Effect
	 CharacterSet
	 PitchFamily

=cut

sub sendmsg {
    my $self     = shift || croak(strMethodOnly);
    my $response = shift || carp("You must pass the message you want to send");
    my $settings = {
        Font         => "MS%20Shell%20Dlg",
        Effect       => "B",
        Color        => "000000",
        CharacterSet => 0,
        PitchFamily  => 0,
        @_
    };
    $settings->{Font} = uri_escape( $settings->{Font} );

    while ( $response =~ /(.{1,1400})/gs ) {
        my $message = $1;
        if ( length $message ) {
            my $header =
                qq{MIME-Version: 1.0\nContent-Type: text/plain; charset=UTF-8\n}
              . qq{X-MMS-IM-Format: FN=$settings->{Font}; EF=$settings->{Effect}; }
              . qq{CO=$settings->{Color}; CS=$settings->{CharacterSet}; }
              . qq{PF=$settings->{PitchFamily}\n\n};

            $header .= $message;
            $header =~ s/\n/\r\n/gs;
            $self->sendraw( 'MSG', 'U ' . length($header) . "\r\n" . $header );
        }
    }
}

=head2 call

calls the user, waits for them to join and then sends them the attached message (if you send it)

	 $msn->call("user@wherever.com");

or

	 $msg->call("user@whereever.com","your a dork");

=cut

sub call {
    my $self = shift || croak(strMethodOnly);
    my $handle = shift
      || carp("Need to send the handle of the person you call") && return;
    my $message = shift;

    $self->send( 'XFR', 'SB' );    # try to get a new SwitchBoard??
    my $TrID = $self->GetMaster->{TrID} - 1;
    $self->GetMaster->{Calls}->{$TrID}->{Handle} = $handle
      ; # add this call to the list of pending calls for when i get to a switch board?
    $self->GetMaster->{Calls}->{$TrID}->{Message} = $message
      ; # add this call to the list of pending calls for when i get to a switch board?
}

=head2 invite

Invites someone into a current conversation

	 $self->invite("you@here.com");

That would invite user you@here.com into the conversation that $self refers to

=cut

sub invite {
    my $self   = shift || croak(strMethodOnly);
    my $handle = shift || carp("Need a handle to invite") && return;

    if ( $self->{Type} ne 'NS' ) {
        $self->send( 'CAL', $handle );
        return 1;
    }
    else {
        carp "invite can only be called in a SB";
        return 0;
    }

}

sub leave {
    my $self = shift || croak(strMethodOnly);
    $self->sendrawnoid("OUT\r\n");
    return 1;
}

=head2 sendtyping

Sends the message telling the current conversation that you are typing a message.

	 $self->sendtyping

=cut

sub sendtyping {
    my $self = shift || croak(strMethodOnly);
    my $header =
        qq{MIME-Version: 1.0\nContent-Type: text/x-msmsgscontrol\nTypingUser: }
      . $self->GetMaster->{Handle}
      . qq{\n\n\n};
    $header =~ s/\n/\r\n/gs;
    $self->sendraw( 'MSG', 'N ' . length($header) . "\r\n" . $header );
    return 1;
}

# GetMaster goes up the tree to get the base object

sub GetMaster {
    my $self = shift || croak(strMethodOnly);
    return $self->{_Master}->GetMaster if ( defined $self->{_Master} );
    return $self;
}

sub _send {
    my $self = shift || croak(strMethodOnly);
    my $msg  = shift || carp("No message specified") && return;

    # Send the data to the socket.
    $self->{Socket}->print($msg);
    chomp($msg);

    my $fn = $self->{Socket}->fileno;
    $self->writelog("($fn $self->{Type}) TX: $msg");

    return length($msg);
}

=head2 block

Blocks the user by removing them from the AL list and adding them to the BL list.
returns 1 on success, 0 on error

	 $msn->block('eric256@rocketmail.com');

=cut

sub block {
    my $self  = shift || croak(strMethodOnly);
    my $email = shift || carp("Need an email address to block") && return;

    $self->_rem_from_list( 'AL', $email ) || return 0;
    return $self->_add_to_list( 'BL', $email );
}

=head2 unblock

unBlocks the user by removing them from the BL list and adding them to the AL list.
returns 1 on success, 0 on error

	 $msn->unblock('eric256@rocketmail.com');

=cut

sub unblock {
    my $self  = shift || croak(strMethodOnly);
    my $email = shift || carp("Need an email address to unblock") && return;

    $self->_rem_from_list( 'BL', $email ) || return 0;
    return $self->_add_to_list( 'AL', $email );
}

=head2 addcontact

adds the contact to the FL list, which is MSNs contact list.
returns 1 on success, 0 on error

	 $msn->addcontact('eric256@rocketmail.com');

=cut

sub addcontact {
    my $self  = shift || croak(strMethodOnly);
    my $email = shift || carp("Need an email address to add") && return;

    print("**** adding contact $email to FL list\n");

    return $self->_add_to_list( 'FL', $email );

    my $client = $self->GetMaster();
    $client->{Lists}->{'FL'}->{$email} = 1;
    my $GUID = $client->{Groups}->{'Friends'};
    $client->send( "ADC",
        "FL N=$email F=$email $self->{'Groups'}->{'Friends'}" )
      if $self->isVer('MSNP10');
    $client->send( "ADD", "FL $email $email 1" ) if $self->isVer('MSNP9');

    return 1;
}

=head2 remcontact

removes the contact to the FL list, which is MSNs contact list.
returns 1 on success, 0 on error

	 $msn->remcontact('eric256@rocketmail.com');

=cut

sub remcontact {
    my $self  = shift || croak(strMethodOnly);
    my $email = shift || carp("Need an email address to remove") && return;

    print("**** removing contact $email from FL list\n");

    #  return $self->_rem_from_list('FL', $email);

    my $client = $self->GetMaster();
    delete $client->{Lists}->{'FL'}->{$email};
    my $GUID = $client->{Groups}->{Friends};
    $client->send( "REM", "FL $email $self->{'Groups'}->{'Friends'}" );
    return 1;
}

sub _add_to_list {
    my $self  = shift || croak(strMethodOnly);
    my $list  = shift || carp("Need a list to add the person to") && return;
    my $email = shift || carp("Need an email address to add") && return;

    my $client = $self->GetMaster();

    $client->{Lists}->{$list}->{$email} = 1;
    $client->send( "ADC", "$list N=$email" )
      if $self->isVer('MSNP10')
      and ( $list eq 'AL' );
    $client->send( "ADC", "$list N=$email F=$email" )
      if $self->isVer('MSNP10')
      and ( $list ne 'AL' );
    $client->send( "ADD", "$list $email $email" ) if $self->isVer('MSNP9');

    return 1;
}

sub _rem_from_list {
    my $self = shift || croak(strMethodOnly);
    my $list = shift || carp("Need a list to remove the person from") && return;
    my $email = shift || carp("Need an email address to remove") && return;

    my $client = $self->GetMaster();

    delete $client->{Lists}->{$list}->{$email};
    $client->send( "REM", "$list $email" );
    return 1;
}

=head1 METHODS (Specialized)

In general these methods should be left alone.  If you do use these then you are on your own when the protocols changes.

=head2 send

Sends a message to MSN adding Transaction ID's and new lines. (it is recommended that you DO NOT use this method)

	 $msn->send("CHG","NLN");

=cut

sub send {
    my $self = shift || croak(strMethodOnly);
    my $cmd = shift || ( carp("No command specified to send") && return );
    my $data = shift;

    # Generate TrID using global TrID value...
    my $datagram =
      $cmd . ' ' . $self->GetMaster->{TrID}++ . ' ' . $data . "\r\n";
    return $self->_send($datagram);
}

=head2 sendraw

Sends the message/command adding Transaction IDs but no newline. (not recommended for use)

	 $self->sendraw("CHG","NLN\r\n");

=cut

sub sendraw {
    my $self = shift || croak(strMethodOnly);
    my $cmd = shift || carp("No command specified to send") && return;
    my $data = shift;

    # same as send without the "\r\n"

    my $datagram = $cmd . ' ' . $self->GetMaster->{TrID}++ . ' ' . $data;
    return $self->_send($datagram);
}

=head2 sendrawnoid

Sends the message/command just as they are. You need to include any transaction ids and line ends. (not recommended for use)

	 $self->sendrawnoid("CHG","1 NLN\r\n");

=cut

sub sendrawnoid {
    my $self = shift || croak(strMethodOnly);
    my $cmd = shift || carp("No command specified to send") && return;
    my $data = shift;

    my $datagram = $cmd . ' ' . $data;
    return $self->_send($datagram);
}

sub writelog {
    my $self = shift || croak(strMethodOnly);
    my $msg  = shift || carp("No message passed") && return;

    $self->call_event( "Log", $msg ) if ( $self->GetMaster->{Debug} );
    return 1;
}

sub buddyadd {
    my $self     = shift || croak(strMethodOnly);
    my $username = shift || carp("No username given to add") && return;
    my $fname    = shift || carp("No friendly name given") && return;

    $self->{Buddies}->{$username}->{FName} = $fname;

    unless ( defined( $self->{Buddies}->{$username}->{Status} ) ) {
        $self->{Buddies}->{$username}->{Status}     = 'NONE';
        $self->{Buddies}->{$username}->{LastChange} = time;
    }
    return 1;
}

sub buddyname {
    my $self = shift || croak(strMethodOnly);
    my $username = shift || carp("No username given.") && return;
    return $self->{Buddies}->{$username}->{FName};
}

sub buddystatus {
    my $self     = shift || croak(strMethodOnly);
    my $username = shift || carp("No username given to add") && return;

    my $status = shift;

    if ($status) {
        $self->call_event( "Status", $username, $status );
        $self->{Buddies}->{$username}->{Status}     = $status;
        $self->{Buddies}->{$username}->{LastChange} = time;
    }

    return $self->{Buddies}->{$username}->{Status};
}

sub do_one_loop {
    my $self = shift || croak(strMethodOnly);
    my $fh;

    my @ready = $Select->can_read(.1);
    foreach $fh (@ready) {

        my $fn   = $fh->fileno;
        my $self = $self->GetMaster->{Socks}->{$fn};
        unless ( $self->{Socket}->connected() ) {
            $Select->remove( $self->{Socket}->fileno() );
            delete( $self->GetMaster->{Socks}->{ $self->{fn} } );
            warn "Killing dead socket";
            next;
        }

        sysread( $fh, $self->{buf}, 2048, length( $self->{buf} || '' ) );
        {
            while ( $self->{buf} =~ s#^(.*?\n)## ) {
                $self->{line} = $1;
                $_ = $self->{line};

                $self->{fn} = $fn;
                $self->{fh} = $fh;

                #my $self = $fh->{_parent};

                s/[\r\n]//g;

                my $incomingdata = $_;

                $self->writelog("($fn $self->{Type}) RX: $_");

                my ( $cmd, @data ) = split( / /, $_ );

                my $c = "CMD_" . $cmd;

                if ( exists &{$c} ) {
                    no strict 'refs';
                    &{$c}( $self, @data );
                }
                elsif ( $cmd =~ /[0-9]+/ ) {
                    $self->call_event( "Error", $cmd, @data );
                    $self->writelog( "ERROR: " . converterror($cmd) );
                }
                else {
                    $self->call_event( "Unknown_Command", $cmd, @data );
                    $self->writelog("RECIEVED UNKNOWN: $cmd @data\n\n");
                }

            }
        }
    }
}

sub CMD_VER {
    my $self = shift || croak(strMethodOnly);
    my @data = @_;
    $self->{protocol} = $data[1];
    $self->send( 'CVR', CVER10 . $self->{Handle} ) if $self->isVer('MSNP10');
    $self->send( 'CVR', CVER9 . $self->{Handle} )  if $self->isVer('MSNP9');
    return 1;
}

sub CMD_CVR {
    my $self = shift || croak(strMethodOnly);
    my @data = @_;
    $self->send( 'USR', 'TWN I ' . $self->{Handle} );
    return 1;
}

sub CMD_USR {
    my $self = shift || croak(strMethodOnly);
    my @data = @_;
    if ( $data[1] eq 'TWN' && $data[2] eq 'S' ) {
        my $token = $self->authenticate( $data[3] );
        $self->send( 'USR', 'TWN S ' . $token );
    }
    elsif ( $data[1] eq 'OK' ) {
        if ( $self->{Type} eq "NS" ) {
            my $friendly = $data[3];
            $self->send( 'SYN', "0 0" ) if $self->isVer('MSNP10');
            $self->send( 'SYN', "0" )   if $self->isVer('MSNP9');
        }
        if ( defined $self->GetMaster->{Calls}->{ $self->{TrID} } ) {
            $self->send( 'CAL',
                $self->GetMaster->{Calls}->{ $self->{TrID} }->{Handle} );
        }
    }
    else {
        croak 'Unsupported authentication method: "' . "@data" . '"\n';
    }
}

sub CMD_XFR {
    my $self = shift || croak(strMethodOnly);
    my @data = @_;

    if ( $data[1] eq 'NS' ) {
        my ( $Host, $Port ) = split( /:/, $data[2] );
        $self->{Socket}->close();
        $Select->remove( $self->{Socket} );
        if ( defined $self->{Socket}->fileno ) {
            delete( $self->GetMaster->{Socks}->{ $self->{Socket}->fileno } );
        }
        $self->{Socket} = IO::Socket::INET->new(
            PeerAddr => $Host,
            PeerPort => $Port || 1863,
            Proto    => 'tcp'
          )
          or croak "$!";
        $Select->add( $self->{Socket} );
        $self->GetMaster->{Socks}->{ $self->{Socket}->fileno } = $self;
        $self->send( 'VER', VER );
    }
    elsif ( $data[1] eq 'SB' ) {
        if ( defined $self->GetMaster->{Calls}->{ $data[0] }->{Handle} ) {
            my ( $Host, $Port ) = split( /:/, $data[2] );
            my $session = MSN->new( Type => 'SB' );
            $session->{Socket} = IO::Socket::INET->new(
                PeerAddr => $Host,
                PeerPort => $Port || 1863,
                Proto    => 'tcp'
              )
              or croak "$!";

            # Add the new connection to the Select structure.
            $Select->add( $session->{Socket} );
            $self->GetMaster->{Socks}->{ $session->{Socket}->fileno } =
              $session;
            $session->{_Master}  = $self;
            $session->{Key}      = $data[4];
            $session->{TrID}     = $data[0];
            $session->{_message} =
              $self->GetMaster->{Calls}->{ $data[0] }->{Message};
            $session->{Type}   = 'SB';
            $session->{Handle} =
              $self->GetMaster->{Calls}->{ $data[0] }->{Handle};
            $session->send( 'USR',
                $self->GetMaster->{Handle} . ' ' . $data[4] );
            $self->{Sessions}
              ->{ $self->GetMaster->{Calls}->{ $data[0] }->{Handle} } =
              $session;
        }
        else {
            croak
              "Huh? Recieved XFR SB request, but there are no pending calls!\n";
        }
    }
}

sub CMD_JOI {
    my $self = shift || croak(strMethodOnly);
    my ( $user, $friendly ) = @_;
    if ( $self->{_message} ) {
        $self->sendmsg("$self->{_message}");
        delete $self->{_message};
    }
    $self->{Buddies}->{$user} = $friendly;
    $self->call_event( "Join", $user, uri_unescape($friendly) );
}

sub CMD_IRO {
    my $self = shift || croak(strMethodOnly);
    my ( undef, $current, $total, $user, $friendly ) = @_;
    $self->{Buddies}->{$user} = $friendly;
    if ( $current == $total ) {
        $self->call_event( "Update_Chat_Buddies", $user,
            uri_unescape($friendly) );
    }
}

sub CMD_BYE {
    my $self = shift || croak(strMethodOnly);
    my ($user) = @_;
    delete $self->{Buddies}->{$user} if $self->{Buddies}->{$user};
    $self->call_event( "Chat_Buddy_Left", $user );
    unless ( keys %{ $self->{Buddies} } ) {
        $self->call_event("Chat_Room_Closed");
        $Select->remove( $self->{Socket}->fileno() );
        delete( $self->GetMaster->{Socks}->{ $self->{fn} } );
        delete( $self->GetMaster->{Sessions}->{$user} );
        undef $self;
    }
}

sub CMD_RNG {
    my $self = shift || croak(strMethodOnly);
    my ( $sid, $addr, undef, $key, $user, $friendly ) = @_;

    my $do_accept = $self->call_event( "Ring", $user, uri_unescape($friendly) );

    # for backwards compatibility (if no handler installed for Ring)
    $do_accept = 1 if ( !defined $do_accept );

    if ($do_accept) {
        my ( $Host, $Port ) = split( /:/, $addr );

        # 1. parse the call
        # 2. create a session to track it
        # 3. create a new msn object for that session .... why?
        # 4. connect the socket to the given address and respond.
        # 5. save relevante info in the Session and send the Reply.

        #temp kludge for readabilaty
        my $session = $self->{Sessions}->{$user};

        $session =
          MSN->new( Type => 'SB' )
          ;    # create new MSN module to handle it .... why?

        #open socket up to it.
        $session->{Socket} = IO::Socket::INET->new(
            PeerAddr => $Host,    # local host
            PeerPort => $Port,    # global port
            Proto    => 'tcp'
          )
          or croak "$!";

        # add that to the list of sockets to watch
        $Select->add( $session->{Socket} );

        # store a ref to that socket so we can get it later.....why?
        $self->GetMaster->{Socks}->{ $session->{Socket}->fileno } = $session;
        $session->{_Master}                                       = $self;
        $session->{Key}                                           = $key;
        $session->{Handle}                                        = $user;
        $session->send( 'ANS', $self->GetMaster->{Handle} . " $key $sid" );
    }
}

sub CMD_ANS {
    my $self = shift || croak(strMethodOnly);
    my ($response) = @_;
    $self->call_event("Answer");
}

sub CMD_MSG {
    my $self = shift || croak(strMethodOnly);
    my ( $user, $friendly, $length ) = @_;

    my $response;
    my $msg;
    my $header;

    if ( length( $self->{buf} ) < $length ) {
        $self->{buf} = $self->{line} . $self->{buf};
        return;
    }

    #$self->{fh}->read( $msg, $length );
    $msg = substr( $self->{buf}, 0, $length, "" );
    ( $header, $msg ) = _strip_header($msg);
    if ( $self->{Type} eq 'SB' ) {
        if ( $header->{'Content-Type'} =~ /text\/x-msmsgscontrol/ ) {
            $self->call_event( "Typing", $user, uri_unescape($friendly) );
        }
        elsif ( $header->{'Content-Type'} =~ /text\/x-msmsgsinvite/ ) {
            my $settings = { map { split( /\: /, $_ ) } split( /\n/, $msg ) };
            if (   $settings->{'Invitation-Command'} eq "INVITE"
                && $settings->{'Application-Name'} eq "File Transfer" )
            {
                $self->call_event(
                    "FileRecieveInvitation",
                    $user,
                    uri_unescape($friendly),
                    $settings->{'Invitation-Cookie'},
                    $settings->{'Application-File'},
                    $settings->{'Application-FileSize'}
                );
            }

            # other....
        }
        elsif ( $header->{'Content-Type'} =~ /application\/x-msnmsgrp2p/ ) {
        }
        elsif ( $header->{'Content-Type'} =~
            /application\/x-msnmsgr-sessionreqbody/ )
        {
        }
        else {    # regular hopefully
            $self->call_event( "Message", $user, $friendly, $msg );
        }
    }
    else {
        $self->call_event( "SystemMessage", $user, $friendly, $msg );
    }
}

sub CMD_NLN {
    my $self = shift || croak(strMethodOnly);
    my @data = @_;
    $self->buddystatus( $data[1], $data[0] );
}

sub CMD_ILN {
    my $self = shift || croak(strMethodOnly);
    my @data = @_;
    $self->buddystatus( $data[2], $data[1] );
}

sub CMD_FLN {
    my $self = shift || croak(strMethodOnly);
    my @data = @_;
    $self->buddystatus( $data[0], 'FLN' );
}

sub CMD_ADC {
    my $self = shift || croak(strMethodOnly);
    my ( $TrID, $list, $handle, $name ) = @_;
    ( undef, $handle ) = split( /=/, $handle ) if $self->isVer('MSNP10');

    #	$self->_add_to_list( 'AL', $handle);
}

sub CMD_ADD {
    my $self = shift || croak(strMethodOnly);
    my ( $TrID, $list, $listversion, $handle, $name ) = @_;
    ( undef, $handle ) = split( /=/, $handle ) if $self->isVer('MSNP10');
    $self->_add_to_list( 'AL', $handle );
}

sub CMD_CHL {
    my $self   = shift || croak(strMethodOnly);
    my @data   = @_;
    my $digest = md5_hex( $data[1] . 'JXQ6J@TUOGYV@N0M' );
    $self->sendraw( 'QRY', 'PROD0061VRRZH@4F 32' . "\r\n" . $digest );
}

sub CMD_GTC {
    my $self = shift || croak(strMethodOnly);
    my @data = @_;
    if ( $data[0] eq 'A' ) {
        $self->writelog( "ACK! Your account requires confirmation for "
              . "people to add you to their contact lists. "
              . "We'll fix that.\n\n" );
        $self->send( 'GTC', 'N' );
    }
}

sub CMD_BLP {
    my $self = shift || croak(strMethodOnly);
    my @data = @_;
    if ( $data[0] eq 'BL' ) {
        $self->writelog( "ACK! Your account doesn't allow unknown people "
              . "to contact you. We'll fix that.\n\n" );
        $self->send( 'BLP', 'AL' );
    }
}

sub CMD_CAL {
    my $self = shift || croak(strMethodOnly);
    my @data = @_;
}

sub CMD_CHG {
    my $self = shift || croak(strMethodOnly);
    my @data = @_;
}

sub CMD_QRY {
    my $self = shift || croak(strMethodOnly);
    my @data = @_;
}

sub CMD_BPR {
    my $self = shift || croak(strMethodOnly);
    my @data = @_;
}

sub CMD_REA {
    my $self = shift || croak(strMethodOnly);
    my @data = @_;
}

sub CMD_LSG {
    my $self = shift || croak(strMethodOnly);
    my ( $group, $guid ) = @_;

    #print( "Group Listing - " . join( " ", @_ ) . "\n" );
    $self->{Groups}->{$group} = $guid;
}

sub CMD_SYN {
    my $self = shift || croak(strMethodOnly);
    my @data = @_;
    $self->{Lists}->{SYN}->{Total} = $data[3] if $self->isVer('MSNP10');
    $self->{Lists}->{SYN}->{Total} = $data[2] if $self->isVer('MSNP9');

    $self->writelog(
        "SYN'd Successfully Total Contacts\: $self->{Lists}->{SYN}->{Total}\n\n"
    );
}

sub CMD_OUT {
    my $self = shift || croak(strMethodOnly);
    die "MSoft sent use OUT so we gotta go for now.";
}

sub CMD_LST {
    my $self = shift || croak(strMethodOnly);
    my @data = @_;

    my ( $email, $friendly, $c, $bitmask, $group );
    ( $email, $friendly, $bitmask, $group ) = @data if $self->isVer('MSNP9');

    if ( $self->isVer('MSNP10') ) {
        my @temp = @data;
        $bitmask = pop @temp;
        if ( $bitmask =~ /[a-z]/ ) {
            $group   = $bitmask;
            $bitmask = pop @temp;
        }
        my $values = {};
        foreach my $t (@temp) {
            my ( $key, $value ) = split( /=/, $t );
            $values->{$key} = $value;
        }
        $friendly = $values->{F};
        $email    = $values->{N};
    }

    $self->{Lists}->{SYN}->{Current}++;

    my $current = $self->{Lists}->{SYN}->{Current};
    my $total   = $self->{Lists}->{SYN}->{Total};

    $self->{Lists}->{RL}->{$email} = 1 if ( $bitmask & 8 );
    $self->{Lists}->{BL}->{$email} = 1 if ( $bitmask & 4 );
    $self->{Lists}->{AL}->{$email} = 1 if ( $bitmask & 2 );
    $self->{Lists}->{FL}->{$email} = 1 if ( $bitmask & 1 );
    if ( $current == $total ) {
        my $RL = $self->{Lists}->{RL};
        my $AL = $self->{Lists}->{AL};
        my $BL = $self->{Lists}->{BL};

        foreach my $key ( keys %$RL ) {
            if ( !defined $AL->{$key} && !defined $BL->{$key} ) {
                $self->writelog(
                    "uh oh $key isnt taken care of we\'ll fix that");
                $self->_add_to_list( "AL", $key );
            }
        }
        $self->send( 'CHG', 'NLN 536870964' );
        $self->call_event("Connected");

    }
}

sub converterror {
    my $err = shift;
    my %errlist;

    $errlist{200} = 'Invalid Syntax';
    $errlist{201} = 'Invalid parameter';
    $errlist{205} = 'Invalid user';
    $errlist{206} = 'Domain name missing';
    $errlist{207} = 'Already logged in';
    $errlist{208} = 'Invalid User Name';
    $errlist{209} = 'Invlaid Friendly Name';
    $errlist{210} = 'List Full';
    $errlist{215} = 'User already on list';
    $errlist{216} = 'User not on list';
    $errlist{217} = 'User not online';                   #<--
    $errlist{218} = 'Already in that mode';
    $errlist{219} = 'User is in the opposite list';
    $errlist{223} = 'Too Many Groups';                   #<--
    $errlist{224} = 'Invalid Groups ';                   #<--
    $errlist{225} = 'User Not In Group';                 #<--
    $errlist{229} = 'Group Name too long';               #<--
    $errlist{230} = 'Cannont Remove Group Zero';         #<--
    $errlist{231} = 'Invalid Group';                     #<--
    $errlist{280} = 'Switchboard Failed';                #<--
    $errlist{281} = 'Transfer to Switchboard failed';    #<--

    $errlist{300} = 'Required Field Missing';
    $errlist{301} = 'Too Many Hits to FND';              #<--
    $errlist{302} = 'Not Logged In';

    $errlist{500} = 'Internal Server Error';
    $errlist{501} = 'Database Server Error';
    $errlist{502} = 'Command Disabled';
    $errlist{510} = 'File Operation Failed';
    $errlist{520} = 'Memory Allocation Failed';
    $errlist{540} = 'Challenge Responce Failed';

    $errlist{600} = 'Server Is Busy';
    $errlist{601} = 'Server Is Unavailable';
    $errlist{602} = 'Peer Name Server is Down';
    $errlist{603} = 'Database Connection Failed';
    $errlist{604} = 'Server Going Down';
    $errlist{605} = 'Server Unavailable';

    $errlist{707} = 'Could Not Create Connection';
    $errlist{710} = 'Bad CVR Parameter Sent';
    $errlist{711} = 'Write is Blocking';
    $errlist{712} = 'Session is Overloaded';
    $errlist{713} = 'Too Many Active Users';
    $errlist{714} = 'Too Many Sessions';
    $errlist{715} = 'Command Not Expected';
    $errlist{717} = 'Bad Friend File';
    $errlist{731} = 'Badly Formated CVR';

    $errlist{800} = 'Friendly Name Change too Rapidly';

    $errlist{910} = 'Server Too Busy';
    $errlist{911} = 'Authentication Failed';
    $errlist{912} = 'Server Too Busy';
    $errlist{913} = 'Not allowed While Offline';
    $errlist{914} = 'Server Not Available';
    $errlist{915} = 'Server Not Available';
    $errlist{916} = 'Server Not Available';
    $errlist{917} = 'Authentication Failed';
    $errlist{918} = 'Server Too Busy';
    $errlist{919} = 'Server Too Busy';
    $errlist{920} = 'Not Accepting New Users';
    $errlist{921} = 'Server Too Busy: User Digest';
    $errlist{922} = 'Server Too Busy';
    $errlist{923} = 'Kids Passport Without Parental Consent';    #<--K
    $errlist{924} = 'Passport Account Not Verified';

    return ( $errlist{$err} || 'unknown error' );
}

sub _strip_header {
    my ($msg) = shift;
    $msg =~ s/\r//gs;                                            # fix newlines
                                                                 #warn "\n$msg";
    if ( $msg =~ /^(.*?)\n\n(.*?)$/s ) {
        my ( $head, $msg ) = ( $1, $2 );
        my @temp = split( /\n/, $head );
        my $header = {};
        foreach my $item (@temp) {
            my ( $key, $value ) = split( /:\s*/, $item );
            $header->{$key} = $value || "";
        }

        #			my $header = { map { split(/\:\s*/, $_ ) } @temp };

        #				print Dumper($header);
        return $header, $msg;
    }
    return $msg;
}

sub _do_connect_loop {
    my ( $redir, $auth ) = @_;
    if ( $redir =~ /ru=([^\&]+)/ ) { $redir = $1; }

    my $ua       = new LWP::UserAgent;
    my @requests = ();
    $ua->requests_redirectable( \@requests );
    $ua->agent('MSMSGS');

    my $request = new HTTP::Request( GET => $redir );
    $request->headers->header( 'Authorization' => $auth );
    my $response = $ua->request($request);

    $redir = $response->header('location') || undef;
    my $info = $response->header('authentication-info') || undef;

    if ( defined $info ) {
        my ( $Version, $pairs ) = $info =~ /^(.*?) (.*)$/;
        my $settings = { map { split( '=', $_, 2 ) } split( ',', $pairs ) };
        if ( $settings->{'da-status'} =~ /^success|redir$/ ) {
            if ( $settings->{'da-status'} eq 'success' ) {
                $settings->{'from-PP'} =~ s/'//g;
                return $settings->{'from-PP'};
            }
            elsif ( $settings->{'da-status'} eq 'redir' ) {
                return _do_connect_loop( $redir, $auth );
            }
            else {
                warn "Authentication Error: Unexpected return: $info";
            }
        }
    }
    elsif ( defined $redir ) {
        return _do_connect_loop( $redir, $auth );
    }
    elsif ( my $error_info = $response->header('www-authenticate') ) {
        $error_info =~ s/^.+cbtxt=(.+)$/$1/;
        $error_info =~ tr/+/ /;
        $error_info =~ s/%(..)/pack("c",hex($1))/ge;
        warn "\nSERVER RETURNED ERROR: $error_info";
    }
    else {
        warn 'Authentication Error: No expected reply recieved...';
    }
}

sub authenticate {
    my ( $self, $challenge ) = @_;
    $challenge = { map { split '=' } split( ',', $challenge ) };

    my $ua            = new LWP::UserAgent;
    my $response      = $ua->get('https://nexus.passport.com/rdr/pprdr.asp');
    my %passport_urls =
      map { split '=' }
      split( ',', ( $response->headers->header('PassportURLs') ) );
    my $DALogin = $passport_urls{'DALogin'};

    my ( $username, $password ) =
      ( uri_escape( $self->{Handle} ), uri_escape( $self->{Password} ) );

    my $auth_string =
        "Passport1.4 OrgVerb=GET,OrgURL=$challenge->{ru}},"
      . "sign-in=$username,pwd=$password,lc=$challenge->{lc},"
      . "id=$challenge->{id},tw=$challenge->{tw},"
      . "fs=$challenge->{fs},ct=$challenge->{ct},"
      . "kpp=$challenge->{kpp},kv=$challenge->{kv},"
      . "ver=$challenge->{ver},tpf=$challenge->{tpf}";

    return _do_connect_loop( 'https://' . $DALogin, $auth_string );

}

=head1 EXAMPLE

	 use MSN;
	 
	 my $Email = 'email@msn.com';
	 my $Password = 'big secret password';
	 
	 my $msn = MSN->new(Handle => $Email, Password => $Password);
	 
	 $msn->set_handler(Connected => \&Connected);
	 $msn->set_handler(Message	  => \&Message);
	 $msn->set_handler(Answer	  => \&Answer);
	 $msn->set_handler(Join		=> \&Join);
	 $msn->set_handler(Update_Chat_Buddies => \&UpdateBuddies);
	 $msn->set_handler(Status => \&Status);
	 
	 $msn->connect();
	 
	 while (1)
	 {
		  $msn->do_one_loop;
	 }
	 
	 sub Message {
		  my ($self, $victim, $name, $msg) = @_;
		  $msg =~ s/<(|\n)+?>//g;
		  $self->sendmsg($msg);
	 }
	 
	 sub Connected {
		  my $self = shift;
		  warn "Calling Eric!";
		  $msn->call('eric256@rocketmail.com',"Dude");
	 }
	 
	 sub Answer {
		  my ($self, $username) = @_;
		  $self->sendmsg("I don't know anything!");
	 }
	 
	 sub Join {
		  my ($self,$user,$friendly) = @_;
		  $self->sendmsg("Welcome $user");
	 }
	 
	 sub UpdateBuddies
	 {
		  my $self = shift;
		  $self->sendmsg("Hello " . join(",", map {$self->{Buddies}->{$_}} keys %{$self->{Buddies}}));
	 }

	 sub Status
	 {
		  my( $self, $username, $status ) = @_;

		  if( $status eq 'NLN' )
		  {
				# $username is online, do something about it
		  }
		  elsif( $status eq 'FLN' )
		  {
				# $username is offline, do something about it
		  }
	 }

	 1;

=cut

=head1 CONTRIBUTIONS

	 Eric Hodges (ejh)
	 eric256@rocketmail.com
	 
	 Steve Fullbrook (sgf)
	 keenie_bean@hotmail.com

	 William Kelley (wtk)
	 wtk@kjwconsulting.com

If you know you should be on this list and are not then please contact one of the above contributors to have the situation fixed.

=head1 COPYRIGHT

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.


=head1 SEE ALSO

=cut

return 1;
__DATA__
