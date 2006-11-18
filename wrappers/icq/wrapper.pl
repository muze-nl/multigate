#!/usr/bin/perl -w

use lib "lib";
use strict;
use warnings;
use Getopt::Long;
use Net::OSCAR qw(:standard :loglevels);
use Digest::MD5 qw(md5);
use IO::Poll;

use Multigate::Debug;
use Multigate::NBRead;
use Multigate::Util;

use Multigate::Config qw(readconfig getconf);
readconfig('multi.conf');    # reread config file on wrapper start


# Read config from multi
my $screenname = getconf('icq_number');
my $password  = getconf('icq_pass');

eval {
	require Data::Dumper;
};
use vars qw($pid $oscar @chats @invites $loglevel $domd5 $password %fdmap $poll);

my $readline = 0;
eval {
	require Term::ReadLine;
};
if($@) {
	warn "Couldn't load Term::ReadLine -- omitting readline support: $@\n";
} else {
	$readline = 1;
}

#$Carp::Verbose = 1;
$| = 1;


my $loglevel = undef;
my $stealth = 0;
my $host = undef;

$poll = IO::Poll->new();
$poll->mask(STDIN => POLLIN);

$oscar = Net::OSCAR->new(capabilities => [qw(typing_status extended_status buddy_icons file_transfer buddy_list_transfer)], rate_manage => OSCAR_RATE_MANAGE_MANUAL);
$oscar->set_callback_error(\&error);
$oscar->set_callback_buddy_in(\&buddy_in);
$oscar->set_callback_buddy_out(\&buddy_out);
$oscar->set_callback_im_in(\&im_in);
$oscar->set_callback_chat_joined(\&chat_joined);
$oscar->set_callback_chat_buddy_in(\&chat_buddy_in);
$oscar->set_callback_chat_buddy_out(\&chat_buddy_out);
$oscar->set_callback_chat_im_in(\&chat_im_in);
$oscar->set_callback_chat_invite(\&chat_invite);
$oscar->set_callback_buddy_info(\&buddy_info);
$oscar->set_callback_evil(\&evil);
$oscar->set_callback_chat_closed(\&chat_closed);
$oscar->set_callback_buddylist_error(\&buddylist_error);
$oscar->set_callback_buddylist_ok(\&buddylist_ok);
$oscar->set_callback_buddylist_changed(\&buddylist_changed);
$oscar->set_callback_admin_error(\&admin_error);
$oscar->set_callback_admin_ok(\&admin_ok);
$oscar->set_callback_rate_alert(\&rate_alert);
$oscar->set_callback_new_buddy_icon(\&new_buddy_icon);
$oscar->set_callback_buddy_icon_downloaded(\&buddy_icon_downloaded);
$oscar->set_callback_buddy_icon_uploaded(\&buddy_icon_uploaded);
$oscar->set_callback_typing_status(\&typing_status);
$oscar->set_callback_extended_status(\&extended_status);
$oscar->set_callback_signon_done(\&signon_done);
$oscar->set_callback_auth_challenge(\&auth_challenge);
$oscar->set_callback_im_ok(\&im_ok);
$oscar->set_callback_stealth_changed(\&stealth_changed);
$oscar->set_callback_buddy_icq_info(\&buddy_icq_info);
$oscar->set_callback_connection_changed(\&connection_changed);
$oscar->set_callback_buddylist_in(\&buddylist_in);

$oscar->loglevel($loglevel) if defined($loglevel);

# I specify local_port 5190 so that I can sniff that one port and get all OSCAR
# traffic, including direct connections.
my %so_opts;
%so_opts = (screenname => $screenname, password => $password, stealth => $stealth, local_port => 5190);

if(defined($host)) {
	$so_opts{host} = $host;
}

$oscar->signon(%so_opts);



my $inline = "";
my $inchar = "";
while(1) {
	next unless $poll->poll();

	my $got_stdin = 0;
	my @handles = $poll->handles(POLLIN | POLLOUT | POLLHUP | POLLERR | POLLNVAL);
	foreach my $handle (@handles) {
		if(fileno($handle) == fileno(STDIN)) {
			$got_stdin = 1;
		} else {
			my($read, $write, $error) = (0, 0, 0);
			my $events = $poll->events($handle);
			$read = 1 if $events & POLLIN;
			$write = 1 if $events & POLLOUT;
			$error = 1 if $events & (POLLNVAL | POLLERR | POLLHUP);

			$fdmap{fileno($handle)}->log_print(OSCAR_DBG_DEBUG, "Got r=$read, w=$write, e=$error");
			$fdmap{fileno($handle)}->process_one($read, $write, $error);
		}
	}
	next unless $got_stdin;

	sysread(STDIN, $inchar, 1);
	if($inchar eq "\n") {
    	if ($inline =~ /^OUTGOING icq (.*?) (.*)/) {
			my $target = $1;
			my $message = $2;
            $message =~ s/\xb6/\r\n/g;

			my $ret = $oscar->send_im($target, $message);
			#print STDERR "Sending IM $ret to $target...\n";
		}
		if ($inline =~ /^DIEDIEDIE/) {
			exit;
		}
        $inchar = "";
        $inline = "";
	} else {
		$inline .= $inchar;
	}
}


