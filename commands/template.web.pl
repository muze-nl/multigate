#!/usr/bin/perl -w
use strict;
use LWP::UserAgent;
use HTML::Entities();

## Import available environment variables

my $address   = $ENV{'MULTI_USER'};        # address of invoking user
my $user      = $ENV{'MULTI_REALUSER'};    # multigate username of invoking user
my $userlevel = $ENV{'MULTI_USERLEVEL'};   # userlevel of invoking user
my $from_protocol = $ENV{'MULTI_FROM'}; # protocol this command was invoked from
my $to_protocol   = $ENV{'MULTI_TO'};   # protocol where output will be sent
my $command_level = $ENV{'MULTI_COMMANDLEVEL'};  # level needed for this command

my $commandline = defined $ARGV[0] ? $ARGV[0] : '';

## Get a certain URL
my $url = "http:// ";

my $ua = new LWP::UserAgent;

#Set agent name, we are not a script! :)
my $agent = "Mozilla/4.0 (compatible; MSIE 4.01; Windows 98)";
$ua->agent($agent);

my $request = new HTTP::Request( 'GET', $url );
my $content = $ua->request($request)->content;

my @lines = split /^/m, $content;

foreach my $line (@lines) {
    if ( $line =~ / /i ) {    # if it matches something
                              # do something
    }
}

# print something,
# use escape like this: $result = HTML::Entities::decode($result);
