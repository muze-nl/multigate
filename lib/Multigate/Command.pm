#
# Takes care of the execution of !commands in multigate messages
#
# (C) 2000 - 2005 Wieger Opmeer, Casper Joost Eyckelhof, Yvo Brevoort
#
# This package is free software; you can redistribute it and/or modify it
# under the terms of the "Artistic License".
#

package Multigate::Command;

use strict;

our ( $VERSION, @ISA, @EXPORT, $child_exit_status );

use Exporter;
use IO::Handle;
use IO::Select;
use POSIX;
use URI::Escape;
use File::stat;
use BSD::Resource;

use Multigate;
use Multigate::Debug;
use Multigate::Config;
use Multigate::NBRead;
use Multigate::Users;
use Multigate::Util;
use Multigate::Accounting;

@ISA    = qw( Exporter );
@EXPORT = qw( spawn_command );
$VERSION='1';

#
# Setup a SIGCHLD handler to prevent zombies..
#
sub REAPER {
    my $waitedpid = wait;
    $child_exit_status = $?;
    $SIG{CHLD} = \&REAPER;    # loathe sysV
}
$SIG{CHLD} = \&REAPER;    # and activate

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

    } elsif ( !defined $pid ) {
        die "cannot fork!";    # this is baaaad...
    }

    #this is the parent

    close $child;

    $command->{'parent'} = $parent;

    bless $command, "Multigate::Command";

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
      
        #Fix for CtlAltDel needs some ugly programming 
        my $rewrite = 0;
        if ($in =~ /^rewrite:(.) (.*)$/) { 
          $rewrite = ( $1 eq 'Y' ? 1 : 0);
          $in = $2;
        } else {
          #something must be wrong...
          debug('Command', "No rewrite prefix fount in message in read_handler!");
        }
        if ($rewrite ) {
           debug('Command' , "Rewriting to_address to unicast");
           $command->{'to_address'} = to_unicast($command->{'to_protocol'}, $command->{'to_address'});
        }
        # This ugly part was brought to you by CtlAltDel; The End :)
        
        my $prepend = ( exists $command->{'prepend'} ) ? $command->{'prepend'} . ' ' : '';
        my $upcall  = $command->{'upcall'};

        my $success = &$upcall( $command, "$prepend$in" );    # pass complete hashref
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
        } else {

            #failure in upcall, what to do?
        }
    } else {
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
#  safe_execute( $command, $command_obj );
#
sub safe_execute {
    my $com         = shift;
    my $command_obj = shift;

    my $command = $com->{'command'};
    my $exe     = $com->{'exe'};
    my $args    = $com->{'args'};
    my $clevel  = $com->{'level'};

    my @out;
    my $line;

    # This would be a nice spot to check the length of the arguments 
    # On linux this should (default) not exceed 128K bytes
    # exec will fail on larger commands...
    if ( length($args) > 128000 ) {
        debug( 'Command', "argument to $command exceeds 128K bytes. Not executing" );
        return "!$command $args";    #Ugly?!
    }

    if ( my $pid = open( CHILD, "-|" ) ) {

        # This is the parent 

        eval {
            local $SIG{ALRM} = sub { die "alarm\n" }; # NB: \n required
            alarm $com->{'runtime_limit'};

            while ( ( $line = <CHILD> ) ) {
                chomp($line);
                if ( length($line) > 0 ) { push @out, $line }
            }
            close(CHILD);
            alarm 0;
        };
        if ($@) {
            die unless $@ eq "alarm\n";   # propagate unexpected errors
            kill 15, $pid; # try to kill..
            push @out, "Command !$command $args timed out";
        }

    } else {

        # This is the child
        die "cannot fork: $!" unless defined $pid;

        # Working directory is the command's own directory
        chdir("commands/$command");

        # Setup an CGI-like environment
        # Create environment variables for our command to use
        $ENV{'MULTI_USER'}         = $command_obj->{'from_address'};
        $ENV{'MULTI_REALUSER'}     = $command_obj->{'user'};
        $ENV{'MULTI_USERLEVEL'}    = $command_obj->{'userlevel'};
        $ENV{'MULTI_FROM'}         = $command_obj->{'from_protocol'};
        $ENV{'MULTI_TO'}           = $command_obj->{'to_protocol'};
        $ENV{'MULTI_IS_MULTICAST'} = $command_obj->{'is_multicast'};
        $ENV{'MULTI_COMMANDLEVEL'} = $clevel;

        # setup limits
        setrlimit(RLIMIT_VMEM, 1024*1024*$com->{'mem_limit'}, 1024*1024*$com->{'mem_limit'});
        setrlimit(RLIMIT_CPU, $com->{'cputime_limit'}, $com->{'cputime_limit'});
        setrlimit(RLIMIT_CORE, 0, 0); # prevent coredumps

        #Execute!
        exec( "./$exe", $args ) or die "can't exec: $!";
    }
    debug('Command_debug', "exit code: $child_exit_status");
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
    } else {
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
    my $commandline = shift;
    my @commands = split /(^!\S+|\s!\S+)/, $commandline;
    shift @commands;    #first entry is empty or rubbish

    my @result = ();
    my ( $command, $args ) = ( '', '' );

    while (@commands) {
        my $item = pop @commands;
        $item =~ s/^\s+//;
        debug( 'Command_debug', "Item: \"$item\"" );
        if ( ( $item =~ /^!(\S+)/ ) ) {
            $command = lc($1);    # all commands are lowercase

            if ( $command =~ /\W/ ) {    # commands with non-word characters are evil
                $args = "$item $args";    # demote to argument
                debug( 'Command_debug', "args: $args" );
                next;
            }

            # read commandconfig, and add to record
            my %cconfig = read_commandconfig($command);

            # make command record
            my $rec = {};
            $rec->{'args'}    = $args;
            $rec->{'command'} = $command;
            if ( defined $cconfig{'exe'} ) {
                $rec->{'exe'} = $cconfig{'exe'};
            } else {
                $rec->{'exe'} = "$command.pl";
            }
            my $exe = $rec->{'exe'};
                                                                              
            $rec->{'exists'}  = ( -x "commands/$command/$exe" ) ? 1 : 0;    # no undefs
            $args = '';

            foreach my $key ( keys %cconfig ) {
                $rec->{$key} = $cconfig{$key};
            }

            push @result, $rec;
        } else {
            $args = "$item $args";
            $args =~ s/^\s+//;
            debug( 'Command_debug', "args: $args" );
        }
    }

    # Debug: show all key->value pairs from the commandconfig thingies
    for my $href (@result) {
        for my $role ( keys %$href ) {
            debug( 'Command_debug', "$role=$href->{$role} " );
        }
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
    my $exe     = $com->{'exe'};
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
    $com->{'args'} = $args; # we need it further down

    unless ($exists) {
        debug( 'Command', "Unknown command: $command" );
        account_log( $command, $realsender, $from_protocol, $from_address, time(), 0, "FAILED", "Unknown command: $command" );
        return "!$command $args";
    }

    unless ( $level <= $userlevel ) {
        debug( 'Command', "Level needed for $command is $level" );
        account_log( $command, $realsender, $from_protocol, $from_address, time(), 0, "FAILED",
            "Level needed for $command is $level" );
        return "!$command $args";
    }

    # check whether this user has enough credits
    if ( defined $boxname ) {    #no boxname for this command -> no accounting (just logging)

        unless ( defined check_and_withdraw( $boxname, $realsender, $units ) ) {
            debug( 'Command', "$realsender has not enough credits for $boxname" );
            account_log( $command, $realsender, $from_protocol, $from_address, time(), 0, "FAILED",
                "$realsender has not enough credits for $boxname" );
            return "!$command $args";
        }
    } else {

        # Is this useful ?
        $boxname = $command;
    }

    if ( eval $cache == 0 ) {
        # No caching due to config..
        debug( 'Command', "No caching due to config..." );

        my $content = safe_execute( $com, $command_obj );

        if ( $child_exit_status == 0 ) {
            account_log( $command, $realsender, $from_protocol, $from_address, time(), $units, "OK", "No caching" );
        } else {
            account_log( $command, $realsender, $from_protocol, $from_address, time(), $units, "FAIL", "No caching" );
        }
        return $content;
    }

    my $cachefile = cachename( $command, $args );
    my $content = check_cache($cachefile);

    if ( defined $content ) {

        # cache hit!
        debug( 'Command', "Cache hit for $command." );
        account_log( $command, $realsender, $from_protocol, $from_address, time(), $units, "OK", "Cache hit" );
    } else {

        # cache miss
        debug( 'Command', "Cache missed for $command." );
        $content = safe_execute( $com, $command_obj );

        if ( $child_exit_status == 0 ) {
            account_log( $command, $realsender, $from_protocol, $from_address, time(), $units, "OK", "Cache mis" );

            # write new cache entry
            write_cache( $cachefile, $cache, $content );
        } else {
            account_log( $command, $realsender, $from_protocol, $from_address, time(), $units, "FAIL", "Cache mis" );
       }
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
    my @commandolist = split_commands($msg);
    my $command;

    my $min_max_lines_multicast = 10000000;  #will contain the minimum value found for max_lines_multicast, initialize at insane value

    foreach $command (@commandolist) {
        debug( 'Command_debug', "doing $command" );
        $command->{'args'} .= $result;
        $result = exec_command( $command, $command_obj );
        #check for new min_max_lines_multicast
        if ($command->{'max_lines_multicast'} < $min_max_lines_multicast) {
          $min_max_lines_multicast = $command->{'max_lines_multicast'};
        }            
    }

    # some string processing to clean things up, if neccesary
    # No leading spaces
    $result =~ s/^\s+//;

    # No traling spaces
    $result =~ s/\s+$//;

    # No trailing \xb6
    $result =~ s/\xb6+$//;

    # Not just an '!'
    $result =~ s/^!$//;
    
    # If we have a multicast message, check if it is not too many lines
    my $rewrite = 'N';
    if ($command_obj->{'is_multicast'}) {
      my $linecount = () = $result =~ /\xb6/g;  #ugly oneliner to count number of matches in a string
      $linecount++;                             #former line has off-by-one, it counts separators :)
      if ($linecount > $min_max_lines_multicast) {
         #rewrite to unicast address! But we are in a child, and the only way to communicate with the parent is using STDOUT :(
         $rewrite = 'Y';
         debug('Command', "linecount ($linecount) > min_max_lines ($min_max_lines_multicast) in multicast message");
      }
    }

    # the following print statement will cause things to happen, 
    # the parent will see it and will act upon it...
    if ( lc($result) ne lc($msg) ) {
        debug( 'Command_debug', "All commands done. Total output is: $result" );
        print "rewrite:$rewrite $result\n";
    } else {
        debug( 'Command_debug', "Discarding bogus command $result" );
    }

    # Nice people clean up after themselves, we are nice :) (who says?)
    cleanup_users_module();

    # DO NOT RETURN, LET EVERYTHING DIE!
    exit 0;
}

1;
