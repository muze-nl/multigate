#
# NBRead.pm: Non Blocking Read routines...
#
# (C) 2000 - 2005 Wieger Opmeer, Casper Joost Eyckelhof, Yvo Brevoort
#
# This package is free software; you can redistribute it and/or modify it
# under the terms of the "Artistic License".
#

package Multigate::NBRead;

use strict;

use vars qw( $VERSION @ISA @EXPORT %fh_buf );

use Exporter;
use POSIX;

use Multigate::Debug;

@ISA     = qw( Exporter );
@EXPORT  = qw( nbread make_non_blocking bufferstatus);
$VERSION = '0.01';

#
# Little helper function...
#
sub make_non_blocking {
    my $fh = shift;
    $fh->autoflush(1);
    fcntl( $fh, F_SETFL(), O_NONBLOCK() )
      or warn 'Could not make $fh non_blocking';
}

#
# get status of buffers, for console..
#
sub bufferstatus {
    my @result = ();
    foreach my $fh ( keys %fh_buf ) {
        push @result, "fh: $fh -> " . length( $fh_buf{$fh} ) . " bytes\n";
    }
    return @result;
}

#
# non blocking read, now with nice and shiny comments!
#
sub nbread {
    my $fh = shift;
    my ( $num, $buf );

    $fh_buf{$fh} = '' unless $fh_buf{$fh};

    if ( $fh_buf{$fh} =~ /^(.*?\n)/s ) {
        $fh_buf{$fh} = $';
        return
          $1;  # return everything up to (and including) first newline in buffer
    }
    else {
        $num = sysread( $fh, $buf, 1024 );
        if ( defined $num ) {    # undefined -> error reading
            debug( 'nbread', "nbread: read $num bytes on fh $fh" );
            if ( $num == 0 ) {

                # fh closed, nothing more to read.

                if ( $fh_buf{$fh} ) {

                    # something left in buffer, this is a bug!
                    debug( 'nbread',
"nbread: filehandle ($fh) closed but something left in buffer!?"
                    );
                }

                debug( 'nbread', "sysread: filehandle $fh closed." );
                delete
                  $fh_buf{$fh};    # this filehandle should not be here anymore
                return
                  undef;    # should trigger a call to close-handler in mainloop

            }
            else {
                $fh_buf{$fh} .= $buf;
                if ( $fh_buf{$fh} =~ /^(.*?\n)/s ) {
                    $fh_buf{$fh} = $';
                    return
                      $1
                      ; # return everything up to (and including) first newline in buffer
                }
            }
        }

        # fall through: nothing read (temporary error) or no full line
        # return 'false', mainloop will try again when select triggers
        return '';
    }
}

1;

