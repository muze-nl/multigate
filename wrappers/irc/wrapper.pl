#!/usr/bin/perl -w
#
#  Based on: irctest
#     (Sample Net::IRC script that starts a vapid little annoybot.)
#
#  Heavily edited by Casper Joost Eyckelhof (Titanhead)
#  To create a very simple bot, which can serve as a frontend to multigate
#  October 2000 until February 2001 (and further...)

use strict;
use lib 'lib/';
use Net::IRC;
use IO::Handle;
use IO::File;
use Data::Dumper;

#User management from multigate
use Multigate::Users;
use Multigate::Debug;
use Multigate::NBRead;
use Multigate::Util;

#############Initialisation and stuff#######################

use Multigate::Config qw(readconfig getconf);
readconfig('multi.conf');    # reread config file on wrapper start

my $dev = getconf('dev');    #development version does not capture url's

my @channels = split /\s+/, getconf('irc_channel');
map { $_ = "#" . $_ if ( $_ =~ /^\w/ ) } @channels;    #default start channel with #
map { $_ = lc($_) } @channels;                         #all channels lower case

my $versionstring = getconf('irc_version');            # reply to CTCP Version
my $nick          = getconf('irc_nick');
my $server        = getconf('irc_server');

# Flush early
$| = 1;

# Reconnection parameters
my $recon_start   = 10;
my $recon_inc     = 5;
my $recon_current = $recon_start;

#Boy, are we random!
srand();

#Install signal handler
$SIG{INT}  = \&catch_zap;
$SIG{ALRM} = \&catch_alarm;

#  Create the IRC and Connection objects

my $logdir          = "logs";
my $urlfile         = "../WWW/autolink.shtml";
my $allurlfile      = "../WWW/allautolink.shtml";
my $quitmessagefile = "wrappers/irc/quitmessages.txt";

## Globals for floodprotection
my $tokens   = 3;
my $lasttime = time();

##

my $irc = new Net::IRC;

#make a connection to the user-database
Multigate::Users::init_users_module();

my $conn = $irc->newconn(
    Server    => $server,
    Port      => 6663,
    Nick      => $nick,
    Ircname   => 'Multigate',
    Username  => 'multilink',
    LocalAddr => 'ringbreak.dnd.utwente.nl'
  )
  or die "IRC: Can't connect to IRC server.\n";

#Global hash of hashes of nick=>user@host
my %users = ();

#Global hash of hashes of operators: nick=>boolean  (true, if nick is an operator)
my %operators = ();

#Global hash of arrays of queued +o nicks
my %opqueues = ();

my %sendqueue = ();    # $destination => @lines

