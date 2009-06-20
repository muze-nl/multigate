#!/usr/bin/perl

use warnings;
use strict;

use lib 'lib/';

use POE;
use POE::Component::IRC::State;
use POE::Component::IRC::Plugin::AutoJoin;
use POE::Component::IRC::Plugin::NickReclaim;
use POE::Component::IRC::Plugin::CycleEmpty;
use POE::Component::IRC::Plugin::CTCP;
#use POE::Component::IRC::Plugin::Logger;
use Multigate::IrcLogger;
use POE::Component::IRC::Plugin::Connector;

#User management from multigate
use Multigate::Users;
use Multigate::Debug;
use Multigate::NBRead;
use Multigate::Util;

use Data::Dumper;

#############Initialisation and stuff#######################

use Multigate::Config qw(readconfig getconf hasconf);
readconfig('multi.conf');    # reread config file on wrapper start

# VARS
my ( $irc, $console );       # POA parts
my $diediedie = 0;                                     # disconnect part of diediedie procedure ?
my $dev       = getconf('dev');                        #development version does not capture url's

my $irc_flood    = 0;
my $irc_oper     = undef;
my $irc_operpass = undef;
my %channels     = ();

my $quitmessagefile = "wrappers/irc/quitmessages.txt";
my $quitmessage = 'This poor wrapper has to die.';
my $urlfile         = "./web/autolink.shtml";
my $allurlfile      = "./web/allautolink.shtml";

my $logdir          = "logs";

#make a connection to the user-database
Multigate::Users::init_users_module();

#temporary:
Multigate::Debug::setdebug('irc');


sub irc_start {
	debug( 'irc', "Starting irc" );

	srand();
	open( QUITFILE, "< $quitmessagefile" );
	my @quitmessages = <QUITFILE>;
	my $quitmessage  = @quitmessages[ int( rand(@quitmessages) ) ];
	close QUITFILE;
	debug( 'irc', "If irc ever gets killed, it will say: $quitmessage" );


	my @confchannels  = split /\s+/, getconf('irc_channel');

	map { $_ = "#" . $_ if ( $_ =~ /^\w/ ) } @confchannels;    #default start channel with #
	map { $_ = lc($_) } @confchannels;                         #all channels lower case

	foreach my $channel (@confchannels) {
		$channels{$channel} = '';
		if(hasconf("irc_chankey_" . substr($channel, 1))) {
			$channels{$channel} = getconf("irc_chankey_" . substr($channel, 1));
		}
	}

	if ( hasconf('irc_flood') ) {
		debug('irc','irc_flood is set');
		$irc_flood = getconf('irc_flood');
	}

	if ( hasconf('irc_oper') ) {
		$irc_oper     = getconf('irc_oper');
		$irc_operpass = getconf('irc_operpass');
	}

	$irc = POE::Component::IRC::State->spawn(
		Nick     => getconf('irc_nick'),
		Server   => getconf('irc_server'),
		Username => 'Multilink',
		Ircname  => 'Multilink',
		Port     => getconf('irc_port'),
		Flood    => $irc_flood,
	);

	$irc->plugin_add( 'AutoJoin', POE::Component::IRC::Plugin::AutoJoin->new( Channels => \%channels ) );
	$irc->plugin_add( 'NickReclaim' => POE::Component::IRC::Plugin::NickReclaim->new( poll => 30 ) );

	$irc->plugin_add( 'CycleEmpty', POE::Component::IRC::Plugin::CycleEmpty->new() );
	$irc->plugin_add( 'Connector', POE::Component::IRC::Plugin::Connector->new() );
	#$irc->plugin_add('Logger', POE::Component::IRC::Plugin::Logger->new(
	$irc->plugin_add('Logger', Multigate::IrcLogger->new(
			Path    => $logdir,
			Private => 0,
			Public  => 1,
			Sort_by_date => 1,

		));


	# Create and load our CTCP plugin
	# TODO: add useful info
	$irc->plugin_add( 'CTCP' => POE::Component::IRC::Plugin::CTCP->new(
			version => '2.0',
			userinfo => "Multilink"
		));



	$irc->yield( register => 'all' );
	$irc->yield('connect');
}


