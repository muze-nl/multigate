#!/usr/bin/perl -w
#
# (C) 2000 - 2005 Wieger Opmeer, Casper Joost Eyckelhof, Yvo Brevoort
#
# This package is free software; you can redistribute it and/or modify it
# under the terms of the "Artistic License".
#

use strict;

#
# globals
#

use lib "/home/multilink/multigate/lib";

my $multiroot = '/home/multilink/multigate';


#
# imports
#
use Multigate::Debug qw( debug setdebug );
use Multigate::Config qw( getconf readconfig );
use Multigate;
use Multigate::Console;
use Multigate::Wrapper;
use Multigate::Scheduler;


#
# read config
#
readconfig("$multiroot/multi.conf");


#The protocol wrappers that are started by default

my $protocolline = getconf ('default_protocols');    # space separated in config file
my @protocols = split " ", $protocolline;

# my @protocols = qw( irc jabber email icq sms msn );


#
# init
#
chdir($multiroot) or die "Cannot cd $multiroot:";
$ENV{MULTI_ROOT} = $multiroot;


#default debug 

setdebug('multicore');
setdebug('Dispatch');
setdebug('Command');
setdebug('Wrapper');
#setdebug('nbread');


#
#initialize console
#
Multigate::Console::new();


#
#initialize scheduler
#
Multigate::Scheduler::new();


#
# initialize protocol wrappers
#
my $protocol;

foreach $protocol ( @protocols ) {
	Multigate::start_wrapper( $protocol );
	setdebug( $protocol );
}


#
# mainloop!
#
Multigate::mainloop();

#
#
#
print "That's all folks!\n";

