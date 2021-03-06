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
my $timeout = 60;

#my $fname = getconf('msn_fname');

Multigate::Debug::setdebug('msn');

my $msn = MSN->new('Handle' => $login, 'Password' => $pass, 'AutoloadError' => 1, 'Debug' => 1, 'Messaging' => 1, 'ShowTX' => 1, 'ShowRX' => 1);

$msn->setHandler( 'Message'      => \&on_message );
$msn->setHandler( 'Connected'    => \&on_connect );
$msn->setHandler( 'Disconnected' => \&on_disconnect );

$SIG{ALRM} = sub { die "Can't connect after 60 seconds\n" };
alarm $timeout;

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
                $message =~ s/\xb6/\n/g;
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
    alarm 0;
    if (-e "display.png") {
        $msn->setDisplayPicture("display.png");
        debug('msn', 'Set display picture');
    }
}

sub on_disconnect {
    debug( 'msn', 'Disconnected from MSN, now what?' );
    exit 0;
}