sub irc_msg {
	my ( $nick, $hostmask ) = ( split /!/, $_[ARG0] );
	my $message = $_[ARG2];

	if ( $message =~ /^!.*?$/ ) {
		if ( $message =~ /^!irc_(\w+)\s(.*?)$/i ) {    #een irc specifiek commando
			my ( $command, $args ) = ( $1, $2 );
			debug( 'irc', "!irc_ cmd ($message)" );

			$hostmask =~ s/^(\+|-)?(\^|~)?//;      #funny characters...
			irc_command( $command, "$nick\!$hostmask", $args );
		} else {
			print "INCOMING irc #\!$nick\!$hostmask $message\n";
		}
	}
}

sub irc_public {
	my ( $nick, $hostmask ) = ( split /!/, $_[ARG0] );
	my $channel = $_[ARG1][0];
	my $message = $_[ARG2];

	$channel = lc($channel);

	if ( $message =~ /^!.*?$/ ) {
		print "INCOMING irc $channel\!$nick\!$hostmask $message\n";
	}

	urlgrab("&lt;$nick&gt; $message");
}

sub irc_topic {
	my ( $nick, $hostmask ) = ( split /!/, $_[ARG0] );
	my $msg = $_[ARG2];

	urlgrab("&lt;$nick&gt; $msg") unless $msg eq '';

}

sub irc_ctcp_action {
	my ( $nick, $hostmask ) = ( split /!/, $_[ARG0] );
	my $msg = $_[ARG2];
	urlgrab("&lt;$nick&gt; $msg") unless $msg eq '';
}



sub irc_disconnected {
	if ( $diediedie == 1 ) {
		exit 0;
	} else {
		#irc_start();
	}
}

sub irc_nick_sync {
	my $nick    = $_[ARG0];
	my $channel = $_[ARG1];
	if ( $nick ne $irc->nick_name() && !$irc->is_channel_operator( $channel, $nick ) ) {
		my $info = $irc->nick_info($nick);
		adduser( $channel, $nick, $info->{'Userhost'} );
	}
}

sub irc_chan_sync {
	my $channel = $_[ARG0];
	my $snick;
	debug( 'irc', "channel $channel is in sync" );
	if ( $irc->is_channel_operator( $channel, $irc->nick_name() ) ) {
		foreach $snick ( $irc->channel_list($channel) ) {
			if ( !$irc->is_channel_operator( $channel, $snick ) ) {
				my $info = $irc->nick_info($snick);
				adduser( $channel, $snick, $info->{'Userhost'} );
			}
		}
	}
}

sub irc_chan_mode {
	my ( $nick, $hostmask ) = ( split /!/, $_[ARG0] );    # de gene die de mode zet
	my $channel = $_[ARG1];
	my $mode    = $_[ARG2];
	my $target  = $_[ARG3];
	debug( 'irc', "chan mode event nick = $nick , hostmask = $hostmask channel = $channel , mode = $mode , target = $target" );
	if ( $target eq $irc->nick_name() && $mode eq "+o" ) {
		my $snick;
		foreach $snick ( $irc->channel_list($channel) ) {
			if ( !$irc->is_channel_operator( $channel, $snick ) ) {
				my $info = $irc->nick_info($snick);
				adduser( $channel, $snick, $info->{'Userhost'} );
			}
		}
	}
}

sub console_start {
	print STDERR "start console\n";

	$console = POE::Wheel::ReadWrite->new(
		InputHandle  => \*STDIN,
		OutputHandle => \*STDOUT,
		InputEvent   => "console_input",
	);
}

