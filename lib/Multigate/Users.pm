#
# (C) 2000 - 2005 Wieger Opmeer, Casper Joost Eyckelhof, Yvo Brevoort
#
# This package is free software; you can redistribute it and/or modify it
# under the terms of the "Artistic License".
#

package Multigate::Users;

#
# The interface to the user administration for multigate
#
# Every user has a unique username for multigate
# Besides this username, he/she can have multiple (unique) aliases
# For every protocol, a user can have one or more registered addresses (like icq
# number, email address, irc hostmask, (sms) mobile phone number, etc)
# The first address for a protocol, is the main address.
#   (This main address is where messages for the user protocol are sent to,
#    the other addresses are to identify the user if necessary, like multiple hostmasks for irc)
# Every user has a userlevel (to give him/her rights on the system)
#
# A better description might follow... :)
#

use strict;
use vars qw( @ISA @EXPORT $VERSION );
use Exporter;
use DBI;
use FileHandle;

use lib './lib';
use Multigate::Config qw( getconf readconfig hasconf);

$VERSION = '2';
@ISA     = qw( Exporter );
@EXPORT  =
  qw( get_user get_address get_realname get_userlevel protocol_exists user_exists group_exists add_protocol
  remove_protocol add_user remove_user add_alias remove_alias
  change_userlevel new_address add_address remove_address set_main_address
  add_group_member remove_group_member set_group_admin_flag get_group_admin_flag get_group_members
  unset_group_admin_flag list_groups user_in_group get_group_protocol set_group_protocol unset_group_protocol
  get_preferred_protocol set_preferred_protocol unset_preferred_protocol
  get_protocol_level set_protocol_level
  get_protocol_maxmsgsize set_protocol_maxmsgsize
  add_box remove_box get_box inc_box dec_box set_box list_boxes
  authorize_expenditure commit_expenditure check_and_withdraw
  authenticate_user
  init_users_module cleanup_users_module );

# returns a working $dbh, we hope
sub get_dbh {
    my $password;
    if (hasconf('db_passwd')) {
        $password = getconf('db_passwd');
    }
    my $db_user  = getconf('db_user');
    my $database = getconf('db_name');
    my $dbh      = DBI->connect_cached( 'DBI:mysql:' . $database,
        $db_user, $password, { RaiseError => 0, AutoCommit => 1 } );
    return 0 unless defined $dbh;
    return $dbh;
}

#
# Call this before any of the others..
# Returns errorstring on failure, 0 on succes...
#
sub init_users_module {
    my $configroot = $ENV{MULTI_ROOT};
    unless ($configroot) { $configroot = "."; }
    readconfig("$configroot/multi.conf");    #allowed this way?
    my $password;

    if (hasconf('db_passwd')) {
        $password = getconf('db_passwd');
    }
    my $db_user  = getconf('db_user');
    my $database = getconf('db_name');
    my $dbh      = get_dbh();
    return DBI::errstr unless defined $dbh;
    return 0;
}

#
# Call this just before process exit
#
sub cleanup_users_module {
    my $dbh = get_dbh();
    if ( defined $dbh ) {
        $dbh->disconnect;

        #print STDERR "Multigate::Users -- Disconnected\n";
    }
    else {

  #print STDERR "Multigate::Users -- Tried to clean up but dbh doesn't exist\n";
    }
}

#
# Try to resolve an alias into a user;
#
sub aliastouser {
    my $alias = shift;
    return '' unless $alias;
    my $dbh = get_dbh();
    my $res = $dbh->selectrow_array( <<'EOT', {}, $alias );
SELECT
  username
FROM 
  alias
WHERE
  alias = ?
EOT
    return $alias unless defined $res;
    return $res;
}

