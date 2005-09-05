#
# Takes care of the execution of !commands in multigate messages
#
# (C) 2000 - 2005 Wieger Opmeer, Casper Joost Eyckelhof, Yvo Brevoort
#
# This package is free software; you can redistribute it and/or modify it
# under the terms of the "Artistic License".
#
# 16-10-2003 Forked Command.pm into CommandSimple.pm and removed all fancy features
#            Just executes 1 command now
#

package Multigate::CommandSimple;

use strict;

use vars qw( $VERSION @ISA @EXPORT );

use Exporter;
use IO::Handle;
use IO::Select;
use POSIX;
use URI::Escape;
use File::stat;

use Multigate;
use Multigate::Debug;
use Multigate::Config;
use Multigate::NBRead;
use Multigate::Users;
use Multigate::Util;
use Multigate::Accounting;

@ISA     = qw( Exporter );
@EXPORT  = qw( spawn_command );
$VERSION = '1';

#
# Setup a SIGCHLD handler to prevent zombies..
#
sub REAPER {
    my $waitedpid = wait;

    $SIG{CHLD} = \&REAPER;    # loathe sysV
}
$SIG{CHLD} = \&REAPER;        # and activate

#
# Do the fork()-thing...
#
sub spawn_command {
    my $commandref = shift;

    #we need a ref to a _copy_, just to be safe...  (!msg will bite you)
    my %commandcopy = %{$commandref};
    my $command     = \%commandcopy;

    my $pid;
    my ( $parent, $child );

    pipe $parent, $child;    # child writes output, parent reads...
    make_non_blocking($parent);

# Do not make the child non-blocking!
# That will result in very unwanted behaviour when the command expands to a string larger than a pipe
# GRRRRMMMM :)

    if ( ( $pid = fork ) == 0 ) {

        # this is the child
        close $parent;

        my $chfileno = fileno($child);

        dup2( $chfileno, 1 ) or die 'cannot dup stdout';

        #FIXME close everything else

        init_users_module();

        #the following call must not return, call exit() instead...
        do_commands($command);
        exit(42);    # just to make sure, child dies

    }
    elsif ( !defined $pid ) {
        die "cannot fork!";    # this is baaaad...
    }

    #this is the parent

    close $child;

    $command->{'parent'} = $parent;

    bless $command, "Multigate::CommandSimple";

    register_read_handler( $parent, $command );

    return ( $pid, $parent );
}

#
# Called when the Command-object has something to read
# (called from: Multigate::mainloop , the main select loop)
# This handler gets called when a command sends it output
# and it must route the output to the destination
#
sub read_handler {
    my $command = shift;
    my $in      = shift;

    debug( 'Command_debug', "Command::read_handler: $in" );

    if ($in) {
        my $prepend =
          ( exists $command->{'prepend'} ) ? $command->{'prepend'} . ' ' : '';
        my $upcall  = $command->{'upcall'};
        my $success =
          &$upcall( $command, "$prepend$in" );    # pass complete hashref
             # different upcalls may need different fields

        if ( defined( $command->{'notify_success'} ) and $success ) {
            &$upcall(
                {
                    'user'          => $command->{'user'},
                    'to_protocol'   => $command->{'from_protocol'},
                    'from_protocol' => $command->{'from_protocol'},
                    'to_address'    => $command->{'from_address'},
                    'from_address'  => $command->{'from_address'}
                },
                $command->{'notify_success'}
            );
        }
        else {

            #failure in upcall, what to do?
        }
    }
    else {
        debug( 'Command_debug', "read_handler leest niets!\n" );
    }
}

#
# This gets called when there is an error on de command fd
# FIXME: What error?
#
sub error_handler {
    my $command = shift;

    unregister_read_handler( $command->{'parent'} );
    close $command->{'parent'};
}

#
# This gets called when the command is done... (I hope)
#
sub close_handler {
    my $command = shift;

    unregister_read_handler( $command->{'parent'} );
    close $command->{'parent'};
}

#
# This can be asked to wrappers, but also to Command objects...
# FIXME: should we do this?
#
sub protocolname {
    return "Command";
}

