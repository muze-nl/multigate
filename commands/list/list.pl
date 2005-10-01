#!/usr/bin/perl -w

use strict;
use Cwd;

chdir('..');
my $dirname  = getcwd();
my $helpfile = shift @ARGV;
my @topics   = ();
my $file;

opendir( DIR, $dirname ) or die "can't opendir $dirname: $!";
while ( defined( $file = readdir(DIR) ) ) {
    if ( -x "$dirname/$file/$file.pl" ) {
        push @topics, $file;
    }
}
closedir(DIR);

# print "Available commands:\n";
my $topic;
foreach $topic ( sort @topics ) {
    print $topic. " ";
}
print "\n";