## Open the logfiles
my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime(time);
my $month = ( 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec' )[$mon];
$year += 1900;
my $logdate    = $mday . $month . $year;
my $currentday = $mday;
my %logfiles   = ();

foreach my $chan (@channels) {
    $chan = lc($chan);    # all logiles in lowercase, even with mixed case channel names
    $logfiles{$chan} = IO::File->new();
    debug( "irc", "Trying to open logfile for $chan" );
    $logfiles{$chan}->open(">>$logdir/$chan\.$logdate") or debug( "irc", "Error opening $logfiles{$chan}" );
    $logfiles{$chan}->autoflush(1);
}

#temporary:
Multigate::Debug::setdebug('irc');

# Pre select a quit message for the day that we die
# Quitmessages are in a file (my $epitaph :)

open( QUITFILE, "< $quitmessagefile" );
my @quitmessages = <QUITFILE>;
my $quitmessage  = @quitmessages[ int( rand(@quitmessages) ) ];
close QUITFILE;
debug( 'irc', "If irc ever gets killed, it will say: $quitmessage" );

###############    end of initialisation ##################

#Signal handler, give a nice quitmessage and clean up the mess
sub catch_zap {
    my $signame = shift;
    $conn->quit($quitmessage);
    Multigate::Users::cleanup_users_module();
    foreach my $chan ( keys %logfiles ) {
        $logfiles{$chan}->close;
    }
    die "Somebody sent me, the irc module,  a SIG $signame !";
}

# removes a channel from the channel array
# yes, a hash would be saner, but introduces some problems elsewhere

sub remove_channel {
    my $channel     = shift;
    my @newchannels = ();
    foreach my $chan (@channels) {
        if ( $chan !~ /^$channel$/i ) {
            push @newchannels, $chan;
        }
    }
    @channels = @newchannels;
}

#give all nicks in global @opqueue operator status
#triggered by a SIG ALRM
#There is a race condition here, but not life treathening :)
sub catch_alarm {
    foreach my $channel ( keys %opqueues ) {
        my @opjes = @{ $opqueues{$channel} };

        #at this point a name might be added to opqueue in another method...
        $opqueues{$channel} = [ () ];

        #...which will be lost here

        #remove duplicates (caused by people on multiple channels that we join...)
        #thanks to cookbook:
        my %seen = ();
        my @uniq = grep { !$seen{$_}++ } @opjes;

        #give +o in groups of 3 nicks
        while ( my @three = splice @uniq, 0, 3 ) {
            my $os = "o" x @three;
            $conn->mode( $channel, "+" . $os, @three );
            debug( 'irc', "opjes uitdelen: +$os @three" );
        }
    }
}

#Writes argument to logfile (prefixed with the time)
sub logfile {
    my ( $channel, $logline ) = @_;
    $channel = lc($channel);    # "#DnD" != "#dnd", *sigh*
    unless ( defined( $logfiles{$channel} ) ) {
        debug( 'irc', "No logfile for $channel. Creating." );
        $logfiles{$channel} = IO::File->new();
        $logfiles{$channel}->open(">>$logdir/$channel\.$logdate")
          or debug( "irc", "Error opening $logfiles{$channel}" );
        $logfiles{$channel}->autoflush(1);
    }

    #we need to know the time etc:
    ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime(time);

    #The day may have ended...
    if ( $mday != $currentday ) {
        $month = ( 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec' )[$mon];
        $year += 1900;
        $logdate = $mday . $month . $year;
        foreach my $chan (@channels) {
            $logfiles{$chan}->close;    #close current;
            undef( $logfiles{$chan} );

            debug( 'irc', "Creating new logfile \"$logdir/$chan\.$logdate\"" );
            $logfiles{$chan} = IO::File->new();
            $logfiles{$chan}->open(">>$logdir/$chan\.$logdate")
              or debug( "irc", "Error opening $logfiles{$chan}" );
            $logfiles{$chan}->autoflush(1);
        }
        $currentday = $mday;
    }

    #prettify   
    if ( $hour < 10 ) { $hour = "0" . $hour }
    if ( $min < 10 )  { $min  = "0" . $min }
    $logfiles{$channel}->print("[$hour:$min] $logline");
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
    } elsif ( $line =~ /(www\.\S+)/i ) {
        $url = $1;
        $line =~ s/www\.\S+/<a href=\"http:\/\/$url\">$url<\/a>/i;
    } elsif ( $line =~ /ftp:\/\/(\S+)/i ) {
        $url = $1;
        $line =~ s/ftp:\/\/\S+/<a href=\"ftp:\/\/$url\">ftp:\/\/$url<\/a>/i;
    }

    #print "URL: $url\n";
    if ( defined($url) && ( $url !~ /pooierphonies\.html/ ) ) {
        ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime(time);
        if ( $hour < 10 ) { $hour = "0" . $hour }
        if ( $min < 10 )  { $min  = "0" . $min }
        if ( $mon < 10 )  { $mon  = "0" . $mon }
        if ( $mday < 10 ) { $mday = "0" . $mday }
        $year += 1900;
        $mon++;
        $logdate = "[$mday/$mon/$year $hour:$min] ";
        $line    = $logdate . $line . "<br>\n";

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
            print STDOUT "INCOMING irc 2system!system\@local !msg urlcatcher $origline\n";
        }
    }
}

