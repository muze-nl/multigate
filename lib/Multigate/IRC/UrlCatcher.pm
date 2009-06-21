# Declare our package
package Multigate::IRC::UrlCatcher;

use strict;
use warnings;
use POE;
use POE::Component::IRC::Plugin qw( PCI_EAT_NONE );
use POE::Component::IRC::Common qw(:ALL);

our $VERSION = '0.01';

sub new {
	return bless { }, shift;
}

sub PCI_register {
	my( $self, $irc ) = @_;
	$irc->plugin_register( $self, 'SERVER', qw(public topic ctcp_action) );
	return 1;
}

sub PCI_unregister {
	return 1;
}

sub S_ctcp_action {
	my ($self, $irc) = splice @_, 0, 2;
	my $sender = parse_user(${ $_[0] });
	my $recipients = ${ $_[1] };
	my $msg = ${ $_[2] };

	for my $recipient (@{ $recipients }) {
		urlgrab($sender,$msg);
	}

	return PCI_EAT_NONE;
}

sub S_public {
	my ($self, $irc) = splice @_, 0, 2;
	my $sender = parse_user(${ $_[0] });
	my $channels = ${ $_[1] };
	my $msg = ${ $_[2] };

	for my $chan (@{ $channels }) {
		urlgrab($sender,$msg);
	}
	return PCI_EAT_NONE;
}

sub S_topic {
	my ($self, $irc) = splice @_, 0, 2;
	my $changer = parse_user(${ $_[0] });
	my $chan = ${ $_[1] };
	my $new_topic = ${ $_[2] };

	urlgrab($changer,$new_topic) unless $new_topic eq '';

	return PCI_EAT_NONE;
}


sub urlgrab {

	my ($sender,$line) = shift @_;
	my $url = 0;

	if ( $line =~ /(http:\/\/\S+)/i ) {
		$url = 1;
	}
	elsif ( $line =~ /(www\.\S+)/i ) {
		$url = 1;
	}
	elsif ( $line =~ /ftp:\/\/(\S+)/i ) {
		$url = 1;
	}

	print "INCOMING irc 2system!system\@local !msg urlcatcher $sender $line\n" if $url ==1;
}