#
# Returns the multigate username and userlevel, given a protocol and address
# Question: what to do with hostmasks from irc??
# Maybe this module should accept wildcards...
# Example: get_user("email" , "joost@dnd.utwente.nl") returns ("titanhead",10)
# "pietjepuk",0 on failure
#
sub get_user {
    my ( $protocol, $address ) = @_;
    return undef unless $protocol and $address;
    my $dbh = get_dbh();
    my @res = $dbh->selectrow_array( <<'EOT', {}, $protocol, $address );
SELECT
  user.username, user.level
FROM 
  user, address
WHERE
  protocol = ? and
  address = ? and
  address.username = user.username
EOT
    return ( 'pietjepuk', 0 ) if ( $#res == -1 );
    return @res[ 0 .. 1 ];
}

sub authenticate_user {
  my ( $username, $password ) = @_;
  return undef unless $username and $password;
    
  my $dbh = get_dbh();
  my @res = $dbh->selectrow_array( <<'EOT', {}, $username );
SELECT
  password
FROM
  user
WHERE
  username = ?
EOT
    my $crypted_password = crypt($password, $res[0]);
    if ($res[0] eq $crypted_password) {
      return 1;
    }
    return 0;
}

#
# Returns the first address found, given a username (or alias) and protocol
# undef on failure
#
sub get_address {
    my ( $user, $protocol ) = @_;
    return undef unless $user and $protocol;
    my $dbh = get_dbh();
    $user = aliastouser($user);
    my @res = $dbh->selectrow_array( <<'EOT', {}, $user, $protocol );
SELECT
  address
FROM 
  address
WHERE
  username = ? and
  protocol = ? and
  address.main_address = 'true'
EOT
    return undef if ( $#res == -1 );
    return $res[0];
}

#
# Returns the multigate username, given an alias (or the username itself)
# undef on failure
#
sub get_realname {
    my ($user) = @_;
    return undef unless $user;
    return aliastouser($user);
}

#
# Returns the userlevel of a user (or alias)
# 0 on failure
#
sub get_userlevel {
    my ($user) = @_;
    return 0 unless $user;
    $user = aliastouser($user);
    my $dbh = get_dbh();
    my $res = $dbh->selectrow_array( <<'EOT', {}, $user );
SELECT
  level
FROM 
  user
WHERE
  username = ?
EOT
    return 0 unless defined $res;
    return $res;
}

#
# ---------------------------------------------------------------------
#
# Some helper functions to check whether things exist
#

#
# Check whether user exists (0, 1)
#
sub user_exists {
    my $user = shift;
    return 0 unless $user;
    $user = aliastouser($user);
    my $dbh = get_dbh();
    my $res = $dbh->selectrow_array( <<'EOT', {}, $user );
SELECT
  count(*)
FROM
  user
WHERE
  username like ?
EOT
    return $res;
}

#
# Check whether protocol exists(0, 1)
#
sub protocol_exists {
    my $protocol = shift;
    return 0 unless $protocol;
    my $dbh = get_dbh();
    my $res = $dbh->selectrow_array( <<'EOT', {}, $protocol );
SELECT
  count(*)
FROM
  protocol
WHERE
  protocol like ?
EOT
    return $res;
}

#
# Check whether group exists (0, #members)
#
sub group_exists {
    my $group = shift;
    return 0 unless $group;
    my $dbh = get_dbh();
    my $res = $dbh->selectrow_array( <<'EOT', {}, $group );
SELECT
  count(*)
FROM
  herd
WHERE
  herdname like ?
EOT
    return $res;
}

#
# ---------------------------------------------------------------------
#
# The following methods actually change the 'database'
#

#
# Adds a protocol (of the given name) to the database and gives every known
# user an empty address for the protocol
#
sub add_protocol {
    my ($protocol) = @_;
    return 0 unless $protocol;
    my $dbh = get_dbh();
    my $res = $dbh->do( <<'EOT', {}, $protocol );
INSERT INTO
  protocol (protocol)
VALUES
  (?)
EOT
    return $res;
}

#
# Removes a protocol and all associated addresses
#
sub remove_protocol {
    my ($protocol) = @_;
    return 0 unless $protocol;
    my $res;
    my $dbh = get_dbh();
    $res = $dbh->do( <<'EOT', {}, $protocol );
DELETE FROM
  protocol
WHERE
  protocol = ?
EOT
    return unless defined $res;
    $res = $dbh->do( <<'EOT', {}, $protocol );
DELETE FROM
  address
WHERE
  protocol = ?
EOT
    return $res;
}

#
# Get protocol level
#
sub get_protocol_level {
    my ($protocol) = @_;
    return unless $protocol;
    my $dbh = get_dbh();
    my $res = $dbh->selectrow_array( <<'EOT', {}, $protocol );
SELECT
  level
FROM 
  protocol
WHERE
  protocol like ?
EOT
    return $res;
}

#
# Set protocol level
#
sub set_protocol_level {
    my ( $protocol, $level ) = @_;
    return unless $protocol and $level;
    my $dbh = get_dbh();
    my $res = $dbh->do( <<'EOT', {}, $level, $protocol );
UPDATE
  protocol
SET
  level = ?
WHERE
  protocol = ?
EOT
    return $res;
}

#
# Get Protocol Maximum Message Size
#
sub get_protocol_maxmsgsize {
    my ($protocol) = @_;
    return unless $protocol;
    my $dbh = get_dbh();
    my $res = $dbh->selectrow_array( <<'EOT', {}, $protocol );
SELECT
  maxmsgsize
FROM 
  protocol
WHERE
  protocol like ?
EOT
    return $res;
}

#
# Set Protocol Maximum Message Size
#
sub set_protocol_maxmsgsize {
    my ( $protocol, $maxmsgsize ) = @_;
    return unless $protocol and $maxmsgsize;
    my $dbh = get_dbh();
    my $res = $dbh->do( <<'EOT', {}, $maxmsgsize, $protocol );
UPDATE
  protocol
SET
  maxmsgsize = ?
WHERE
  protocol = ?
EOT
    return $res;
}

#
# Adds a new user.
# First argument should be the unique new name, second argument userlevel
# Every (optional) next argument is a unique alias
#
sub add_user {
    my ( $username, $level ) = @_;
    return unless $username and $level;
    my $dbh = get_dbh();
    my $res = $dbh->do( <<'EOT', {}, $username, $level );
INSERT INTO
  user (username, level)
VALUES
  (?, ?)
EOT
    return $res;
}

#
# Removes a user (probably not to be called with alias) completely
#
sub remove_user {
    my ($username) = @_;
    return unless $username;
    my $res;
    my $dbh = get_dbh();
    $res = $dbh->do( <<'EOT', {}, $username );
DELETE FROM
  user
WHERE
  username = ?
EOT
    return unless defined $res;
    $res = $dbh->do( <<'EOT', {}, $username );
DELETE FROM
  address
WHERE
  username = ?
EOT
    return $res;
}

#
# Removes an alias. aliasses are unique, so no need for extra arguments
#
sub remove_alias {
    my ($alias) = @_;
    return unless $alias;
    my $dbh = get_dbh();
    my $res = $dbh->do( <<'EOT', {}, $alias );
DELETE FROM
  alias
WHERE
  alias = ?
EOT
    return $res;
}

#
# Adds a new (unique) alias to existing user (or alias)
# example add_alias("titanhead","joost");
#
sub add_alias {
    my ( $alias, $username ) = @_;
    return unless $alias and $username;
    my $dbh = get_dbh();
    my $res = $dbh->do( <<'EOT', {}, $alias, $username );
INSERT INTO
  alias (alias, username)
VALUES
  (?, ?)
EOT
    return $res;
}

#
# Changes userlevel
# change_userlevel("titanhead", 10);
#
sub change_userlevel {
    my ( $username, $level ) = @_;
    return unless $username and $level;
    my $dbh = get_dbh();
    my $res = $dbh->do( <<'EOT', {}, $level, $username );
UPDATE
  user
SET
  level = ?
WHERE
  username = ?
EOT
    return $res;
}

#
# Adds a new address for a user (or alias) for protocol
# This address should be returned by the method get_address
# It adds it to "the top of the search list" (as the main address for the protocol)
# example new_address("titanhead","email","casper@joost.student.utwente.nl");
#
sub new_address {
    my ( $user, $protocol, $address ) = @_;
    return unless $user and $protocol and $address;
    $user = aliastouser($user);
    my $res;
    my $dbh = get_dbh();
    $res = $dbh->do( <<'EOT', {}, $user, $protocol );
UPDATE
  address
SET
  main_address = 'false'
WHERE
  username = ? and
  protocol = ? and
  main_address = 'true'
EOT

    #    return unless $res;
    $res = $dbh->do( <<'EOT', {}, $user, $protocol, $address );
INSERT INTO
  address (username, protocol, address, main_address)
VALUES
  (?, ?, ?, 'true')
EOT
    return $res;
}

#
# Adds a new address for a user (or alias) for protocol
# This addres should be placed at "the end of the searchlist"
# Used for get_user rather than get_address
#
sub add_address {
    my ( $user, $protocol, $address ) = @_;
    return unless $user and $protocol and $address;
    $user = aliastouser($user);
    my $res;
    my $dbh = get_dbh();
    $res = $dbh->do( <<'EOT', {}, $user, $protocol, $address );
INSERT INTO
  address (username, protocol, address, main_address)
VALUES
  (?, ?, ?, 'false')
EOT
    return $res;
}

#
# Updates the main address of a user for a protocol
#
sub set_main_address {
    my ( $user, $protocol, $address ) = @_;
    return 0 unless $user and $protocol and $address;
    $user = aliastouser($user);
    my $res;
    my $dbh = get_dbh();
    $res = $dbh->do( <<'EOT', {}, $user, $protocol );
UPDATE 
   address 
SET
   main_address='false' 
WHERE 
  username=? and protocol=?
EOT

#No main addresses anymore for given user and protocol
#This might indeed be a race condition if someone queries the database at this point...
#So lets not waste time, and quickly set the new main address ;)

    my $res2;
    $res2 = $dbh->do( <<'EOT', {}, $user, $protocol, $address );
UPDATE 
   address
SET
   main_address='true' 
WHERE 
  username=? and protocol=? and address=?              
EOT

    return $res2;    #rows affected -> 0 failure; 1 success
}

#
# Removes an address for a user (or alias) for protocol
# example remove_address("joost","email","joost@dnd.utwente.nl")
#
sub remove_address {
    my ( $user, $protocol, $address ) = @_;
    return unless $user and $protocol and $address;
    $user = aliastouser($user);
    my $res;
    my $dbh = get_dbh();
    $res = $dbh->do( <<'EOT', {}, $user, $protocol, $address );
DELETE FROM
  address
WHERE
  username = ? and
  protocol = ? and
  address = ?
EOT
    return $res;
}

#
#
#
sub add_group_member {
    my ( $group, $user ) = @_;
    return unless $group and $user;
    $user = aliastouser($user);
    my $res;
    my $dbh = get_dbh();
    $res = $dbh->do( <<'EOT', {}, $group, $user );
INSERT INTO
  herd (herdname, username, shepherd)
VALUES
  (?, ?, 'no')
EOT
    return $res;
}

#
#
#
sub remove_group_member {
    my ( $group, $user ) = @_;
    return unless $group and $user;
    $user = aliastouser($user);
    my $res;
    my $dbh = get_dbh();
    $res = $dbh->do( <<'EOT', {}, $user, $group );
DELETE FROM
  herd
WHERE
  username like ? AND
  herdname like ?
EOT
    return $res;
}

#
#
#
sub get_group_members {
    my ($group) = @_;
    return () unless $group;
    my $dbh = get_dbh();
    unless ( defined $dbh ) { die "dbh undefined" }
    my $res = $dbh->selectcol_arrayref( <<'EOT', {}, $group );
SELECT
  username
FROM
  herd
WHERE
  herdname like ?
EOT
    return ($res) ? @$res : undef;
}

#
#
#
sub list_groups {
    my $dbh = get_dbh();
    my $res = $dbh->selectcol_arrayref( <<'EOT', {} );
SELECT
  DISTINCT(herdname)
FROM
  herd
EOT
    return ($res) ? @$res : undef;
}

#
#
#
sub user_in_group {
    my ( $group, $user ) = @_;
    $user = aliastouser($user);
    return 0 unless ( $group and $user );
    my $dbh = get_dbh();
    my $res = $dbh->selectrow_array( <<'EOT', {}, $group, $user );
SELECT
  COUNT(*)
FROM
  herd
WHERE
  herdname like ? and
  username like ?
EOT
    return $res;
}

#
#
#
sub get_group_admin_flag {
    my ( $group, $user ) = @_;
    return 'no' unless $group and $user;
    $user = aliastouser($user);
    my $dbh = get_dbh();
    my $res = $dbh->selectrow_array( <<'EOT', {}, $user, $group );
SELECT
  shepherd
FROM 
  herd
WHERE
  username like ? AND
  herdname like ?
EOT
    return 'no' unless defined $res;
    return $res;
}

#
#
#
sub set_group_admin_flag {
    my ( $group, $user ) = @_;
    return unless $group and $user;
    $user = aliastouser($user);
    my $res;
    my $dbh = get_dbh();
    $res = $dbh->do( <<'EOT', {}, $user, $group );
UPDATE
  herd
SET
  shepherd = 'yes'
WHERE
  username = ? AND
  herdname = ?
EOT
    return $res;

}

#
#
#
sub unset_group_admin_flag {
    my ( $group, $user ) = @_;
    return unless $group and $user;
    $user = aliastouser($user);
    my $res;
    my $dbh = get_dbh();
    $res = $dbh->do( <<'EOT', {}, $user, $group );
UPDATE
  herd
SET
  shepherd = 'no'
WHERE
  username = ? AND
  herdname = ?
EOT
    return $res;

}

#
# Gets preferred protocol for a user
#
sub get_preferred_protocol {
    my ($user) = @_;
    $user = aliastouser($user);
    return unless $user;
    my $dbh = get_dbh();
    my $res = $dbh->selectrow_array( <<'EOT', {}, $user );
SELECT
  protocol
FROM
  prefprot
WHERE
  username like ?
EOT
    return $res;
}

#
#
#
sub set_preferred_protocol {
    my ( $username, $protocol ) = @_;
    return unless $username and $protocol;
    my $dbh = get_dbh();
    my $res = $dbh->do( <<'EOT', {}, $protocol, $username );
REPLACE INTO
  prefprot
SET
  protocol = ?,
  username = ?
EOT
    return $res;
}

#
# remove preferred protocol for user
#
sub unset_preferred_protocol {
    my ($username) = @_;
    return unless $username;
    my $dbh = get_dbh();
    my $res = $dbh->do( <<'EOT', {}, $username );
DELETE FROM
  prefprot
WHERE
  username LIKE ?
EOT
    return $res;
}

#
# returns group_protocol for (group, user) or undef if NULL
#
sub get_group_protocol {
    my ( $group, $user ) = @_;
    $user = aliastouser($user);
    return unless $group and $user;
    my $dbh = get_dbh();
    my $res = $dbh->selectrow_array( <<'EOT', {}, $group, $user );
SELECT
  protocol
FROM
  herd
WHERE
  herdname like ? and
  username like ?
EOT
    return $res;
}

#
# sets group_protocol for group, user
#
sub set_group_protocol {
    my ( $groupname, $username, $protocol ) = @_;
    $username = aliastouser($username);
    return unless $groupname and $username and $protocol;
    my $dbh = get_dbh();
    my $res = $dbh->do( <<'EOT', {}, $protocol, $groupname, $username );
UPDATE
   herd  
SET
   protocol = ?
WHERE
   herdname like ? and
   username like ?
EOT
    return $res;
}

#
# sets group_protocol for group, user to NULL
#
sub unset_group_protocol {
    my ( $groupname, $username ) = @_;
    $username = aliastouser($username);
    return unless $username and $groupname;
    my $dbh = get_dbh();
    my $res = $dbh->do( <<'EOT', {}, $groupname, $username );
UPDATE
   herd    
SET
   protocol = NULL
WHERE
   herdname like ? and
   username like ?
EOT
    return $res;
}

#
# Adds a box for user without units
#
sub add_box {
    my ( $boxname, $user ) = @_;
    $user = aliastouser($user);
    return unless $boxname and $user;
    my $dbh = get_dbh();
    my $res = $dbh->do( <<'EOT', {}, $boxname, $user );
INSERT INTO
  box ( boxname, username, contents)  
VALUES
  ( ? , ? , 0 )
EOT
    return $res;
}

#
# Deletes a box for a user
#
sub remove_box {
    my ( $boxname, $user ) = @_;
    $user = aliastouser($user);
    return unless $boxname and $user;
    my $dbh = get_dbh();
    my $res = $dbh->do( <<'EOT', {}, $boxname, $user );
DELETE FROM
  box
WHERE
  boxname = ? and
  username = ? 
EOT
    return $res;
}

#
# Gets the value for a box,username
#
sub get_box {
    my ( $boxname, $user ) = @_;
    $user = aliastouser($user);
    return unless $boxname and $user;
    my $dbh = get_dbh();
    my $res = $dbh->selectrow_array( <<'EOT', {}, $user, $boxname );
SELECT
  contents
FROM  
  box
WHERE
  username like ? AND
  boxname like ?
EOT
    return $res;
}

#
#
#
sub inc_box {
    my ( $boxname, $user, $units ) = @_;
    $user = aliastouser($user);
    return unless $boxname and $user;
    my $dbh = get_dbh();
    my $res = $dbh->do( <<'EOT', {}, $units, $user, $boxname );
UPDATE 
  box 
SET
  contents = contents + ?
WHERE  
  username = ? AND
  boxname  = ? 
EOT
    return $res;

}

#
#
#
sub dec_box {
    my ( $boxname, $user, $units ) = @_;
    $user = aliastouser($user);
    return unless $boxname and $user;
    my $dbh = get_dbh();
    my $res = $dbh->do( <<'EOT', {}, $units, $user, $boxname );
UPDATE      
  box 
SET     
  contents = contents - ?
WHERE
  username = ? AND
  boxname  = ?  
EOT
    return $res;
}

#
#
#
sub set_box {
    my ( $boxname, $user, $units ) = @_;
    $user = aliastouser($user);
    return unless $boxname and $user;
    my $dbh = get_dbh();
    my $res = $dbh->do( <<'EOT', {}, $user, $boxname, $units );
REPLACE INTO
  box (username, boxname, contents)
VALUES
  (?,?,?)
EOT
    return $res;
}


#
# Lists boxes for a user or all boxes
#
sub list_boxes {
    my ( $user ) = @_;
    my $dbh = get_dbh();
    if ( defined $user and ($user = aliastouser($user)) ) {
        my $res = $dbh->selectcol_arrayref( <<'EOT', {}, $user );
SELECT
  boxname
FROM  
  box
WHERE
  username like ?
EOT
        return $res;
    } else { 
        my $res = $dbh->selectcol_arrayref( <<'EOT', {} );
SELECT
  distinct(boxname)
FROM  
  box
EOT
        return $res;
    }
}


#
# - Check if user has enough units in the requested box
# - Claim those credits and store transaction ID
# - Real withdrawal is done by the commit_expenditure (or rollback if failed)
#
# FIXME - This function probably doesn't belong in this module :)
#
sub authorize_expenditure {

}

#
# commit changes to box,user identified by transaction ID
#
sub commit_expenditure {

}

#
# rollback the claim on a box,user identified by transaction ID
#
sub rollback_expenditure {

}

#
# This is a shortcut for authorize_expenditure and commit_expenditure
# We probably want to get rid of it as soon as the other 2 are implemented properly
# Returns the number of units withdrawn (succes) or undef (failure)
#

sub check_and_withdraw {
    my ( $boxname, $user, $amount ) = @_;
    return undef
      unless ( defined $boxname and defined $user and defined $amount );
    my $balance = get_box( $boxname, $user );
    if ( ( defined $balance ) and ( $balance >= $amount ) ) {
        if ( dec_box( $boxname, $user, $amount ) ) {
            return $amount;
        }
        else {

            # Can this ever be reached???
            return undef;
        }
    }
    else {
        return undef;
    }
}

# all went well
1;