#adduser adds a user to the userlist and gives the user operator status, if allowed
#Both %users and %operators are updated, they should be in one datastructure
#actually (or object even), but this is so easy :) I just have to keep them in sync myself
#3 parameters: a channel, a nick and a userhost
sub adduser {
    my ( $channel, $nick, $userhost ) = @_;
    $channel = lc($channel);

    #Get rid of those funny characters in front of userhost replies
    $userhost =~ s/^[\+\-\^\~]*//;

    $users{$channel}{$nick} = $userhost;

    #Now lets check his userlevel according to multigate
    my ( $id, $level ) = Multigate::Users::get_user( "irc", "$nick!$userhost" );

    #We probably need a lot of sanity checking here, but what the hell, we do it later
    if ( $level >= 100 ) {

        #this person deserves operator status!
        debug( 'irc', "This $nick $userhost ($id) deserves operator status on $channel" );
        $operators{$channel}{$nick} = 1;
        push @{ $opqueues{$channel} }, $nick;
        alarm(5);    #wait 4 to 5 seconds, if called within 5 seconds, it's reset at 5
    } else {

        #We do not like this person :)
        $operators{$channel}{$nick} = 0;
        debug( 'irc', "This $nick $userhost ($id) does not deserve operator status on $channel" );
    }
}

#The brother of adduser, removes a user from the usertables
sub removeuser {
    my ( $channel, $nick ) = @_;
    $channel = lc($channel);

    #FIXME, any checking?
    if ( defined($nick) && defined( $users{$channel}{$nick} ) ) {
        delete $users{$channel}{$nick};
        delete $operators{$channel}{$nick};
    }
}

#returns the most recent nick for a given userhost
# by reversing the %users hash
# But only if the given nick does not exist in %users
sub getnick {
    my ( $oldnick, $userhost ) = @_;

    #too many errors, until fixed, don't change anything
    return $oldnick;

    if ( !defined($userhost) ) {
        $userhost = "nobody\@nowhere.org";
    }
    my %sresu = reverse %users;
    if ( defined $sresu{$userhost} && !( defined $users{$oldnick} ) ) {
        debug( 'irc_debug', "irc: " . $sresu{$userhost} . " will be used instead of $oldnick" );
        return $sresu{$userhost};
    } else {
        return $oldnick;
    }
}

# Here are the handler subroutines. Fascinating, huh?
# The more interesting handlers for this module are last in the list, so scroll
# down fast :)

# What to do when the bot successfully connects.
sub on_connect {
    my $self = shift;
    foreach my $channel (@channels) {

        # Join our channel
        debug( 'irc', "Joining channel \"$channel\"" );
        $self->join($channel);
        logfile( $channel, "*** Joining channel $channel\n" );
    }
    $recon_current = $recon_start;
}

# Handles some messages you get when you connect
sub on_init {
    my ( $self, $event ) = @_;
    my (@args) = ( $event->args );
    shift (@args);
}

# What to do when someone leaves a channel the bot is on.
# Mostly bookkeeping 
sub on_part {
    my ( $self, $event ) = @_;
    my $leavingnick = ( $event->args )[0];
    my $channel     = ( $event->to )[0];

    # get rid of this nick in the usertables
    delete $users{$channel}{$leavingnick};
    delete $operators{$channel}{$leavingnick};

    debug( 'irc_debug', "$leavingnick removed from tables" );
    logfile( $channel, "$leavingnick left $channel.\n" );
}

# What to do when someone is kicked
sub on_kick {
    my ( $self, $event ) = @_;

    #print STDERR Dumper($event);
    my $kickednick = ( $event->to )[0];
    my $kicker     = ( $event->from )[0];
    my $channel    = ( $event->args )[0];
    my $reason     = ( $event->args )[1];

    # from is the kicker!userhost, args[0] is the channel and args[1]  the kickmessage
    # get rid of this nick in the usertables
    delete $users{$channel}{$kickednick};
    delete $operators{$channel}{$kickednick};

    debug( 'irc_debug', "$kickednick removed from tables" );
    $kicker =~ s/^(.*?)!.*$/$1/;
    logfile( $channel, "$kicker kicked $kickednick: \"$reason\"\n" );

    #what if we were kicked ourselves? HACK:
    if ( lc($kickednick) eq lc($nick) ) {
        sleep( $recon_current + rand($recon_inc) );    #no auto-reconnect ;)
        $conn->join( lc($channel) );
        debug( 'irc', "We were kicked by $kicker ($reason). Attempting to rejoin..." );
    }
}

