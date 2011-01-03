#!/usr/bin/perl -w
#
# (C) 2000 - 2005 Wieger Opmeer, Casper Joost Eyckelhof, Yvo Brevoort
#
# This package is free software; you can redistribute it and/or modify it
# under the terms of the "Artistic License".
#

use strict;
use lib './lib/';

#User management from multigate
use Multigate::Users;

#make a connection to the user-database
Multigate::Users::init_users_module();

my $protocol = $ARGV[0];

if ( $protocol !~ /^\w+$/ ) {
    print "Argument $protocol does not appear to have a valid name\n";
    exit 1;
}

print
"Adding $protocol to database in 10 seconds, if $protocol exists, all addresses will be deleted!\n";
print "Hit ^c to abort\n";
sleep 10;

my $res = Multigate::Users::add_protocol($protocol);

print "Added $protocol\n";

#cleanup
Multigate::Users::cleanup_users_module();