sub error($$$$$) {
	my($oscar, $connection, $errno, $error, $fatal) = @_;
	if($fatal) {
		die "Fatal error $errno in ".$connection->{description}.": $error\n";
	} else {
		#print STDERR "Error $errno: $error\n";
	}
}

sub signon_done($) {
	my $oscar = shift;
	print "You are now signed on to AOL Instant Messenger.\n";
}

sub typing_status($$$) {
	my($oscar, $who, $status) = @_;
	#print STDERR "We received typing status $status from $who.\n";
}

sub extended_status($$) {
	my($oscar, $status) = @_;
	#print STDERR "Our extended status is $status.\n";
}

sub rate_alert($$$) {
	my($oscar, $level, $clear, $window) = @_;

	$clear /= 1000;
	#print STDERR "We received a level $level rate alert.  Wait for about $clear seconds.\n";
}

sub buddylist_error($$$) {
	my($oscar, $error, $what) = @_;
	#print STDERR "Error $error occured while $what on your buddylist\n";
}

sub buddylist_ok($) {
	#print STDERR "Your buddylist was modified successfully.\n";
}

sub admin_error($$$$) {
	my($oscar, $reqtype, $error, $errurl) = @_;

	#print STDERR "Your $reqtype request was unsuccessful (", 0+$error, "): $error.";
	#print STDERR "  See $errurl for more info." if $errurl;
	#print STDERR "\n";
}

sub admin_ok($$) {
	my($oscar, $reqtype) = @_;

	print "Your $reqtype request was successful.\n";
}

sub new_buddy_icon($$$) {
	my($oscar, $screenname, $buddat) = @_;
	print "$screenname claims to have a new buddy icon.\n";
}

sub buddy_icon_downloaded($) {
	my($oscar, $screenname, $icon) = @_;

	print "Buddy icon for $screenname downloaded...\n";
	open(ICON, ">/tmp/$screenname.$$.icon") or do {
		print "Couldn't open /tmp/$screenname.$$.icon for writing: $!\n";
		return;
	};
	print ICON $icon;
	close ICON;
	print "Icon written to /tmp/$screenname.$$.icon.\n";
}

sub buddy_icon_uploaded($) {
	my($oscar) = @_;

	print "Your buddy icon was successfully uploaded.\n";
}

sub chat_closed($$$) {
	my($oscar, $chat, $error) = @_;
	for(my $i = 0; $i < @chats; $i++) {
		next unless $chats[$i] == $chat;
		splice @chats, $i, 1;
	}
	#print STDERR "Connection to chat ", $chat->{name}, " was closed: $error\n";
}

sub buddy_in($$$$) {
	shift;
	my($screenname, $group, $buddat) = @_;
	print "Got buddy $screenname from $group\n";
}

sub chat_buddy_in($$$$) {
	shift;
	my($screenname, $chat, $buddat) = @_;
	print "Got buddy $screenname from chat ", $chat->{name}, ".\n";
}

sub buddy_out($$$) {
	shift;
	my($screenname, $group) = @_;
	print "Lost buddy $screenname from $group\n";
}

sub chat_buddy_out($$$) {
	shift;
	my($screenname, $chat) = @_;
	print "Lost buddy $screenname from chat ", $chat->{name}, ".\n";
}

sub im_in($$$) {
	shift;
	my($who, $what, $away) = @_;
	if($away) {
		$away = "[AWAY] ";
	} else {
		$away = "";
	}
	#print STDERR "$who: $away$what\n";

    $what =~ s/\r\n/\xb6/g;
    $what =~ s/\r/\n/g;
    $what =~ s/\n/\xb6/g;
                        
	print "INCOMING icq $who $what\n";
}

sub chat_im_in($$$$) {
	shift;
	my($who, $chat, $what) = @_;
	#print STDERR "$who in ".$chat->{name}.": $what\n";

    $what =~ s/\r\n/\xb6/g;
    $what =~ s/\r/\n/g;
    $what =~ s/\n/\xb6/g;
            
	print "INCOMING icq $who $what\n";
}