# What to do when someone joins a channel the bot is on.
sub on_join {
    my ( $self, $event ) = @_;
    my ($channel) = ( $event->to )[0];
    my ( $nick, $userhost ) = ( $event->nick, $event->userhost );

    # Add this user to the userlist     
    adduser( $channel, $nick, $userhost );
    logfile( $channel, "$nick ($userhost) joined $channel.\n" );
}

# Prints the names of people in a channel when we enter.
sub on_names {
    my ( $self, $event )   = @_;
    my ( @list, $channel ) = ( $event->args );    # eat yer heart out, mjd!

    # splice() only works on real arrays. Sigh.
    ( $channel, @list ) = splice @list, 2;

    # $list[0] now contains a space separated list of nicknames
    debug( 'irc', "Users on $channel: $list[0]" );
    my @nicklist = split /\s/, $list[0];

    #add to %users with unknown user@host    
    foreach my $nick (@nicklist) {
        $users{$channel}{$nick} = 'nobody@nowhere.org';
    }

    # ask the server for information on all inhabitants
    # the replies from the server will be handled in "on_userhost_reply"
    # RFC 1459 allows us to send max 5 names at once
    while ( my @five = splice @nicklist, 0, 5 ) {
        $self->userhost(@five);
        sleep(1);    # You know what? Lets not flood!
    }

}

# Handles user_host_replies from the server (that we initiated)
# I guess we can trust the server, so we use these replies to update our
# user table. 

sub on_userhost_reply {
    my ( $self,   $event )     = @_;
    my ( $tonick, $userhosts ) = $event->args;

    # @users contains all userhost replies from the irc-server
    my @users = split /\s/, $userhosts;
    foreach my $user (@users) {
        $user =~ /(.*?)=(.*?)$/;
        my $nick     = $1;
        my $userhost = $2;
        debug( 'irc', "$nick is $userhost" );
        foreach my $channel ( keys %users ) {
            if ( defined $users{$channel}{$nick} ) {    #user is on channel
                    #Add this user to the lists
                adduser( $channel, $nick, $userhost );
            }
        }
    }
}

# What to do if we get a notice... Nothing seems a wise cause of action :)
sub on_notice {
    my ( $self, $event ) = @_;
    $event->dump;
}

# Yell about incoming CTCP PINGs.
# "The querying client can then subtract the recieved timestamp from the
#  current time to obtain the delay between clients over the IRC network."

sub on_ping {
    my ( $self, $event ) = @_;
    my $nick = $event->nick;
    my $args = ( $event->args )[0];

    #sanity, tsd found another parse bug:
    $args =~ s/[^a-zA-Z0-9 ]//gm;

    my $reply = "PING $args";

    # Ugly way of doing _some_ excess flood protection
    # Limit replies to 40 characters (like mIRC)
    $self->ctcp_reply( $nick, substr( $reply, 0, 40 ) );

    debug( 'irc', "*** CTCP PING request from $nick received" );
}

sub on_version {
    my ( $self, $event ) = @_;
    my $nick = $event->nick;

    $self->ctcp_reply( $nick, "VERSION $versionstring" );
    debug( 'irc', "*** CTCP VERSION request from $nick received" );
}

# Gives lag results for outgoing PINGs.
sub on_ping_reply {
    my ( $self, $event ) = @_;
    my ($args) = ( $event->args )[1];
    my ($nick) = $event->nick;

    $args = time - $args;
}

# Change our nick if someone stole it.
sub on_nick_taken {
    my ($self) = shift;
    $self->nick( substr( $self->nick, -1 ) . substr( $self->nick, 0, 8 ) );
}

#mode is changed on channel... parsing might be ugly
# $event->args[0] contains the +oo-v etc list
# $event->args[1..n] contains the respective arguments
# RFC2811 is a bitch :)

