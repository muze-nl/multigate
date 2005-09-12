#
# Config file stuff
#
# (C) 2000 - 2005 Wieger Opmeer, Casper Joost Eyckelhof, Yvo Brevoort
#
# This package is free software; you can redistribute it and/or modify it
# under the terms of the "Artistic License".
#

package Multigate::Config;

use strict;

use vars qw( $VERSION @ISA @EXPORT @EXPORT_OK %config );

use Exporter;
use IO::File;
use Multigate::Debug;

$VERSION   = '0.01';
@ISA       = qw( Exporter );
@EXPORT    = qw( getconf read_commandconfig);
@EXPORT_OK = qw( readconfig );

#Multigate::Debug::setdebug('Config');
#Multigate::Debug::setdebug('Config_debug');

### Global config#####

#
#
#
sub getconf {
    my $key = shift;

    if ( exists( $config{$key} ) ) {
        debug( 'Config_debug', "getconf returning $config{$key} for $key" );
        return $config{$key};
    }
    else {
        die "Unknown config item $key.\n";
    }
}

#
#
#
sub readconfig {
    my $configfile = shift;
    my ( $key, $val, $line );

    die "Unreadable configfile $configfile\n" unless -f $configfile and -r _;

    open CONF, "<$configfile" or die "Cannot open $configfile:";

    while (<CONF>) {
        chomp;
        next if /^\s*$/;    # empty lines
        next if /^\s*#/;
        s/(?<!\\)#.*$//;    # comments on the end of a line, not \#
        s/\\#/#/g;
        if (/\\$/) {
            chop;           # remove \
            $_ .= <CONF>;
            chomp;          # remove \n
            redo;
        }
        if (/(\w+)\s*=\s*(.+?)\s*$/) {
            $key          = $1;
            $val          = $2;
            $config{$key} = $val;
            debug( 'Config_debug', "$key: $val\n" );
        }
        else {
            debug( 'Config', "Warning: weird config line: $_" );
        }
    }

    close CONF;
}

####### Command Config ########

#
# reads the config for a command, and uses defaults for options not
# mentioned in local config
# returns a hash of option=>value

sub read_commandconfig {
    my $command                    = shift;
    my %commandconfig              = ();
    my $default_command_configfile = "commands/default.cfg";

    if ( -e $default_command_configfile ) {

        # Read defaults
        open CCONF, "<$default_command_configfile"
          or die "Cannot open $default_command_configfile:";
        while (<CCONF>) {
            chomp;
            next if /^\s*#/;
            next if /^\s*$/;    # empty lines
            s/(?<!\\)#.*$//;    # comments on the end of a line, not \#
            s/\\#/#/g;
            if (/\\$/) {
                chop;           # remove \
                $_ .= <CCONF>;
                chomp;          # remove \n
                redo;
            }
            if (/(\w+)\s*=\s*(.+?)\s*$/) {
                my $key = $1;
                my $val = $2;
                $commandconfig{$key} = $val;
                debug( 'Config_debug', "$key: $val" );
            }
            else {
                debug( 'Config', "Warning: weird config line: $_" );
            }
        }
        close CCONF;
    }
    else {

        # No default config...
        debug( 'Config', 'No default config for commands' );
    }

    if ( -e "commands/$command/command.cfg" ) {
        open CCONF, "commands/$command/command.cfg"
          or die "Cannot open commands/$command/command.cfg";
        while (<CCONF>) {
            chomp;
            next if /^\s*#/;
            next if /^\s*$/;    #empty lines
            s/#.*$//;
            if (/\\$/) {
                chop;           # remove \
                $_ .= <CCONF>;
                chomp;          # remove \n
                redo;
            }
            if (/(\w+)\s*=\s*(.+?)\s*$/) {
                my $key = $1;
                my $val = $2;
                $commandconfig{$key} = $val;
                debug( 'Config_debug', "$key: $val" );
            }
            else {
                debug( 'Config', "Warning: weird config line: $_" );
            }
        }
        close CCONF;
    }
    else {

        # No special config for command or command does not exist
        if ( -e "commands/$command/$command.pl" ) {
            debug( 'Config', "No config for $command, using defaults" );
        }
        else {
            debug( 'Config_debug', "$command does not exist" );
        }
    }
    return %commandconfig;
}

1;

