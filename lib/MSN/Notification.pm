#================================================
package MSN::Notification;
#================================================

use strict;
use warnings;

# IO
use IO::Socket;

# For authenticate
use URI::Escape;
use URI;
use HTTP::Request;
use LWP::UserAgent;

# For challenge
use Digest::MD5 qw(md5 md5_hex md5_base64);
use LWP::Simple;

# For DP
use Digest::SHA1 qw(sha1 sha1_hex sha1_base64);

# For RNG
use MSN::SwitchBoard;

# For errors
use MSN::Util;

#Time
use POSIX qw(strftime);

#PSM XML Parsing
use XML::Simple;
use Data::Dumper;

#For Passport 3.0
use MSN::AuthPP3;

use constant CVER10 => '0x0409 winnt 5.1 i386 MSNMSGR 7.0.0777 MSMSGS ';
use constant VER => 'MSNP11 CVR0\r\n';
my $VER = 'MSNP11 MSNP10 CVR0';

sub checksum { my $o = tell(DATA); seek DATA,0,0; local $/; my $t = unpack("%32C*",<DATA>) % 65535;seek DATA,$o,0; return $t;};


sub new
{
	my $class = shift;
	my ($msn, $host, $port, $handle, $password) = (shift, shift, shift, shift, shift);

	my $self  =
	{
		Msn				=> $msn,
		Host				=> $host,
		Port				=> $port,
		Handle			=> $handle,
		Password			=> $password,
		Socket			=> {},
		Objects			=> {},
		DPLocation		=> {},
		Type				=> 'NS',
		Calls				=> {},
		Lists				=> { 'PL' => {}, 'AL' => {}, 'FL' => {}, 'BL' => {}, 'RL' => {} },
		PingTime			=> time,
		PongTime			=> time,
		PingIncrement	=> 30,
		NoPongMax		=> 60,
		TrID				=> 0,
		Objects			=> {},
		DPLocation		=> '',
		@_
	};
	bless( $self, $class );

	return $self;
}

sub DESTROY
{
	my $self = shift;

	# placeholder for possible destructor code
}

sub AUTOLOAD
{
	my $self = shift;

	my $method = $MSN::Notification::AUTOLOAD;

	if( $method =~ /CMD_(.*)$/ )
	{
		$self->cmdError( "$1 not handled in MSN::Notification" );
	}
	else
	{
		$self->error( "method $method not defined" ) if( $self->{Msn}->{AutoloadError} );
	}
}

sub debug
{
	my $self = shift;

	return $self->{Msn}->debug( @_ );
}

sub consolemsg
{
	my $self = shift;

	return $self->{Msn}->consolemsg( @_ );
}

sub error
{
	my $self = shift;

	return $self->{Msn}->error( @_ );
}

sub serverError
{
	my $self = shift;

	return $self->{Msn}->serverError( @_ );
}

sub cmdError
{
	my $self = shift;

	return $self->{Msn}->cmdError( @_ );
}

#================================================
# connect to the Notification Server
# add the socket to the Select object
# add self to the Connections hash
# start a conversation by sending VER
#================================================

sub connect
{
	my $self = shift;
	my $host = shift || $self->{Host};
	my $port = shift || $self->{Port};

	$self->{Socket} = new IO::Socket::INET( PeerAddr => $host, PeerPort => $port, Proto	  => 'tcp' );

	# if we can't open a socket, set an error and return 0
	return $self->serverError( "Connection error: $!" ) if( !defined $self->{Socket} );

	$self->{Msn}->{Select}->add( $self->{Socket} );
	$self->{Msn}->{Connections}->{ $self->{Socket}->fileno } = $self;

	# start the conversation
	$self->send( 'VER', $VER );

	return 1;
}

sub disconnect
{
	my $self = shift;

	$self->debug( "Disconnecting from Notification Server" );

	return $self->_send( "OUT\r\n" );
}

sub getType
{
	my $self = shift;

	return 'NS';
}

sub send
{
	my $self = shift;
	my $cmd  = shift || return $self->error( "No command specified to send" );
	my $data = shift;

	# Generate TrID using global TrID value...
	my $datagram = $cmd . ' ' . $self->{TrID}++ . ' ' . $data . "\r\n";
	return $self->_send( $datagram );
}

sub sendraw
{
	my $self = shift;
	my $cmd = shift || return $self->error( "No command specified to send" );
	my $data  = shift;
	# same as send without the "\r\n"

	my $datagram = $cmd . ' ' . $self->{TrID}++ . ' ' . $data;
	return $self->_send($datagram);
}

