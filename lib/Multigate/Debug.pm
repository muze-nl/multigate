#
# Debug
#
# (C) 2000 - 2005 Wieger Opmeer, Casper Joost Eyckelhof, Yvo Brevoort
#
# This package is free software; you can redistribute it and/or modify it
# under the terms of the "Artistic License".
#

package Multigate::Debug;

use strict;

use vars qw( $VERSION @ISA @EXPORT @EXPORT_OK $all %cats );

use Exporter;

@ISA       = qw( Exporter );
@EXPORT    = qw( debug );
@EXPORT_OK = qw( setdebug unsetdebug listdebug );
$VERSION   = '0.02';

#
#
#
sub debug {
    my $cat = shift;
    if ( $all or $cats{$cat} ) {

        # Create timestamp;
        my ( $sec, $min, $hour ) = localtime();

        # first collate all output to work around bugs in stdio
        my $output =
          sprintf( "[%02d:%02d] <%s> %s\n", $hour, $min, $cat, join( '', @_ ) );

        print STDERR $output;
    }
}

#
#
#
sub setdebug {
    my $cat = shift;
    unless ( $cats{$cat} ) {    # unless already enabled
        print STDERR "Setting debug: $cat\n";
        $cats{$cat} = 1;
    }
}

#
#
#
sub unsetdebug {
    my $cat = shift;
    delete $cats{$cat};
}

#
#
#
sub listdebug {
    return keys %cats;
}

1;

