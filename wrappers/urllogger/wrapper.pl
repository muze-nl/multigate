#!/usr/bin/perl
#
# (C) 2000 - 2009 Wieger Opmeer, Casper Joost Eyckelhof, Yvo Brevoort
#
# This package is free software; you can redistribute it and/or modify it
# under the terms of the "Artistic License".
#

use strict;
use warnings;

# The urllogger wrapper logs all the urls in the messages sent to it.
# The irc wrapper sends al messages with urls in it to the urlcatcher herd,
# so the urllogger wrapper can be used to log the urls on irc channels

use lib 'lib';

#use Multigate;
use Multigate::Debug;
use Multigate::Config qw(readconfig getconf hasconf);
use HTML::Entities;

readconfig('multi.conf');    # reread config file on wrapper start

Multigate::Debug::setdebug("urllogger");

#my $urlfile    = "../WWW/autolinkdev.shtml";
#my $allurlfile = "../WWW/allautolinkdev.shtml";
my $urlfile    = getconf('urllogger_urlfile');
my $allurlfile = getconf('urllogger_allurlfile');


# Main loop:
while (<>) {
    unless ( defined $_ ) {

        # Error with STDIN, parent probably died...
        debug( 'urllogger', "urllogger wrapper going down. (parent died?)" );
        exit 0;
    }

    chomp;

    if ( $_ =~ /^OUTGOING urllogger urllogger (.*?) (.*?) (.*)/ ) {
        my $username = $2;
        my $line     = $3;
        my $url;

        $username = encode_entities("<$username>");
        $line = encode_entities($line);
        if ( $line =~ /(http:\/\/\S+)/i ) {
            $url = $1;
            $line =~ s/http:\/\/\S+/<a href=\"$url\">$url<\/a>/i;
        }
        elsif ( $line =~ /(www\.\S+)/i ) {
            $url = $1;
            $line =~ s/www\.\S+/<a href=\"http:\/\/$url\">$url<\/a>/i;
        }
        elsif ( $line =~ /ftp:\/\/(\S+)/i ) {
            $url = $1;
            $line =~ s/ftp:\/\/\S+/<a href=\"ftp:\/\/$url\">ftp:\/\/$url<\/a>/i;
        }

        if ( defined($url) && ( $url !~ /pooierphonies\.html/ ) ) {
            my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) =
              localtime(time);
            if ( $hour < 10 ) { $hour = "0" . $hour }
            if ( $min < 10 )  { $min  = "0" . $min }
            if ( $mon < 10 )  { $mon  = "0" . $mon }
            if ( $mday < 10 ) { $mday = "0" . $mday }
            $year += 1900;
            $mon++;
            my $logdate = "[$mday/$mon/$year $hour:$min] ";
            $line = $logdate . $username . ' ' . $line . "<br>\n";

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
            foreach my $url (@urls) {
                print URLFILE $url;
            }
            close URLFILE;
        }
    }
    elsif ( $_ =~ /^DIEDIEDIE/ ) {
        debug( 'urllogger', 'urlogger wrapper going down.' );
        exit 0;
    }

}