sub _send
{
	my $self = shift;
	my $msg = shift || return $self->error( "No message specified" );

	return $self->error( "Trying to print '$msg' on an undefined socket" ) if( !defined $self->{Socket} );

	# Send the data to the socket.
	$self->{Socket}->print( $msg );
	my $fn = $self->{Socket}->fileno;
	if( $msg eq "OUT\r\n" || $msg eq "BYE\r\n" )
	{
		$self->{Msn}->{Select}->remove( $self->{Socket}->fileno() );
		delete $self->{Msn}->{Connections}->{ $self->{Socket}->fileno() };
		undef $self->{Socket};
	}
	chomp($msg);

	#print STDERR "($fn $self->{Type}) TX: $msg\n" if( $self->{Msn}->{ShowTX} );

	return length($msg);
}

sub setName
{
	my $self = shift;
	my $name = shift || return $self->error( "Must be passed new name." );

	if( length $name > 129 )
	{
		return $self->error( "Display name to long to set" );
	}

	$self->send( 'PRP', 'MFN ' . uri_escape( $name ) );

	return 1;
}

sub setPSM
{
	my $self = shift;
	my $psm = shift;

	my $data = '<Data><PSM>'.$psm.'</PSM><CurrentMedia></CurrentMedia></Data>';
	$self->sendraw("UUX",  length($data)."\r\n" . $data);# if ($MSNPROTO eq 'MSNP11');
}

sub setDisplayPicture
{
	my $self = shift;
	my $filename = shift;

	if( !$filename )
	{
		# Remove DP
		$self->{DPData} = '';
		$self->{MSNObject} = '';
		$self->setStatus( $self->{Msn}->{Status} );
		return 1;
	}

	if( $filename !~ /\.png$/ )
	{
		return $self->error( "File must be a PNG file" );
	}

	# append the time so we get a unique hash everytime
	# makes debuging easier because MSN can't cache it
	my $location = "msndp.dat". time;
	$self->{DPLocation} = $location;
	($self->{Objects}->{$location}->{Object},
	$self->{Objects}->{$location}->{Data}) = $self->create_msn_Object($filename,$location);
	# Set new status & return
	$self->setStatus( $self->{Msn}->{Status} );
	$self->debug( "Done With Dp!" );
	return 1;
}

sub setStatus
{
	my $self = shift;
	my $status = shift || 'NLN';

	# save our current status for use in setDisplayPicture
	$self->{Msn}->{Status} = $status;

	my $object = '';
	if (defined $self->{DPLocation} && exists $self->{Objects}->{$self->{DPLocation}} ) {
		$object = uri_escape($self->{Objects}->{$self->{DPLocation}}->{Object});
	}
	$self->send( 'CHG', $status . " " . $self->{Msn}->{ClientID} . " " . $object);
}

sub addEmoticon
{
	my $self = shift;
	my $shortcut = shift;
	my $filename = shift;
	
	if((-e $filename) && $filename =~ /png$/)
	{
		($self->{Objects}->{$shortcut}->{Object},
		$self->{Objects}->{$shortcut}->{Data}) = $self->create_msn_Object($filename,$shortcut);
		return 1;
	}
	else
	{
		return $self->error( "Could not find the file '$filename', or it is not a PNG file" );
	}	
}