sub chat_invite($$$$$) {
	shift;
	my($from, $msg, $chat, $chaturl) = @_;
	my $invnum = push @invites, $chaturl;
	$invnum--;
	print "$from has invited us to chat $chat.  Use command accept_invite $invnum to accept.\n";
	print "Invite message: $msg\n";
}

sub chat_joined($$$) {
	shift;
	my($name, $chat) = @_;
	push @chats, $chat;
	print "You have joined chat $name.  Its chat number is ".(scalar(@chats)-1)."\n";
}

sub evil($$$) {
	shift;
	my($newevil, $enemy) = @_;
	$enemy ||= "Anonymous";
	print "$enemy has just evilled you!  Your new evil level is $newevil%.\n";
}

sub buddy_info($$$) {
	shift;
	my($screenname, $buddat) = @_;
	my $membersince = $buddat->{membersince} ? localtime($buddat->{membersince}) : "";
	my $onsince = localtime($buddat->{onsince});

	my $extra = "";
	$extra .= " [TRIAL]" if $buddat->{trial};
	$extra .= " [AOL]" if $buddat->{aol};
	$extra .= " [FREE]" if $buddat->{free};
	$extra .= " [AWAY]" if $buddat->{away};

	$extra .= "\nMember Since: $membersince" if $membersince;
	$extra .= "\nIdle Time (secs): " . (time()-$buddat->{idle_since}) if exists($buddat->{idle_since}) and defined($buddat->{idle_since});
	if($buddat->{capabilities}) {
		$extra .= "\nCapabilities:";
		$extra .= "\n\t$_" foreach values %{$buddat->{capabilities}};
	}

	my $profile = "";
	if($buddat->{awaymsg}) {
		$profile = <<EOF
---------------------------------
Away message
---------------------------------
$buddat->{awaymsg}
EOF
	} elsif($buddat->{profile}) {
		$profile = <<EOF
---------------------------------
Profile
---------------------------------
$buddat->{profile}
EOF
	}

	print <<EOF;
=================================
Buddy info for $screenname
---------------------------------
EOF
print "Extended Status: $buddat->{extended_status}\n" if exists($buddat->{extended_status});
print <<EOF;
Flags: $extra
On Since: $onsince
Evil Level: $buddat->{evil}%
$profile
=================================
EOF
}

sub auth_challenge($$$) {
	my($oscar, $challenge, $hashstr) = @_;
	my $md5 = Digest::MD5->new;
	$md5->add($challenge);
	$md5->add(md5($password));
	$md5->add($hashstr);
	$oscar->auth_response($md5->digest, 5.5);
}

sub im_ok($$$) {
	my($oscar, $to, $reqid) = @_;
	print "Your message, $reqid, was sent to $to.\n";
}

sub stealth_changed($$) {
	my($oscar, $stealth_state) = @_;
	print "Stealth state changed to $stealth_state.\n";
}

sub buddy_icq_info($$$) {
	my($oscar, $uin, $info) = @_;
	print "Got ICQ info for $uin: " . Data::Dumper::Dumper($info) . "\n";
}

sub connection_changed($$$) {
	my($oscar, $connection, $status) = @_;

	my $h = $connection->get_filehandle();
	return unless $h;
	$connection->log_printf(OSCAR_DBG_DEBUG, "State changed (FD %d) to %s", fileno($h), $status);
	my $mask = 0;

	if($status eq "deleted") {
		delete $fdmap{fileno($h)};
	} else {
		$fdmap{fileno($h)} = $connection;
		if($status eq "read") {
			$mask = POLLIN;
		} elsif($status eq "write") {
			$mask = POLLOUT;
		} elsif($status eq "readwrite") {
			$mask = POLLIN | POLLOUT;
		}
	}

	$poll->mask($h => $mask);
}

sub buddylist_in($$$) {
	my($oscar, $sender, $list) = @_;
	print "Got buddylist from $sender\n";
	print "================================\n";

	foreach my $group (sort keys %$list) {
		print "$group:\n";
		foreach my $buddy (sort @{$list->{$group}}) {
			print "\t$buddy\n";
		}
	}
}

sub buddylist_changed($@) {
	my($oscar, @changes) = @_;

	print "Buddylist was changed:\n";
	foreach (@changes) {
		printf("\t%s: %s %s\n",
			$_->{action},
			$_->{type},
			($_->{type} == MODBL_WHAT_BUDDY) ? ($_->{group} . "/" . $_->{buddy}) : $_->{group}
		);
	}
}