sub on_mode {
    my ( $self, $event ) = @_;
    my @args       = $event->args;
    my $nick       = $event->nick;
    my $channel    = ( $event->to )[0];
    my $modestring = shift @args;         #what can it contain? +,-,o,v,b,s,n,t,k and much more
                                          #some have arguments, some don't :(

    #The modes that we know; 0 => no argument; 1 => argument
    my %modes = (
        o => "1",
        b => "1",
        v => "1",
        I => "1",
        k => "1",
        e => "1",
        l => "1",
        n => "0",
        s => "0",
        t => "0",
        i => "0",
        m => "0"
    );
    my $add = 1;    # '+' => 1; '-' => 0

    #parse one character at the time
    my $c;
    foreach $c ( split //, $modestring ) {
        if ( $c eq '+' ) {
            $add = 1;
        } elsif ( $c eq '-' ) {
            $add = 0;
        } elsif ( defined $modes{$c} ) {    #we know this mode
            if ( $modes{$c} ) {    #this mode has an argument
                my $argument = shift @args;
                if ( $c eq 'o' ) {
                    $operators{$channel}{$argument} = $add;
                }
            }
        } else {

            #unparsable mode string detected
            debug( 'irc', "modestring \"$modestring\" not recognized" );
            return 0;
        }
    }
    return 1;
}

# Someone changed his/her nick. We need to update the user-tables
sub on_nick {
    my ( $self, $event ) = @_;

    # print STDERR Dumper($event);
    # old and new are complete nick!userhost thingies
    # actually old and new are the same... bug in NET::IRC
    my ( $old, $new ) = ( $event->from, $event->to );
    my ( $oldnick, $dummy )    = split /!/, $old, 2;
    my ( $newnick, $userhost ) = split /!/, $new, 2;

    # workaround bug....
    $newnick = ( $event->args )[0];

    foreach my $channel ( keys %users ) {
        if ( defined $users{$channel}{$oldnick} ) {    #user is actually on that channel
            if ( $operators{$channel}{$oldnick} ) {    #deze heeft al ops, zelf adduser dingetjes doen:
                $userhost =~ s/^[\+\-\^\~]*//;
                $users{$channel}{$newnick}     = $userhost;
                $operators{$channel}{$newnick} = 1;
                debug( 'irc_debug', "$oldnick is now known as $newnick. Already has ops" );
            } else {
                adduser( $channel, $newnick, $userhost );
                debug( 'irc_debug', "$oldnick is now known as $newnick. No ops?" );
            }

            #altijd oude nick weggooien
            removeuser( $channel, $oldnick );
            logfile( $channel,    "$old is now known as $newnick.\n" );
        }
    }
}

# Displayed formatted CTCP ACTIONs once
sub on_action {
    my ( $self, $event ) = @_;
    my ( $nick, @args ) = ( $event->nick, $event->args );
    my $channel = ( $event->to )[0];

    logfile( $channel, "Action: $nick @args\n" );

    #Catch possible URL's
    urlgrab("&lt;$nick&gt; @args");
}

# Reconnect to the server when we die.
sub on_disconnect {
    my ( $self, $event ) = @_;
    debug( 'irc', "Disconnected from ", $event->from(), " (", ( $event->args() )[0], "). Attempting to reconnect..." );

    foreach my $channel (@channels) {
        logfile( $channel,
            "Disconnected from " . $event->from() . " (" . ( $event->args() )[0] . "). Attempting to reconnect...\n" );
    }

    while ( !$self->connected() ) {
        sleep($recon_current);
        $self->connect();
        debug( 'irc', "Attempting to reconnect..." );
        $recon_current += $recon_inc;
    }
    $recon_current = $recon_start;
}

# Look at the topic for a channel you join.  
sub on_topic {
    my ( $self, $event ) = @_;
    my ($nick) = $event->nick;
    my ($arg)  = ( $event->args );

    # Note the use of the same handler sub for different events.

    if ( $event->type() eq 'notopic' ) {

        # print "No topic set for $args[1].\n";
        # If it's being done _to_ the channel, it's a topic change.
    } elsif ( ( $event->type() eq 'topic' ) and ( $event->to()->[0] ne '' ) ) {
        logfile( $event->to()->[0], "Topic change for " . $event->to()->[0] . " by $nick : $arg\n" );
        urlgrab("&lt;$nick&gt; $arg");
        #print STDERR Dumper($event);
    } else {

        # print "The topic for $args[1] is \"$args[2]\".\n";
    }
}

