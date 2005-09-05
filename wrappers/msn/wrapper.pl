#!/usr/bin/perl -w

use strict;

use lib 'lib';

use MSN;
use Multigate::Debug;
use Multigate::NBRead;
use Multigate::Util;
use IO::Select;
use IO::Handle;
use Multigate::Config qw(readconfig getconf);
readconfig('multi.conf');    # reread config file on wrapper start

my $login = getconf('msn_login');
my $pass  = getconf('msn_pass');

#my $fname = getconf('msn_fname');

Multigate::Debug::setdebug('msn');

my $msn = MSN->new( Handle => $login, Password => $pass );
$msn->set_handler( Message      => \&on_message );
$msn->set_handler( Connected    => \&on_connect );
$msn->set_handler( Disconnected => \&on_disconnect );

$msn->connect();

#select on STDIN, build a readset with only STDIN
my $stdin = new IO::Handle;
$stdin->fdopen( fileno(STDIN), 'r' );
make_non_blocking($stdin);

my $readset = IO::Select->new();
$readset->add($stdin);

my $r_ready;    #to store read_ready filehandles
$| = 1;

my $fh;
my $input;
my $target;
my $message;

while (1) {
    $msn->do_one_loop;
    ($r_ready) = IO::Select->select( $readset, undef, undef, 0.1 );
    foreach $fh (@$r_ready) {

        #We have someone knocking on STDIN, lets read what it is
        while ( $input = nbread($fh) ) {
            chomp($input);
            if ( $input =~ m/OUTGOING msn (.*?) (.*)/ ) {
                $target  = $1;
                $message = $2;
                $message =~ s/\xb6/\r\n/g;
                foreach my $piece ( cut_pieces( $message, 1000 ) ) {
                    $msn->call( $target, $piece );
                }
            }
            elsif ( $input =~ m/^DIEDIEDIE/ ) {
                exit;
            }
            unless ( defined $input ) {

                # $fh has closed... should we do something now?
            }
        }
    }
}

sub on_message {
    my ( $self, $email, $name, $msg ) = @_;
    $msg =~ s/<(|\n)+?>//g;

    #    $self->sendmsg($msg);
    print "INCOMING msn $email $msg\n";
}

sub on_connect {

    #   $msn->call('yvo@muze.nl', "Frop!!!");
    debug( 'msn', 'Connected to MSN' );
}

sub on_disconnect {
    debug( 'msn', 'Disconnected from MSN, now what?' );
    exit 0;
}
