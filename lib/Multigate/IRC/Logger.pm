package Multigate::IRC::Logger;

use base (POE::Component::IRC::Plugin::Logger);

use POSIX qw(strftime);

use File::Spec::Functions qw( catfile);
use POE::Component::IRC::Common qw( l_irc );

use strict;
use warnings;


sub new {
	my ($package, %args) = @_;
	my $self = $package->SUPER::new(%args);
	# add overrides for Format config here
	return $self;
}

sub _log_entry {
	my ($self, $context, $type, @args) = @_;
	my ($date, $time) = split / /, (strftime '%F %R', localtime);
	my $case = $self->{irc}->isupport('CASEMAPPING');
	$context = l_irc($context, $case);

	if ($context =~ /^[#&+!]/) {
		return if !$self->{Public};
	}
	else {
		return if !$self->{Private};
	}

	return if !defined $self->{Format}->{$type};

	my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) =
	      localtime(time);
	my $month = (
		'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
		'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
	)[$mon];
	$year += 1900;
	my $logdate = $mday . $month . $year;


	my $log_file;
	$log_file = catfile($self->{Path}, "$context.$logdate");

	$log_file = $self->_open_log($log_file);

	if (!$self->{logging}->{$context}) {
		$self->{logging}->{$context} = 1;
	}
	my $line = "[$time] " . $self->{Format}->{$type}->(@args);
	print $log_file $self->_normalize($line) . "\n";
	return;
}

1;