# What to do when we receive a private PRIVMSG.
sub on_msg {
    my ( $self, $event ) = @_;
    my ($nick) = $event->nick;
    my ($arg)  = ( $event->args );
    my $userhost = $event->userhost;

    # Is there any reason to send to send lines that do not start
    # with an '!' to multigate?
    # Should this client know about multigate at all?
    if ( $arg =~ /^!.*?$/ ) {
        if ( $arg =~ /^!irc_(\w+)\s(.*?)$/i ) {    #een irc specifiek commando
            my ( $command, $args ) = ( $1, $2 );
            $userhost =~ s/^(\+|-)?(\^|~)?//;    #funny characters...
            irc_command( $command, "$nick\!$userhost", $args );
        } else {
            print "INCOMING irc #\!$nick\!$userhost $arg\n";
        }

        # Speciale gevallen waarin we commando's op irc willen onderscheppen
        # Het is een vieze hack, maar het is ook maar een irc-botje... 
        if ( $arg =~ /^!pizza open(.*?)$/i ) {
            push @{ $sendqueue{'#dnd'} }, "Pizza geopend (door $nick)";

            #$conn->privmsg( "#dnd", "Pizza geopend (door $nick)" );
        }
    }

}

# What to do when we receive channel text.
sub on_public {
    $| = 1;    #shouldn't be necessary... but won't hurt
    my ( $self, $event ) = @_;
    my @to = $event->to;
    my ( $nick, $mynick ) = ( $event->nick, $self->nick );
    my ($arg) = ( $event->args );
    my $user    = $event->userhost;
    my $channel = ( $event->to )[0];

    $channel = lc($channel);

    # Note that $event->to() returns a list (or arrayref, in scalar
    # context) of the message's recipients, since there can easily be
    # more than one.

    # Is there any reason to send to send lines that do not start
    # with an '!' to multigate?
    # Should this client know about multigate at all?
    if ( $arg =~ /^!.*?$/ ) {
        print "INCOMING irc $channel\!$nick\!$user $arg\n";
    }

    #Log it:
    logfile( $channel, "<$nick> $arg\n" );

    #Catch possible URL's
    urlgrab("&lt;$nick&gt; $arg");
}

# What to do when we receive a quitmessage.
sub on_quit {
    my ( $self, $event ) = @_;
    my ($nick) = $event->nick;
    my ($arg)  = ( $event->args );
    my $userhost = $event->userhost;
    my $channel = ( $event->to )[0];
                    
    #Log it:
#    logfile( $channel, "*** $nick [$userhost] has quit [$arg]\n"); 
    # FIXME: ($event->to)[0] is not the channel, but the user. Where is the channel hidden so we can log it?
}


