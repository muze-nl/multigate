#
# Accounting stuff
#
# (C) 2000 - 2005 Wieger Opmeer, Casper Joost Eyckelhof, Yvo Brevoort
#
# This package is free software; you can redistribute it and/or modify it
# under the terms of the "Artistic License".
#

package Multigate::Accounting;

use strict;
use vars qw( @ISA @EXPORT $VERSION );
use Exporter;

#use POSIX;

use lib './lib';
use Multigate::Debug;
use Multigate::Config;

@ISA     = qw( Exporter );
@EXPORT  = qw( account check_account account_log);
$VERSION = '0.01';

#
# Check for sufficient funds
#
sub check_account {
    my $user    = shift;
    my $account = shift;

    return 'ack';    # For now...
}

#
# Appends logging to a file, tab-delimited
#
# FIXME: persistent filehandle? open once, write many :)
#
sub account_log {
    my ( $command, $realsender, $protocol, $address, $time, $units, $status,
        $extra )
      = @_;
    my $accountlogdir = getconf('accountlog');
    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) =
      localtime(time);
    $year += 1900;
    $mon++;
    my $logname    = "accountlog-$year-$mon-$mday.log";
    my $accountlog = "$accountlogdir/$logname";
    open ACCOUNTLOG, ">>$accountlog"
      or return ("Cannot open accountlog $accountlog");    #better than dying?
    print ACCOUNTLOG
"$command\t$realsender\t$protocol\t$address\t$time\t$units\t$status\t$extra\n";
    close ACCOUNTLOG;
}

1;