#
# Run an external executable, but try to do it as safe as possible: the user
# supplied some or all of the arguments.
# Code taken from Perl Cookbook(???) can't find the exact chapter...
# Don't let the name fool you, further down the chain, the user supplied
# arguments are still available
#
#  safe_execute( $command, $args , $level , $command_obj );
#
sub safe_execute {
    my ( $file, $argumenten, $clevel, $command_obj ) = @_;
    my @out;
    my $line;

    # This would be a nice spot to check the length of the arguments
    # On linux this should (default) not exceed 128K bytes
    # exec will fail on larger commands...
    if ( length($argumenten) > 128000 ) {
        debug( 'Command',
            "argument to $file exceeds 128K bytes. Not executing" );
        return "!$file $argumenten";    #Ugly?!
    }

    if ( my $pid = open( CHILD, "-|" ) ) {

        # This is the parent
        while ( ( $line = <CHILD> ) ) {
            chomp($line);
            if ( length($line) > 0 ) { push @out, $line }
        }
        close(CHILD);
    }
    else {

        # This is the child
        die "cannot fork: $!" unless defined $pid;

        # Working directory is the command's own directory
        chdir("commands/$file");

        # Setup an CGI-like environment
        # Create environment variables for our command to use
        $ENV{'MULTI_USER'}         = $command_obj->{'from_address'};
        $ENV{'MULTI_REALUSER'}     = $command_obj->{'user'};
        $ENV{'MULTI_USERLEVEL'}    = $command_obj->{'userlevel'};
        $ENV{'MULTI_FROM'}         = $command_obj->{'from_protocol'};
        $ENV{'MULTI_TO'}           = $command_obj->{'to_protocol'};
        $ENV{'MULTI_IS_MULTICAST'} = $command_obj->{'is_multicast'};
        $ENV{'MULTI_COMMANDLEVEL'} = $clevel;

        #Execute!
        exec( "./$file.pl", $argumenten ) or die "can't exec: $!";
    }
    return join " \xb6", @out;
}

#
# cache_name( $command, $args )
# returns a probably unique filename, based on $command and $args
#
sub cachename {
    my ( $command, $args ) = @_;
    my $cachefile = "cache/$command/";

    unless ( -d "cache/$command" ) {
        mkdir "cache/$command", 0755 or die "cannot mkdir cache/$command";
    }

    if ( defined $args and $args ne '' ) {
        my $escaped = uri_escape($args);
        if ( length($escaped) > 250 ) {
            $escaped = substr $escaped, 0, 250;
        }
        $cachefile .= $escaped;
    }
    else {
        $cachefile .= '!';
    }
    return $cachefile;
}

#
# check_cache (command, args) = content
# not found => timestamp = 0
#
sub check_cache {
    my $cachefile = shift;
    unless ( -e $cachefile ) {
        return undef;
    }

    my $stat = stat $cachefile or die "Error opening cachefile: $!\n";

    unless ( $stat->mtime > time() ) {
        return undef;
    }

    open CACHE, "< $cachefile" or die "Error opening cachefile: $!\n";
    my $content = <CACHE>;
    close CACHE;
    chop $content;
    return $content;
}

#
# write_cache( $command, $args, $cache_expr, $output )
#
sub write_cache {
    my $cachefile = shift;
    my $cacheexpr = shift;
    my $content   = shift;

    open CACHE, "> $cachefile" or die "cannot write to $cachefile!";
    print CACHE $content, "\n";
    close CACHE;

    my $cachetime = time + eval $cacheexpr;
    debug( 'Command_debug', "Cache $cacheexpr = $cachetime" );
    utime $cachetime, $cachetime, $cachefile if $cachetime;
}

#
# This function splits a commandline into a list of hashes of commands
# and arguments, then adds the commandconfig.
#
sub split_commands {
    my $item = shift;
    $item =~ s/^\s+//;
    debug( 'Command_debug', "Item: \"$item\"" );
    my ( $command, $args ) = ( '', '' );
    my @result;

    if ( ( $item =~ /^!(\S+)/ ) ) {
        $command = lc($1);    # all commands are lowercase

        if ( $command =~ /\W/ ) {   # commands with non-word characters are evil
            $args = "$item $args";    # demote to argument
            debug( 'Command_debug', "args: $args" );
            next;
        }

        # make command record
        my $rec = {};
        $rec->{'args'}    = $args;
        $rec->{'command'} = $command;
        $rec->{'exists'}  =
          ( -x "commands/$command/$command.pl" ) ? 1 : 0;    # no undefs
        $args = '';

        # read commandconfig, and add to record
        my %cconfig = read_commandconfig($command);

        foreach my $key ( keys %cconfig ) {
            $rec->{$key} = $cconfig{$key};
        }

        push @result, $rec;
    }
    else {
        $args = "$item $args";
        $args =~ s/^\s+//;
        debug( 'Command_debug', "args: $args" );
    }

    return @result;
}