#
# Executes irc-commands (say, kick, topic, etc) if user is allowed to
# irc-command ( command, user, args );
#
sub irc_command {
    my ( $command, $userhost, $args ) = @_;

    my $channel = $channels[0];
    if ( $args =~ /^(#\w+) (.*)$/ ) {
        $channel = lc($1);
        $args    = $2;
    }

    #check userlevel
    my ( $id, $level ) = Multigate::Users::get_user( "irc", "$userhost" );
    debug( 'irc', "IRC-Command ($command, $args) by $userhost ($id) level: $level" );

    if ( $level >= 500 ) {
        if ( $command eq "say" ) {
            $conn->privmsg( $channel, $args );
        } elsif ( $command eq "topic" ) {
            $conn->topic( $channel, $args );
        } elsif ( $command eq "action" ) {
            $conn->ctcp( 'ACTION', $channel, $args );
        } elsif ( $command eq "kick" ) {
            my ( $nick, $reason ) = split /\s/, $args, 2;
            $reason = "By request" unless defined($reason);
            $conn->kick( $channel, $nick, $reason );
        } elsif ( $command eq "op" ) {
            $conn->mode( $channel, "+o", $args );
        } elsif ( $command eq "join" ) {
            $conn->join($args);
            push @channels, $args;
        } elsif ( $command eq "leave" ) {
            my ( $channel, $reason ) = split /\s/, $args, 2;
            $conn->part($channel);
            remove_channel($channel);
        }

        #FIXME,TODO Add more commands...
    }
}

#
# uses some globals to calculate a sleep-time, to prevent floods
# just some heuristics for now. can be done much better 
#
sub irc_sleep {
    my $now = time();

    #reclaim tokens
    if ( ( $now - $lasttime ) >= 60 ) {    #all tokens back after 1 minute of silence
        $tokens = 4;
    } elsif ( ( $now - $lasttime ) >= 30 ) {
        $tokens++;
    }

    if ( $tokens > 0 ) {    # tokens left
        $tokens--;    # use one
        return;       # no sleep
    } else {
        select( undef, undef, undef, 0.9 );
    }
}

sub do_stdin {
    my $fd = shift;
    my $line;

    while ( $line = nbread($fd) ) {
        handle_incoming($line);    #put in global sendqueue
                                   #handle global sendqueue

        while ( keys %sendqueue ) {
            foreach my $destination ( keys %sendqueue ) {
                my $line = shift @{ $sendqueue{$destination} };
                unless ( @{ $sendqueue{$destination} } ) {
                    delete $sendqueue{$destination};    #ready with this destination
                    debug( 'irc_debug', "Deleted $destination from sendqueue" );
                }
                $conn->privmsg( $destination, $line );

                #select how long we want to sleep
                irc_sleep();
                $lasttime = time();

                #get fresh lines somehow:
                $irc->do_one_loop();
            }
        }
    }
    unless ( ( defined $line ) ) {

        # $fh (STDIN) has closed... should we do something now?
        $conn->quit("Scan parent");
        Multigate::Users::cleanup_users_module();
        foreach my $chan ( keys %logfiles ) {
            $logfiles{$chan}->close;
        }
        debug( 'irc', "Quitting. (parent died?)" );
        exit 0;
    }
}

# Someone gave us a command
# Could look like:
# OUTGOING irc destination some text
# OUTGOING * can contain a special character to indicate a newline FIXME
# destination can have 5 different formats, I know, that's ugly, but it was
# the only way I could think of, to keep the irc-garbage out of multigate
# itself.
# everything else will be handled after those 5 cases as normal client behaviour

sub handle_incoming {
    my $input = shift;

    if ( defined($input) && ( $input ne "" ) && ( length($input) > 0 ) ) {

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
            #FIXME: this only matches channels that just contain normal characters...
            if ( $to_parse =~ /^(#\w+)!(.*?)!(.*?)\s(.*)/ ) {
                $channel     = $1;
                $destination = $2;
                $userhost    = $3;
                $msg         = $4;

                #format: #!nick!user@host message , this should go to nick
            } elsif ( $to_parse =~ /^#!(.*?)!(.*?)\s(.*)/ ) {
                $channel     = "#";
                $destination = $1;
                $userhost    = $2;
                $msg         = $3;

                #HACK!
                if ( $destination =~ /\|Joop\|/i ) {
                    debug( 'irc_debug', "Adding joop-stuff" );
                    $msg = "Didn't get the hint? Write your own bot! Don't steal without asking.";
                }

                #format: #channel message , this should go to #channel
            } elsif ( $to_parse =~ /^(#\S+)\s(.*)/ ) {
                $destination = $1;
                $channel     = $destination;
                $msg         = $2;

                #format: nick!user@host message , this should go to the person that matches
            } elsif ( $to_parse =~ /^(\S*?)!(\S*?)\s(.*)/ ) {
                $channel     = "#";
                $destination = $1;
                $userhost    = $2;
                $msg         = $3;

                #format: nick message , this should go to nick (actually the same as #channel message)
            } elsif ( $to_parse =~ /^(.*?)\s(.*)/ ) {
                $channel     = "#";
                $destination = $1;
                $userhost    = "nobody\@nowhere.org";    #let's hope he doesn't visit our channel ;)
                $msg         = $2;
            }

            #multiline messages: \xb6 is internal line seperator
            my @lines = split /\xb6/, $msg;

            #The userhost has precedence over destination (we might know a more
            #recent nick)
            $destination = getnick( $destination, $userhost );
            if ( $channel =~ /^#\w+/ ) { $destination = $channel }

            # Attention: an extra newline to prettify the console (blocks of text)
            debug( 'irc_debug', "destination: $destination. channel:$channel." );
            foreach my $line (@lines) {
                foreach my $sline ( cut_pieces( $line, 445 ) ) {

                    #No empty lines, this _should_ be filtered at a higher level...
                    if ( defined($sline) && ( length $sline > 0 ) ) {

                        # Add to sendqueue
                        push @{ $sendqueue{$destination} }, $sline;
                        if ( $destination eq $channel ) {
                            logfile( $channel, "<$nick> $sline\n" );
                        }
                    }
                }
            }
        } elsif ( $input =~ /^DIEDIEDIE/ ) {

            #We have to stop...
            $conn->quit($quitmessage);
            Multigate::Users::cleanup_users_module();
            foreach my $chan ( keys %logfiles ) {
                $logfiles{$chan}->close;
            }
            exit 0;
        }

        ### Using it directly as a client.
        ### Fixme, what is current channel?

        #Het is een message
        elsif ( $input =~ /^\/msg\s(.*?)\s(.*?)\n/i ) {
            my $nick = $1;
            my $msg  = $2;
            $conn->privmsg( $nick, $msg );
        }

        #Het is een action
        elsif ( $input =~ /^\/me\s(.*?)\n/i ) {
            my $action  = $1;
            my $channel = $channels[0];
            $conn->ctcp( 'ACTION', $channel, $action );
        }

        #Het is een kick
        elsif ( $input =~ /^\/kick\s(.*?)\s(.*?)\n/i ) {
            my $nick    = $1;
            my $reason  = $2;
            my $channel = $channels[0];
            $conn->kick( $channel, $nick, $reason );
        }

        #Het is een ban
        elsif ( $input =~ /^\/ban\s(.*?)\n/i ) {
            my $nick    = $1;
            my $channel = $channels[0];
            $conn->mode( $channel, '+b ', $nick );
        }

        #Het is een mode
        elsif ( $input =~ /^\/mode\s(.*?)\s(.*?)\s(.*?)\n/i ) {
            my $target     = $1;
            my $mode       = $2;
            my $parameters = $3;
            $conn->mode( $target, $mode, $parameters );
        }

        #Het is een topic
        elsif ( $input =~ /^\/topic\s(.*?)\n/i ) {
            my $topic   = $1;
            my $channel = $channels[0];
            $conn->topic( $channel, $topic );
        }

        #Het is een quit
        elsif ( $input =~ /^\/quit(\s(.*?)){0,1}\n/i ) {
            my $reason = $1;
            $conn->quit($reason);
            Multigate::Users::cleanup_users_module();
            exit 0;
        }

        #Het is een nick
        elsif ( $input =~ /^\/nick\s(.*?){1,9}\n/i ) {
            my $newnick = $1;
            $conn->nick($newnick);
        }

        #Het is iets anders: gooi maar naar kanaal 
        else {
            my $channel = $channels[0];
            $conn->privmsg( $channel, $input );
        }

    } else {    # read from stdin went wrong?
        die "aargh";
    }
}

# Initialize handlers for all events

$conn->add_handler( 'cping',    \&on_ping );
$conn->add_handler( 'crping',   \&on_ping_reply );
$conn->add_handler( 'msg',      \&on_msg );
$conn->add_handler( 'public',   \&on_public );
$conn->add_handler( 'caction',  \&on_action );
$conn->add_handler( 'join',     \&on_join );
$conn->add_handler( 'part',     \&on_part );
$conn->add_handler( 'kick',     \&on_kick );
$conn->add_handler( 'topic',    \&on_topic );
$conn->add_handler( 'notopic',  \&on_topic );
$conn->add_handler( 'notice',   \&on_notice );
$conn->add_handler( 'nick',     \&on_nick );
$conn->add_handler( 'cversion', \&on_version );
$conn->add_handler( 'mode',     \&on_mode );
$conn->add_handler( 'quit',     \&on_quit );

$conn->add_global_handler( [ 251, 252, 253, 254, 302, 255 ], \&on_init );
$conn->add_global_handler( 'disconnect', \&on_disconnect );
$conn->add_global_handler( 376,          \&on_connect );
$conn->add_global_handler( 433,          \&on_nick_taken );
$conn->add_global_handler( 353,          \&on_names );
$conn->add_global_handler( 302,          \&on_userhost_reply );

my $stdin = new IO::Handle;
$stdin->fdopen( fileno(STDIN), 'r' );
make_non_blocking($stdin);

#$irc->addfh( \*STDIN, \&do_stdin, "r" );
$irc->addfh( $stdin, \&do_stdin, "r" );

# Guess what? We start! :)
$irc->start();