sub console_input {
	my ( $heap, $input, $wheel_id ) = @_[ HEAP, ARG0, ARG1 ];

	#First we check for multigate commands ("OUTGOING irc")
	if ( $input =~ /^OUTGOING\sirc\s(.*?)$/ ) {
		my $to_parse = $1;
		my $channel;
		my $destination;
		my $userhost;
		my $msg;

		#Because of the way irc handles control characters, we need some sanity checking
		$to_parse =~ s/\cM//g;
		$to_parse =~ s/\cA//g;
		$to_parse =~ s/\cJ//g;
		$to_parse =~ s/\cB//g;

		#irc sucks, with all those nicks, channels and hostmasks
		#we can get several messages (OUTGOING irc something)
		#the something will be parsed here

		#format: #channel!nick!user@host message , this should go to #channel
		if ( $to_parse =~ /^(#[^!]+)!(.*?)!(.*?)\s(.*)/ ) {
			$channel     = $1;
			$destination = $2;
			$userhost    = $3;
			$msg         = $4;

		}
		#format: #!nick!user@host message , this should go to nick
		elsif ( $to_parse =~ /^#!(.*?)!(.*?)\s(.*)/ ) {
			$channel     = "#";
			$destination = $1;
			$userhost    = $2;
			$msg         = $3;

		}
		#format: #channel message , this should go to #channel
		elsif ( $to_parse =~ /^(#\S+)\s(.*)/ ) {
			$destination = $1;
			$channel     = $destination;
			$msg         = $2;

		}
		#format: nick!user@host message , this should go to the person that matches
		elsif ( $to_parse =~ /^(\S*?)!(\S*?)\s(.*)/ ) {
			$channel     = "#";
			$destination = $1;
			$userhost    = $2;
			$msg         = $3;

		}
		#format: nick message , this should go to nick (actually the same as #channel message)
		elsif ( $to_parse =~ /^(.*?)\s(.*)/ ) {
			$channel     = "#";
			$destination = $1;
			$userhost    = "nobody\@example.org";    #let's hope he doesn't visit our channel ;)
			$msg         = $2;
		}

		#multiline messages: \xb6 is internal line seperator
		my @lines = split /\xb6/, $msg;

		#The userhost has precedence over destination (we might know a more
		#recent nick)
		#TODO fix this $destination = getnick( $destination, $userhost );
		if ( $channel =~ /^#\w+/ ) { $destination = $channel }

		# Attention: an extra newline to prettify the console (blocks of text)
		foreach my $line (@lines) {
			# Add to sendqueue

			foreach my $sline (cut_pieces($line,445)) {
				$irc->yield( privmsg => $destination => $sline );
			}
		}
	} elsif ( $input =~ /^DIEDIEDIE/ ) {
		$diediedie = 1;
		$irc->call( 'quit' => $quitmessage );
	}
}

sub adduser {
	my ( $channel, $nick, $userhost ) = @_;
	$channel = lc($channel);

	#Get rid of those funny characters in front of userhost replies
	$userhost =~ s/^[\+\-\^\~]*//;

	#Now lets check his userlevel according to multigate
	my ( $id, $level ) = Multigate::Users::get_user( "irc", "$nick!$userhost" );

	#We probably need a lot of sanity checking here, but what the hell, we do it later
	if ( $level >= 100 ) {

		#this person deserves operator status!
		debug( 'irc', "This $nick $userhost ($id) deserves operator status on $channel" );
		$irc->yield( 'mode' => $channel => '+o' => $nick );

	} else {
		#We do not like this person :)
		debug( 'irc', "This $nick $userhost ($id) does not deserve operator status on $channel" );
	}
}

#
# Executes irc-commands (say, kick, topic, etc) if user is allowed to
# irc-command ( command, user, args );
#
sub irc_command {
	my ( $command, $nickuserhost, $args ) = @_;

	my $channel = (keys %channels)[0];
	if ( $args =~ /^([#!+][^ ]+) (.*)$/ ) {
		$channel = lc($1);
		$args    = $2;
	}

	#check userlevel
	my ( $id, $level ) = Multigate::Users::get_user( "irc", "$nickuserhost" );
	debug( 'irc',
		"IRC-Command ($command, $args) by $nickuserhost ($id) level: $level" );

	if ( $level >= 500 ) {
		if ( $command eq "say" ) {
			$irc->yield( privmsg => $channel => $args);
		}
		elsif ( $command eq "topic" ) {
			$irc->yield(topic => $channel => $args);
		}
		elsif ( $command eq "action" ) {
			$irc->yield(ctcp => $channel, "ACTION $args");
		}
		elsif ( $command eq "kick" ) {
			my ( $nick, $reason ) = split /\s/, $args, 2;
			$reason = "By request" unless defined($reason);
			$irc->yield(kick => $channel => $nick => $reason);
		}
		elsif ( $command eq "op" ) {
			$irc->yield(mode => $channel => "+o" => $args);
		}
		elsif ( $command eq "join" ) {
			$irc->yield(join => $args);
		}
		elsif ( $command eq "leave" ) {
			my ( $channel, $reason ) = split /\s/, $args, 2;
			$irc->yield(part => $channel);
		}
	}
}

#If there is an url in the string, it will be written to a file
#actually 2 files: 'last 100' and 'all'
sub urlgrab {

    if ($dev) { return }

    my $line     = shift;
    my $origline = $line;
    my $url;

    $line =~ s/>/&gt;/g;
    $line =~ s/</&lt;/g;
    if ( $line =~ /(http:\/\/\S+)/i ) {
        $url = $1;
        $line =~ s/http:\/\/\S+/<a href=\"$url\">$url<\/a>/i;
    }
    elsif ( $line =~ /(www\.\S+)/i ) {
        $url = $1;
        $line =~ s/www\.\S+/<a href=\"http:\/\/$url\">$url<\/a>/i;
    }
    elsif ( $line =~ /ftp:\/\/(\S+)/i ) {
        $url = $1;
        $line =~ s/ftp:\/\/\S+/<a href=\"ftp:\/\/$url\">ftp:\/\/$url<\/a>/i;
    }

    #print "URL: $url\n";
    if ( defined($url) && ( $url !~ /pooierphonies\.html/ ) ) {
        my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) =
          localtime(time);
        if ( $hour < 10 ) { $hour = "0" . $hour }
        if ( $min < 10 )  { $min  = "0" . $min }
        if ( $mon < 10 )  { $mon  = "0" . $mon }
        if ( $mday < 10 ) { $mday = "0" . $mday }
        $year += 1900;
        $mon++;
        my $logdate = "[$mday/$mon/$year $hour:$min] ";
        my $line    = $logdate . $line . "<br>\n";

        #add to allurlfile, easiest, just append.
        open( ALLURLFILE, ">>$allurlfile" );
        print ALLURLFILE $line;
        close ALLURLFILE;

        #read old file
        open( URLFILE, "<$urlfile" );
        my @urls = <URLFILE>;
        close URLFILE;

        #add our new line to the top
        unshift @urls, $line;
        splice @urls, 100;    #only keep first 100 entries
                              #write the file back to disk
        open( URLFILE, ">$urlfile" );
        foreach my $url (@urls) { print URLFILE $url; }
        close URLFILE;

        if ( getconf('irc_urlspam') ) {

            #send url to multigate
            # origline contains &gt; &lt;
            $origline =~ s/&gt;/>/;
            $origline =~ s/&lt;/</;
            print STDOUT
              "INCOMING irc 2system!system\@local !msg urlcatcher $origline\n";
        }
    }
}

POE::Session->create(
	package_states => [
	main => {
		_start           => 'irc_start',
		irc_nick_sync    => 'irc_nick_sync',
		irc_msg          => 'irc_msg',
		irc_public       => 'irc_public',
		irc_disconnected => 'irc_disconnected',
		irc_chan_mode    => 'irc_chan_mode',
		irc_chan_sync    => 'irc_chan_sync',
		irc_topic        => 'irc_topic',
		irc_ctcp_action  => 'irc_ctcp_action',
	}
	]
);

POE::Session->create(
	package_states => [
	main => {
		'_start'        => 'console_start',
		'console_input' => 'console_input'
	}
	]
);



$poe_kernel->run();