#
# execute a single command
# exec_command( $command, $command_obj);
sub exec_command {
    my $com         = shift;
    my $command_obj = shift;

    my $realsender    = $command_obj->{'user'};
    my $userlevel     = $command_obj->{'userlevel'};
    my $from_protocol = $command_obj->{'from_protocol'};
    my $from_address  = $command_obj->{'from_address'};

    my $command = $com->{'command'};
    my $args    = $com->{'args'};
    my $exists  = $com->{'exists'};
    my $level   = $com->{'level'};
    my $cache   = $com->{'cache'};
    my $boxname = $com->{'box'};
    my $units   = $com->{'units'};

    $units = 0 unless ( defined $units );

    debug( 'Command_debug', "doing $command" );

    $args = '' unless ( defined $args );
    $args =~ s/^\s+//;
    $args =~ s/\s+$//;

    # For SMSC purposes: Do not return anything on an unknown command.
    unless ($exists) {
        debug( 'Command', "Unknown command: $command" );
        account_log( $command, $realsender, $from_protocol, $from_address,
            time(), 0, "FAILED", "Unknown command: $command" );

        #        return "Het commando $command is niet bekend";
        return undef;
    }

    unless ( $level <= $userlevel ) {
        debug( 'Command', "Level needed for $command is $level" );
        account_log( $command, $realsender, $from_protocol, $from_address,
            time(), 0, "FAILED", "Level needed for $command is $level" );
        return "U heeft onvoldoende rechten om $command te kunnen uitvoeren";
    }

    # check whether this user has enough credits
    if ( defined $boxname )
    {    #no boxname for this command -> no accounting (just logging)

        unless ( defined check_and_withdraw( $boxname, $realsender, $units ) ) {
            debug( 'Command',
                "$realsender has not enough credits for $boxname" );
            account_log(
                $command,
                $realsender,
                $from_protocol,
                $from_address,
                time(),
                0,
                "FAILED",
                "$realsender has not enough credits for $boxname"
            );
            return
              "U heeft onvoldoende credits om $command te kunnen uitvoeren";
        }
    }
    else {

        # Is this useful ?
        $boxname = $command;
    }

    if ( eval $cache == 0 ) {

        # No caching due to config..
        account_log( $command, $realsender, $from_protocol, $from_address,
            time(), $units, "OK", "No caching" );
        return safe_execute( $command, $args, $level, $command_obj );
    }

    my $cachefile = cachename( $command, $args );
    my $content   = check_cache($cachefile);

    if ( defined $content ) {

        # cache hit!
        debug( 'Command', "Cache hit for $command." );
        account_log( $command, $realsender, $from_protocol, $from_address,
            time(), $units, "OK", "Cache hit" );
    }
    else {

        # cache miss
        debug( 'Command', "Cache missed for $command." );
        $content = safe_execute( $command, $args, $level, $command_obj );
        account_log( $command, $realsender, $from_protocol, $from_address,
            time(), $units, "OK", "Cache mis" );

        # write new cache entry
        write_cache( $cachefile, $cache, $content );
    }

    return $content;

}

#
# expand commands
#
sub do_commands {
    my $command_obj = shift;

    my $msg    = $command_obj->{'msg'};
    my $result = '';                      # to store final result

    # get rid of final whitespace
    $msg =~ s/\s+$//;

    # Split on !command, we now have an array of commands
    # Update in CommandSimple this is always just one entry
    my @commandolist = split_commands($msg);
    my $command      = shift @commandolist;

    debug( 'Command_debug', "doing $command" );
    $result = exec_command( $command, $command_obj );

    if ( defined($result) ) {

        # some string processing to clean things up, if neccesary
        # No leading spaces
        $result =~ s/^\s+//;

        # No traling spaces
        $result =~ s/\s+$//;

        # No trailing \xb6
        $result =~ s/\xb6+$//;

        # Not just an '!'
        $result =~ s/^!$//;

        # the following print statement will cause things to happen,
        # the parent will see it and will act upon it...
        if ( lc($result) ne lc($msg) ) {
            debug( 'Command_debug',
                "All commands done. Total output is: $result" );

            # add tariff - FIXME?
            my $tariff =
              ( exists( $command->{'tariff'} ) ? $command->{'tariff'} : 0 );
            print "$tariff $result\n";
        }
        else {
            debug( 'Command_debug', "Discarding bogus command $result" );
        }
    }
    else {
        debug( 'Command_debug',
            "Discarding bogus command, result was undefined" );
    }

    # Nice people clean up after themselves, we are nice :) (who says?)
    cleanup_users_module();

    # DO NOT RETURN, LET EVERYTHING DIE!
    exit 0;
}

1;