sub create_msn_Object
{
	 my $self = shift;
	 my $file = shift;
	 my $location = shift;

	 my $data = '';

	 open( DP, $file ) || return $self->error( "Could not find the file '$file'" );
	 binmode(DP);
	 while( <DP> ) { $data .= $_; }
	 close(DP);

	 # SHA1D and the Display Picture Data
	 my $sha1d = sha1_base64( $data ) . '=';

	 # Compile the object from its keys + sha1d
	 my $object = 'Creator="'  . $self->{Handle} . '" ' .
					  'Size="'     . (-s $file)      . '" ' .
					  'Type="3" '  .
					  'Location="' . $location       . '" ' .
					  'Friendly="AAA=" ' .
					  'SHA1D="'    . $sha1d          . '"';

	 # SHA1C - this is a checksum of all the key value pairs
	 my $sha1c = $object =~ s/(\"=\s)*//g;
	 $sha1c = sha1_base64( $sha1c ) . '=';

	 # Put it all in its nice msnobj wrapper.
	 $object = '<msnobj ' . $object . ' SHA1C="' . $sha1c . '" />';

	 return ($object, $data);

}

#================================================
# Contact methods
#================================================

sub blockContact
{
	my $self = shift;
	my $email = shift || return $self->error( "Need an email address to block" );

	return 0 if( defined $self->{Lists}->{'BL'}->{$email} );

	$self->remContact($email);
	$self->disallowContact($email);
	$self->send( "ADC", "BL N=$email" );

	return 1;
}

sub unblockContact
{
	my $self = shift;
	my $email = shift || return $self->error( "Need an email address to unblock" );

	return 0 if( !defined $self->{Lists}->{'BL'}->{$email} );

	$self->send( "REM", "BL $email" );
	$self->allowContact($email);

	return 1;
}

sub addPending
{
        my $self = shift;
        my $email = shift || return $self->error( "Need an email address to add" );

	my $user = $self->{Lists}->{'PL'}->{$email};
	my $guid = $user->{guid};
	my $group = $user->{group};
        return 0 if( !defined $self->{Lists}->{'PL'}->{$email} );

	if (defined $self->{Lists}->{'BL'}->{$email}) {
	        $self->send( "REM", "BL $email" );	
	}

	if (!defined $self->{Lists}->{'RL'}->{$email}) {
	 	$self->send( "ADC", "RL N=$email" );
	}

	if (defined $self->{Lists}->{'PL'}->{$email}) {
	 	$self->send( "REM", "PL $email" );
		$self->consolemsg("$email removed from pending list.");
	}

	if (!defined $self->{Lists}->{'AL'}->{$email}) {
	        $self->send( "ADC", "AL N=$email" );
	}

	if (!defined $self->{Lists}->{'FL'}->{$email}) {
	        $self->send( "ADC", "FL N=$email F=$email" );
	}
	
        return 1;
}

sub addContact
{
	my $self = shift;
	my $email = shift || return $self->error( "Need an email address to add" );

	return 0 if( defined $self->{Lists}->{'FL'}->{$email} );

	$self->send( "ADC", "FL N=$email F=$email" );

	return 1;
}

sub remContact
{
	my $self = shift;
	my $email = shift || return $self->error( "Need an email address to remove" );

	return 0 if( !defined $self->{Lists}->{'FL'}->{$email} );

	my $user = $self->{Lists}->{'FL'}->{$email};
	$self->send( "REM", "FL " . ($user->{guid} || $email) . $user->{group} );

	return 1;
}

sub allowContact
{
	my $self = shift;
	my $email = shift || return $self->error( "Need an email address to add" );

	return 0 if( defined $self->{Lists}->{'AL'}->{$email} );

	$self->send( "ADC", "AL N=$email" );

	return 1;
}

sub disallowContact
{
	my $self = shift;
	my $email = shift || return $self->error( "Need an email address to remove" );

	return 0 if( !defined $self->{Lists}->{'AL'}->{$email} );

	$self->send( "REM", "AL $email" );

	return 1;
}

sub getContactList
{
	my $self = shift;
	my $list = shift || return $self->error( "You must specify a list to check" );

	if( !exists $self->{Lists}->{$list} )
	{
		return $self->error( "That list ($list) does not exists. Please try RL, BL, AL or FL" );
	}

	return keys %{$self->{Lists}->{$list}};
}

sub getContact
{
	my $self = shift;
	my $email = shift || return $self->error( "No email given" );

	if( !defined $self->{Lists}->{AL}->{$email} && !defined $self->{Lists}->{FL}->{$email} && !defined $self->{Lists}->{BL}->{$email} && !defined $self->{Lists}->{RL}->{$email} )
	{
		return $self->error( "Contact doesn't exist" );
	}

	my $contact = { Email			=> $email,
						 Friendly		=> $self->{Lists}->{FL}->{$email}->{Friendly} || '',
						 Status			=> $self->{Lists}->{FL}->{$email}->{Status} || '',
						 CID				=> $self->{Lists}->{FL}->{$email}->{ClientID} || 0,
						 ClientInfo		=> MSN::Util::convertFromCid( $self->{Lists}->{FL}->{$email}->{ClientID} || 0 ),
						 AL				=> defined( $self->{Lists}->{AL}->{$email} ) ? 1 : 0,
						 FL				=> defined( $self->{Lists}->{FL}->{$email} ) ? 1 : 0,
						 BL				=> defined( $self->{Lists}->{BL}->{$email} ) ? 1 : 0,
						 RL				=> defined( $self->{Lists}->{RL}->{$email} ) ? 1 : 0
					  };

	return $contact;
}

sub getContactName
{
	my $self = shift;
	my $email = shift || return $self->error( "No email given" );

	if( !defined $self->{Lists}->{FL}->{$email} || !defined $self->{Lists}->{FL}->{$email}->{Friendly} )
	{
		return $self->error( "Contact doesn't exist" );
	}

	return $self->{Lists}->{FL}->{$email}->{Friendly};
}

sub getContactStatus
{
	my $self = shift;
	my $email = shift || return $self->error( "No email given" );

	if( !defined $self->{Lists}->{FL}->{$email} || !defined $self->{Lists}->{FL}->{$email}->{Status} )
	{
		return $self->error( "Contact doesn't exist" );
	}

	return $self->{Lists}->{FL}->{$email}->{Status};
}

sub getContactClientInfo
{
	my $self = shift;
	my $email = shift || return $self->error( "No email given" );

	if( !defined $self->{Lists}->{FL}->{$email} || !defined $self->{Lists}->{FL}->{$email}->{ClientID} )
	{
		return $self->error( "Contact doesn't exist" );
	}

	my $cid = $self->{Lists}->{FL}->{$email}->{ClientID};

	my $info = MSN::Util::convertFromCid( $cid );

	return $info;
}

sub call
{
	my $self = shift;
	my $handle = shift || return $self->error( "Need to send the handle of the person you want to call" );
	my $message = shift;
	my %style = @_;

	# see if we already have a conversation going with the contact being called
	my $convo = $self->{Msn}->findMember( $handle );

	# if so, simply send them this message
	if( $convo )
	{
		$convo->sendMessage( $message, %style );
	}
	# otherwise, open a switchboard and save the message for later delivery
	else
	{
		# try to get a new switchboard
		$self->send( 'XFR', 'SB' );

		# store the handle and message of this call for use after we have a switchboard (why subtract 1 here??)
		my $TrID = $self->{TrID} - 1;
		$self->{Calls}->{$TrID}->{Handle} = $handle;
		$self->{Calls}->{$TrID}->{Message} = $message;
		$self->{Calls}->{$TrID}->{Style} = \%style;
	}
}

sub ping
{
	my $self = shift;

	if( time >= $self->{PingTime} + $self->{PingIncrement} )
	{
		$self->{Msn}->call_event( $self, "Ping" );

		# send PNG with no TrID
		$self->_send( "PNG\r\n" );

		$self->{PingTime} = time;

		# if no pong is received within the required time limit, assume we are disconnected
		if( time - $self->{PongTime} > $self->{NoPongMax} )
		{
			# disconnect
			$self->debug( "Disconnected : No pong received from server" );
			$self->{Msn}->disconnect();

			# call the Disconnected handler
			$self->{Msn}->call_event( $self, "Disconnected", "No pong received from server" );

			# reconnect if AutoReconnect is true
			$self->{Msn}->connect() if( $self->{Msn}->{AutoReconnect} );
		}
	}
}

#================================================
# internal method for updating a contact's info
#================================================

sub set_contact_status
{
        my $self = shift;
        my $email = shift || return $self->error( "No email given" );
        my $status = shift || return $self->error( "No status given" );
        my $friendly = shift || '';
        my $cid = shift || 0;

#NOTE, $STATUS WILL BE "UBX" WHEN IT IS A PERSONAL MESSAGE, AND "UBM" WHEN IT IS MUSIC THAT IS BEING UPDATED!

        $self->{Msn}->call_event( $self, "Status", $email, $status, $friendly );
        $self->{Lists}->{FL}->{$email}->{Status} = $status;
        $self->{Lists}->{FL}->{$email}->{Friendly} = $friendly;
        $self->{Lists}->{FL}->{$email}->{ClientID} = $cid;
        $self->{Lists}->{FL}->{$email}->{LastChange} = time;

}

#================================================
# dispatch a server event to this object
#================================================

sub dispatch
{
	my $self = shift;
	my $incomingdata = shift || '';

	my ($cmd, @data) = split( / /, $incomingdata );

	if( !defined $cmd )
	{
		#This has been commented out because of the server sometimes
		#sends \r\n\r\n which the bot parses as an empty event.
		#return $self->serverError( "Empty event received from server : '" . $incomingdata . "'" );
	}
	elsif( $cmd =~ /[0-9]+/ )
	{
		return $self->serverError( MSN::Util::convertError( $cmd ) . " : " . @data );
	}
	else
	{
		my $c = "CMD_" . $cmd;

		no strict 'refs';
		&{$c}($self, @data);
	}
}

#================================================
# MSN Server messages handled by Notification
#================================================

sub CMD_VER
{
	 my $self = shift;
	 my @data = @_;

	$self->{protocol} = $data[1];
	$self->send( 'CVR', CVER10 . $self->{Handle} );

	return 1;
}

sub CMD_CVR
{
	my $self = shift;
	my @data = @_;

	$self->send( 'USR', 'TWN I ' . $self->{Handle});

	return 1;
}

sub CMD_USR
{
        my $self = shift;
        my @data = @_;

        if ($data[1] eq 'TWN' && $data[2] eq 'S')
        {
		$self->{Auth} = new MSN::AuthPP3($self, $self->{Handle}, $self->{Password}, $data[3]);
		my $token = $self->{Auth}->auth($self->{Handle}, $self->{Password}, $data[3]);
                #my $token = $self->authenticate( $data[3] ); #This is the old version, just comment the two lines above this and uncomment this one to change back.
		if (!defined $token) {
                        $self->disconnect;
			return $self->error("A problem occurred during authentication. Details should be shown above.");;
                }
                $self->send('USR', 'TWN S ' . $token);
        }
        elsif( $data[1] eq 'OK' )
        {
                my $friendly = $data[3];
                $self->send( 'SYN', "0 0" );
        }
        else
        {
                return $self->serverError( 'Unsupported authentication method: "' . "@data" .'"' );
        }
}

#================================================
# Get the number of contacts on our contacts list
# Request Shields.xml
#================================================

sub CMD_SYN
{
        my $self = shift;
        my @data = @_;

        $self->{Lists}->{SYN}->{Total} = $data[3];
        $self->debug( "Syncing lists with $self->{Lists}->{SYN}->{Total} contacts" );
	$self->send( 'GCF', 'Shields.xml');
}

#================================================
# This command isn't really needed, and can be ignored
# for now, but it brings up an error unless it is
# handled, so we might as well just add the handling
# now.
#================================================

sub CMD_GCF
{
        my $self = shift;
        my @data = @_;

        $self->debug( "Shields.xml received." );

        $self->send( 'CHG', 'NLN ' . $self->{Msn}->{ClientID} );
        $self->{Msn}->call_event( $self, "Connected" );
}

#================================================
# This value is only stored on the server and has no effect
# it's here to tell the client what to do with new contacts
# we don't need any particular value and can do whatever we want
# but we'll just set the value to automatic to be good
#================================================

sub CMD_GTC
{
	my $self = shift;
	my @data = @_;

	if( $data[0] eq 'A' )
	{
		# Tell the server that we don't need confirmation for people to add us to their contact lists
		$self->send( 'GTC', 'N' );
	}
}

#================================================
# As we are a bot, we want anyone to be able to invite and chat with us
# this could be an option in future clients
#================================================

sub CMD_BLP
{
	my $self = shift;
	my @data = @_;

	if ( $data[0] eq 'BL' )
	{
		# Tell the server we want to allow anyone to invite and chat with us
		$self->send( 'BLP', 'AL' );
	}
}

#================================================
# Getting our list of contact groups
#================================================

sub CMD_LSG
{
	my $self = shift;
	my ($group, $guid) = @_;

#	$self->debug( "Group $group ($guid) added" );
	$self->{Groups}->{$group} = $guid;
}

#================================================
# Getting our list of contacts
# Feel free to clean this up if you want.
#================================================

sub CMD_LST
{
        my $self = shift;

        my ($email, $friendly, $guid, $bitmask, $group);

        my @items = grep { /=/ } @_;
        my @masks = grep { !/=/ } @_;

        my $settings = {};
        foreach my $item (@items)
        {
                my ($what,$value) = split (/=/,$item);
                $settings->{$what} = $value;
        }

        $bitmask = pop @masks;
        if( $bitmask =~ /[a-z]/ )
        {
                $group = $bitmask;
                $bitmask = pop @masks;
        }

        $email         = $settings->{N};
        $friendly = $settings->{F} || '';
        $guid                 = $settings->{C} || '';

        my $contact = { email         => $email,
                                                 Friendly => $friendly,
                                                 guid                 => $guid,
                                                 group         => $group };

        #$self->consolemsg( "'$email', '$friendly', '$bitmask', '$guid'" );        # , '$group'" );

        $self->{Lists}->{SYN}->{Current}++;

        my $current = $self->{Lists}->{SYN}->{Current};
        my $total = $self->{Lists}->{SYN}->{Total};

        $self->{Lists}->{PL}->{$email} = $contact                    if ($bitmask & 16);
        $self->{Lists}->{RL}->{$email} = $contact                    if ($bitmask & 8);
        $self->{Lists}->{BL}->{$email} = 1                           if ($bitmask & 4);
        $self->{Lists}->{AL}->{$email} = $contact                    if ($bitmask & 2);
        $self->{Lists}->{FL}->{$email} = $contact                    if ($bitmask & 1);
        if ($current == $total)
        {
                my $PL = $self->{Lists}->{PL};
                my $RL = $self->{Lists}->{RL};
                my $AL = $self->{Lists}->{AL};
                my $BL = $self->{Lists}->{BL};
                my $FL = $self->{Lists}->{FL};

                foreach my $handle (keys %$RL)
                {
                        if( !defined $AL->{$handle} && !defined $BL->{$handle} && !defined $PL->{$handle})
                        {
                                # This contact wants to be allowed, ask if we should
                                my $do_add = $self->{Msn}->call_event( $self, "ContactAddingUs", $handle );
                                $self->allowContact( $handle ) unless( defined $do_add && !$do_add );
                        }
                }

                foreach my $handle (keys %$PL)
                {
                        # Pending contact.
			# $self->consolemsg("Pending user: $handle | Guid - $PL->{$handle}->{guid}");
                        $self->addPending( $handle );
			goto THEEND;
                }

                foreach my $handle (keys %$AL)
                {
			if (!defined $FL->{$handle}) {
				if (defined $AL->{guid}) {
		     			$self->send( "ADC", "FL C=$AL->{guid}" );
				}
			}
                }

                foreach my $handle (keys %$FL)
                {
			if (!defined $BL->{$handle} && !defined $AL->{$handle} && !defined $RL->{$handle}) {
				$self->consolemsg("$handle is currently on FL, but nothing else");
	     		   $self->send( "ADC", "AL N=$handle" );
			}
			if (!defined $BL->{$handle} && defined $AL->{$handle} && !defined $RL->{$handle}) {
				#$self->consolemsg("<Contact List> $handle has removed the bot from their RL. The bot will not receive updates from them.");
			}
                }
THEEND:

        }
}

sub CMD_UBX
{
        my $self = shift;
        my ($email, $length) = @_;

        # we don't have the full message yet, so store it and return
        if( length( $self->{buf} ) < $length )
        {
                $self->{buf} = $self->{line} . $self->{buf};
                return "wait";
        }

        #print STDERR "Got full message: [" . $self->{buf} . "]\n";
        # get the message and split into header and msg content
        my ( $header, $msg ) = ( '', substr( $self->{buf}, 0, $length, "" ) );
        ($header, $msg) = _strip_header($msg);
	
	# create object
	my $xml = new XML::Simple;

	if ($msg) {
		# read XML file
		my $data = $xml->XMLin($msg, suppressempty => '');
	
		if ($data->{CurrentMedia} ne "") {
			my ($nothing, $ismusic, $nothingtwo, $artisttitle, $dataone, $datatwo, @mediavalues) = split('\\\0',$data->{CurrentMedia});
			if ($ismusic eq "Music") {
				$self->set_contact_status( $email, "UBM", "Listening to:" . ($dataone || '') . ' - ' . ($datatwo || '')); 
			}
		} else {
			if ($data->{PSM} eq "") {
				$self->set_contact_status( $email, "UBX", ""); 	
			} else {
				$self->set_contact_status( $email, "UBX", $data->{PSM});
			}
		}
	} else {
		$self->set_contact_status ( $email, "UBX", "");
	}
}

sub CMD_NLN
{
	my $self = shift;
	my ($status, $email, $friendly, $cid) = @_;

	$self->set_contact_status( $email, $status, $friendly, $cid );
}

sub CMD_FLN
{
	my $self = shift;
	my ($email) = @_;

	$self->set_contact_status( $email, 'FLN' );
}

sub CMD_ILN
{
	my $self = shift;
	my ($trid, $status, $email, $friendly, $cid) = @_;

	$self->set_contact_status( $email, $status, $friendly, $cid );
 }

sub CMD_CHG
{
	my $self = shift;
	my @data = @_;
}

sub CMD_ADC
{
	my $self = shift;
	my ($TrID, $list, $handle, $name) = @_;
	(undef, $handle) = split( /=/, $handle );

	if( $list eq 'RL' )		# a user is adding us to their contact list (our RL list)
	{
		$self->{Lists}->{'RL'}->{$handle} = 1;
		# ask for approval before we add this contact (default to approved)
		my $do_add = $self->{Msn}->call_event( $self, "ContactAddingUs", $handle );				  
		$self->allowContact( $handle ) unless( defined $do_add && !$do_add );
	}
	elsif( $list eq 'PL' )  # server telling us we successfully added someone to our AL list
	{
		$self->{Lists}->{'PL'}->{$handle} = 1;
		my $do_add = $self->{Msn}->call_event( $self, "ContactAddingUs", $handle );				  
		$self->addPending( $handle ) unless( defined $do_add && !$do_add );
	}
	elsif( $list eq 'AL' )  # server telling us we successfully added someone to our AL list
	{
		$self->{Lists}->{'AL'}->{$handle} = 1;
	}
	elsif( $list eq 'BL' )  # server telling us we successfully added someone to our BL list
	{
		$self->{Lists}->{'BL'}->{$handle} = 1;
	}	  
	elsif( $list eq 'FL' )  # server telling us we successfully added someone to our FL list
	{
		my @items = grep { /=/ } @_;
		my $settings = {};	 
		foreach my $item (@items)
		{
			my ($what,$value) = split (/=/,$item);
			$settings->{$what} = $value;
		}

		my $contact = { email	 => $settings->{N},
							 Friendly => $settings->{F},
							 guid		 => $settings->{C},
							 group	 => '' };

		$self->{Lists}->{'FL'}->{$handle} = $contact;
	}
}

sub CMD_REM
{
	my $self = shift;
	my ($TrID, $list, $handle) = @_;

	if( $list eq 'RL' )		# a user is removing us from their contact list (our RL list)
	{
		delete $self->{Lists}->{'RL'}->{$handle};
		$self->{Msn}->call_event( $self, "ContactRemovingUs", $handle );
		$self->disallowContact( $handle);
#		$self->remContact( $handle);
	}
	elsif( $list eq 'PLL' )  # server telling us we successfully removed someone from our PL list
	{
		# This means that as long as the contact has been added to the
		# reverse list, we can see them online.
		$handle =~ s/^N=//gi;
		delete $self->{Lists}->{'PL'}->{$handle};
	}
	elsif( $list eq 'AL' )  # server telling us we successfully removed someone from our AL list
	{
		$handle =~ s/^N=//gi;
		delete $self->{Lists}->{'AL'}->{$handle};
	}
	elsif( $list eq 'BL' )  # server telling us we successfully removed someone from our BL list
	{
		delete $self->{Lists}->{'BL'}->{$handle};
	}
	elsif( $list eq 'FL' )  # server telling us we successfully removed someone from our FL list
	{
		foreach my $mail (keys %{$self->{Lists}->{'FL'}})
		{
			 if ($self->{Lists}->{'FL'}->{$mail}->{guid} eq $handle)
			 {
				  delete $self->{Lists}->{'FL'}->{$mail};
				  return;
			 }
		}
	}
}

sub CMD_XFR
{
	my $self = shift;
	my @data = @_;

	if( $data[1] eq 'NS' )
	{
		my ($host, $port) = split( /:/, $data[2] );
		$self->{Socket}->close();
		$self->{Msn}->{Select}->remove( $self->{Socket} );

		# why wouldn't this be defined??
		if( defined $self->{Socket}->fileno )
		{
			delete( $self->{Msn}->{Connections}->{ $self->{Socket}->fileno } );
		}

		$self->connect( $host, $port );
	}
	elsif( $data[1] eq 'SB' )
	{
		if( defined $self->{Calls}->{$data[0]}->{Handle} )
		{
			my ( $host, $port ) = split( /:/, $data[2] );

			# get a switchboard and connect, passing along the call handle and message
			my $switchboard = new MSN::SwitchBoard( $self->{Msn}, $host, $port );
			$switchboard->connectXFR( $data[4], $self->{Calls}->{$data[0]}->{Handle}, $self->{Calls}->{$data[0]}->{Message}, $self->{Calls}->{$data[0]}->{Style} );
		}
		else
		{
			$self->serverError( 'Received XFR SB request, but there are no pending calls!' );
		}
	}
}

#================================================
# someone is calling us
#================================================

sub CMD_RNG
{
	my $self = shift;
	my ($sid, $addr, undef, $key, $user, $friendly) = @_;

	# ask for approval before we answer this ring (default to approved)
	my $do_accept = $self->{Msn}->call_event( $self, "Ring", $user, uri_unescape($friendly) );

	if( !defined $do_accept || $do_accept )
	{
		my ($host, $port) = split ( /:/, $addr );

		my $switchboard = new MSN::SwitchBoard( $self->{Msn}, $host, $port );
		$switchboard->connectRNG( $key, $sid );
	}
}

#================================================
# a challenge (ping) from the server
#================================================

sub CMD_CHL
{
        my $self = shift;
        my @data = @_;

	#Thanks Siebe for writing the subs to
	#create the QRY reply data
        my $qryhash = CreateQRYHash( $data[1] );

        $self->sendraw( 'QRY', 'PROD0090YUAUV{2B 32' . "\r\n" . $qryhash );
}

#================================================
# a response to our QRY
#================================================

sub CMD_QRY
{
	 my $self = shift;
	 my @data = @_;
}

#================================================
# a response to our PNG
#================================================

sub CMD_QNG
{
	my $self = shift;
	my @data = @_;

	$self->{PongTime} = time;
}

#================================================
# Utility function for removing header from a message
#================================================

sub _strip_header
{
        my $msg = shift;

         if ($msg =~ /^(.*?)\r\n\r\n(.*?)$/s)
        {
                my ($head, $msg) = ($1,$2);
                my @temp = split (/\r\n/, $head);
                my $header = {};
                foreach my $item (@temp)
                {
                        my ($key,$value) = split(/:\s*/,$item);
                        $header->{$key} = $value || "";
                }

                return $header,$msg;
        }
        return {}, $msg;
}

#================================================
# Internal methods for authentication
#================================================

sub authenticate
{
    my ($self, $challenge)  = @_;
    #$challenge = {map { split '=' } split(',', $challenge)} ;
    my ($user, $pass) = (uri_escape($self->{Handle}), uri_escape($self->{Password}));

    my $ua = LWP::UserAgent->new;
    $ua->agent('MSMSGS');
    $self->debug( "Authenticating : https://nexus.passport.com/rdr/pprdr.asp" );
    my ($DALogin) = $ua->get('https://nexus.passport.com/rdr/pprdr.asp')->{'_headers'}->{'passporturls'} =~ m/DALogin=(.*?),/;
    $self->debug( "Authenticating : https://$DALogin" );
    my $sslobj = $ua->get("https://$DALogin", 'Authorization' => "Passport1.4 OrgVerb=GET,OrgURL=http%3A%2F%2Fmessenger.msn.com,sign-in=$user,pwd=$pass,$challenge");
    if($sslobj->is_success) {
        if($sslobj->header('Location')){
            $ua->header('Authorization' => "Passport1.4 OrgVerb=GET,OrgURL=http%3A%2F%2Fmessenger.msn.com,sign-in=$user,pwd=$pass,$challenge");
            $sslobj = $ua->get($sslobj->header('Location'), 'Authorization' => "Passport1.4 OrgVerb=GET,OrgURL=http%3A%2F%2Fmessenger.msn.com,sign-in=$user,pwd=$pass,$challenge");
        }
        $sslobj->{'_headers'}->{'authentication-info'} =~ m/(t=.*?)\'/;
        return $1;
    }
    else{
         $self->serverError( "Authentication Error: No response from Passport server" );
         return undef;
    }
}



# This piece of code was written by Siebe Tolsma (Copyright 2004, 2005).
# Based on documentation by ZoRoNaX.
# 
# This code is for eductional purposes only. Modification, use and/or publishing this code 
# is entirely on your OWN risk, I can not be held responsible for any of the above.
# If you have questions please contact me by posting on the BOT2K3 forum: http://bot2k3.net/forum/

sub CreateQRYHash {
use Math::BigInt;
	my $chldata = shift || return;
	my $prodid  = shift || "PROD0090YUAUV{2B";
	my $prodkey = shift || "YMM8C_H7KCQ2S_KL";
	
	# Create an MD5 hash out of the given data, then form 32 bit integers from it
	my @md5hash = unpack("a16a16", md5_hex("$chldata$prodkey"));
	my @md5parts = MD5HashToInt("$md5hash[0]$md5hash[1]");

	# Then create a valid productid string, divisable by 8, then form 32 bit integers from it
	my @chlprodid = CHLProdToInt("$chldata$prodid" . ("0" x (8 - length("$chldata$prodid") % 8)));

	# Create the key we need to XOR
	my $key = KeyFromInt(@md5parts, @chlprodid);
	
	# Take the MD5 hash and split it in two parts and XOR them
	my $low  = substr(Math::BigInt->new("0x$md5hash[0]")->bxor($key)->as_hex(), 2);
	my $high = substr(Math::BigInt->new("0x$md5hash[1]")->bxor($key)->as_hex(), 2);

	# Return the string, make sure both parts are padded though if needed
	return ("0" x (16 - length($low))) . $low . ("0" x (16 - length($high))) . $high;
}

sub KeyFromInt {
	# We take it the first 4 integers are from the MD5 Hash
	my @md5 = splice(@_, 0, 4);	
	my @chlprod = @_;

	# Create a new series of numbers
	my $key_temp = Math::BigInt->new(0);
	my $key_high = Math::BigInt->new(0);
	my $key_low  = Math::BigInt->new(0);
	
	# Then loop on the entries in the second array we got in the parameters
	for(my $i = 0; $i < scalar(@chlprod); $i+=2) {
		# Make $key_temp zero again and perform calculation as described in the documents
		$key_temp->bzero()->badd($chlprod[$i])->bmul(0x0E79A9C1)->bmod(0x7FFFFFFF)->badd($key_high);
		$key_temp->bmul($md5[0])->badd($md5[1])->bmod(0x7FFFFFFF);

		# So, when that is done, work on the $key_high value :)
		$key_high->bzero()->badd($chlprod[$i + 1])->badd($key_temp)->bmod(0x7FFFFFFF);
		$key_high->bmul($md5[2])->badd($md5[3])->bmod(0x7FFFFFFF);

		# And add the two parts to the low value of the key
		$key_low->badd($key_temp)->badd($key_high);
	}

	# At the end of the loop we should add the dwords and modulo again
	$key_high->badd($md5[1])->bmod(0x7FFFFFFF);
	$key_low->badd($md5[3])->bmod(0x7FFFFFFF);

	# Byteswap the keys, left shift (32) the high value and then add the low value
	$key_low  = unpack("I*", reverse(pack("I*", $key_low )));
	$key_high = unpack("I*", reverse(pack("I*", $key_high)));

	return $key_temp->bzero()->badd($key_high)->blsft(32)->badd($key_low);
}

# Takes an CHLData + ProdID + Padded string and chops it in 4 bytes. Then converts to 32 bit integers 
sub CHLProdToInt { return map { unpack("I*", $_) } unpack(("a4" x (length($_[0]) / 4)), $_[0]); }

# Takes an MD5 string and chops it in 4. Then "decodes" the HEX and converts to 32 bit integers. After that it ANDs
sub MD5HashToInt { return map { unpack("I*", pack("H*", $_)) & 0x7FFFFFFF } unpack(("a8" x 4), $_[0]); }

return 1;
__DATA__