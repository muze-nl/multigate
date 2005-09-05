#!/usr/bin/perl -w
use strict;

my $root = ".";

opendir( DIR, $root ) or die "can't opendir $root: $!";
while ( defined( my $file = readdir(DIR) ) ) {

    # do something with "$dirname/$file"
    next if $file =~ /^\.\.?$/;
    print "$root/$file\n";
    if ( -d "$root/$file" ) {
        open CONFIG, ">$root/$file/command.cfg"
          or die "can't create command.cfg";
        if ( -e "$root/$file/level" ) {
            open LEVEL, "< $root/$file/level";
            my $level = <LEVEL>;
            close LEVEL;
            chomp $level;
            print CONFIG "level = $level\n";
        }
        if ( -e "$root/$file/user" ) {
            print CONFIG "user = 1\n";
        }
        close CONFIG;
    }
}
closedir(DIR);
