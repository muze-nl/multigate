#!/usr/bin/perl -w

#
# multigate admin level user edit module
# (C) 2000,2001 Wieger Opmeer
#

#
# Imports and global vars
#

use strict;
use vars qw( $r $req $user $level $args %args $dbh );
#MP2
use Apache2::Request;
use Apache2::RequestUtil ();
use ModPerl::Util qw( exit );
#MP1
#use Apache::Util qw( escape_html exit );
use FileHandle;
use lib '../../lib';
use Multigate::Config qw( getconf readconfig );
use Multigate::Users;

#
# ---------------------------------------------------------
# main
#

my ( $action, $subref, %dispatch, $password, $fh );

%dispatch = (
    'showallusers'         => \&showallusers,
    'showallaliases'       => \&showallaliases,
    'showalladdresses'     => \&showalladdresses,
    'showuser'             => \&showuser,
    'newuser'              => \&newuser,
    'makenewuser'          => \&makenewuser,
    'edituserinfo'         => \&edituserinfo,
    'saveuserinfo'         => \&saveuserinfo,
    'deleteuser'           => \&deleteuser,
    'reallydeleteuser'     => \&reallydeleteuser,
    'editaliases'          => \&editaliases,
    'editalias'            => \&editalias,
    'deletealias'          => \&deletealias,
    'savealias'            => \&savealias,
    'newalias'             => \&newalias,
    'changepassword'       => \&changepassword,
    'reallychangepassword' => \&reallychangepassword,
    'editaddress'          => \&editaddress,
    'saveaddress'          => \&saveaddress,
    'deleteaddress'        => \&deleteaddress,
    'reallydeleteaddress'  => \&reallydeleteaddress,
    'newaddress'           => \&newaddress,
    '_default_'            => \&showallusers,
);

#MP1
#$r = Apache->request;
#$user = $r->connection->user;
#MP2
$r = Apache2::RequestUtil->request;
$req = Apache2::Request->new($r);
$r->content_type('text/html');
#MP1
#$user = $r->connection->user;
#MP2
$user = $r->user;

$fh = new FileHandle;

readconfig("../../multi.conf");    #allowed this way?
my $password = getconf('db_passwd');
my $db_user  = getconf('db_user');
my $database = getconf('db_name');
$dbh = DBI->connect( 'DBI:mysql:' . $database,
    $db_user, $password, { RaiseError => 0, AutoCommit => 1 } );

if ( !defined $dbh ) {
    print STDERR DBI::errstr;
    exit 0;
}


$level = $dbh->selectrow_array( <<'EOT', {}, $user );
SELECT
  level
FROM
  user
WHERE
  username LIKE ?
EOT

if ( $level < 1000 ) {
    printheader();
    print <<'EOT';
Error: unsufficient privileges to access admin mode!
EOT
    printfooter();
    $r->exit();
}

#MP1
#%args = $r->method eq 'POST' ? $r->content : $r->args;
#MP2
$args = $req->param;
%args = %$args if $args;

if (    ( $action = $args{'action'} )
    and ( $subref = $dispatch{$action} ) )
{
    &$subref();
}
else {
    $subref = $dispatch{'_default_'};
    &$subref();
}

#MP1
#$r->exit;
#MP2
exit;

#
# ---------------------------------------------------------
#
sub showallusers {
    my ( $allusers, $un, $irl, $ul, $bd, $bt );

    $allusers = $dbh->selectall_arrayref( <<'EOT' );
SELECT
  username, irl, level, birthday, birthtime
FROM
  user
ORDER BY
  username
EOT

    printheader();
    print <<'EOT';
<table border="1" cellpadding="2">
<tr>
<th colspan="6">All users of Multigate</th>
</tr>

<tr>
<th align="left">Username</th>
<th align="left">IRL</th>
<th align="left">Level</th>
<th align="left">Birth date</th>
<th align="left">Birth time</th>
<td>&nbsp;</td>
</tr>
EOT

    foreach (@$allusers) {
        ( $un, $irl, $ul, $bd, $bt ) = @$_;
        $irl = '*unknown*' unless $irl;
        $bd  = '*unknown*' unless $bd;
        $bt  = '*unknown*' unless $bt;
        print <<"EOT";
<tr>
<td>$un</td>
<td>$irl</td>
<td>$ul</td>
<td>$bd</td>
<td>$bt</td>
<form><input type="hidden" name="action" value="showuser">
<input type="hidden" name="username" value="$un">
<td align="center">
<input type="submit" value="Show">
</td></form>
</tr>
EOT
    }

    print <<'EOT';
<tr>
<form><input type="hidden" name="action" value="newuser">
<td colspan="7" align="center">
<input type="submit" value="New User">
</td></form>
</tr>
</table>
EOT

    printfooter();
}

#
# ---------------------------------------------------------
#
sub showallaliases {
    my ( $allaliases, $un, $alias, %aliases );

    $allaliases = $dbh->selectall_arrayref( <<'EOT' );
SELECT
  username, alias
FROM
  alias
EOT

    foreach (@$allaliases) {
        ( $un, $alias ) = @$_;
        if ( exists $aliases{$un} ) {
            push @{ $aliases{$un} }, $alias;
        }
        else {
            $aliases{$un} = [$alias];
        }
    }

    printheader();
    print <<'EOT';
<table border="1" cellpadding="2">
<tr>
<th colspan="3">All aliases known</th>
</tr>

<tr>
<th align="left">Username</th>
<th align="left">Aliases</th>
<td>&nbsp;</td>
</tr>
EOT

    foreach $un ( keys %aliases ) {
        $alias = join( ' ', @{ $aliases{$un} } );
        print <<"EOT";
<tr>
<td>$un</td>
<td>$alias</td>
<form><input type="hidden" name="action" value="editaliases">
<input type="hidden" name="username" value="$un">
<input type="hidden" name="prevaction" value="showallaliases">
<td align="center">
<input type="submit" value="Edit">
</td></form>
</tr>
EOT
    }

    print <<'EOT';
</table>
EOT
    printfooter();

}

#
# ---------------------------------------------------------
#
sub showalladdresses {
    my ($addr);

    $addr = $dbh->selectall_arrayref( <<'EOT');
SELECT
  username, protocol, address, main_address
FROM
  address
ORDER BY
  username
EOT

    printheader();
    print <<'EOT';
<table border="1" cellpadding="2">
<tr>
<th colspan="6">Adresses</th>
</tr>
<tr>
<th>User</th><th>Protocol</th><th>Address</th><th>Main</th><th colspan="2">&nbsp;</th>
</tr>
EOT

    foreach (@$addr) {
        my ( $un, $prot, $addr, $prim ) = @$_;
        $un   = escape_html($un);
        $prot = escape_html($prot);
        $addr = escape_html($addr);
        $prim = ( $prim eq 'true' ) ? 'main' : '&nbsp';
        print <<"EOT";
<tr>
<td>$un</td>
<td>$prot</td>
<td>$addr</td>
<td>$prim</td>
<form><input type="hidden" name="action" value="editaddress">
<input type="hidden" name="prevaction" value="showalladdresses">
<input type="hidden" name="username" value="$un">
<input type="hidden" name="protocol" value="$prot">
<input type="hidden" name="address" value="$addr"><td align="center">
<input type="submit" value="Edit">
</td></form>
<form><input type="hidden" name="action" value="deleteaddress">
<input type="hidden" name="prevaction" value="showalladdresses">
<input type="hidden" name="username" value="$un">
<input type="hidden" name="protocol" value="$prot">
<input type="hidden" name="address" value="$addr"><td>
<input type="submit" value="Delete">
</td></form>
</tr>
EOT

    }

    print <<'EOT';
</table>
EOT
    printfooter();
    return;

}

#
# ---------------------------------------------------------
# Show information of a user, with edit possibility
#
sub showuser {
    my ( $un, $ul, $irl, $bd, $bt, @prot, $addr, $opts );

    $un = $args{'username'};

    ( $irl, $ul, $bd, $bt ) = $dbh->selectrow_array( <<'EOT', {}, $un );
SELECT
  irl, level, birthday, birthtime
FROM
  user
WHERE
  username LIKE ?
EOT

    $irl = '*unknown*' unless $irl;
    $bd  = '*unknown*' unless $bd;
    $bt  = '*unknown*' unless $bt;

    printheader();
    print <<"EOT";


<table border="1" cellpadding="2">
<tr>
<th colspan="3">User Info</th>
</tr>

<tr>
<th align="left">Username</th>
<td colspan="2">$un</td>
</tr>

<tr>
<th align="left">IRL</th>
<td colspan="2">$irl</td>
</tr>

<tr>
<th align="left">Level</th>
<td colspan="2">$ul</td>
</tr>

<tr>
<th align="left">Birth date</th>
<td colspan="2">$bd</td>
</tr>

<tr>
<th align="left">Birth time</th>
<td colspan="2">$bt</td>
</tr>

<tr>
<form><input type="hidden" name="action" value="edituserinfo">
<input type="hidden" name="username" value="$un"><td>
<input type="submit" value="Edit User Info">
</td></form>
<form><input type="hidden" name="action" value="changepassword">
<input type="hidden" name="username" value="$un"><td>
<input type="submit" value="Change Password">
</td></form>
<form><input type="hidden" name="action" value="deleteuser">
<input type="hidden" name="username" value="$un"><td>
<input type="submit" value="Delete User">
</td></form>
</tr>
</table>
<br>
EOT

    my ( $aliases, $alias );

    $aliases = $dbh->selectcol_arrayref( <<'EOT', {}, $un );
SELECT
  alias
FROM
  alias
WHERE
  username = ?
EOT

    if ( $aliases and scalar @$aliases > 0 ) {
        $alias = join( ' ', @$aliases );

        print <<"EOT";
<table border="1" cellpadding="2">
<tr>
<th colspan="2">Aliases</th>
</tr>
<tr>
<td>$alias</td>
<form><input type="hidden" name="action" value="editaliases">
<input type="hidden" name="prevaction" value="showuser">
<input type="hidden" name="username" value="$un">
<td align="center">
<input type="submit" value="Edit">
</td></form>
</tr>
</table>
EOT

    }
    else {
        print <<"EOT";
<table border="1" cellpadding="2">
<tr><form>
<td><input type="text" size="32" name="alias"></td>
<input type="hidden" name="action" value="newalias">
<input type="hidden" name="username" value="$un">
<td align="center">
<input type="submit" value="New Alias">
</td></form>
</tr>
</table>
EOT

    }

    print <<'EOT';
<br>
<table border="1" cellpadding="2">
<tr>
<th colspan="5">Adresses</th>
</tr>
EOT

    $addr = $dbh->selectall_arrayref( <<'EOT', {}, $un );
SELECT
  protocol, address, main_address
FROM
  address
WHERE
  username LIKE ?
EOT

    foreach (@$addr) {
        my ( $prot, $addr, $prim, $main ) = @$_;
        $prot = escape_html($prot);
        $addr = escape_html($addr);
        $main = ( $prim eq 'true' ) ? 'main' : '&nbsp';
        print <<"EOT";
<tr>
<th align="left">$prot</th>
<td>$addr</td>
<td>$main</td>
<form><input type="hidden" name="action" value="editaddress">
<input type="hidden" name="prevaction" value="showuser">
<input type="hidden" name="username" value="$un">
<input type="hidden" name="protocol" value="$prot">
<input type="hidden" name="address" value="$addr">
<input type="hidden" name="primary" value="$prim"><td align="center">
<input type="submit" value="Edit">
</td></form>
<form><input type="hidden" name="action" value="deleteaddress">
<input type="hidden" name="prevaction" value="showuser">
<input type="hidden" name="username" value="$un">
<input type="hidden" name="protocol" value="$prot">
<input type="hidden" name="address" value="$addr"><td>
<input type="submit" value="Delete">
</td></form>
</tr>
EOT

    }

    @prot = getprotocols();

    foreach (@prot) {
        $opts .= "<option value=\"$_\">$_";
    }

    print <<"EOT";
<tr>
<form>
<input type="hidden" name="action" value="newaddress">
<input type="hidden" name="username" value="$un">
<td>
<select name="protocol"><option value="protocol" selected>protocol
$opts
</select>
</td>
<td><input type="text" name="address" size="50"></td>
<td align="center"><input type="checkbox" name="main"></td>
<td colspan="2" align="center"><input type="submit" value="New"></td>
</form>
</tr>
</table>
EOT

    printfooter();
    return;
}

#
# ---------------------------------------------------------
# Edit user info
#
sub edituserinfo {

    my ( $un, $ul, $irl, $bd, $bt, @prot, $addr, $opts );

    $un = $args{'username'};

    ( $irl, $ul, $bd, $bt ) = $dbh->selectrow_array( <<'EOT', {}, $un );
SELECT
  irl, level, birthday, birthtime
FROM
  user
WHERE
  username LIKE ?
EOT

    $irl = '*unknown*' unless $irl;
    $bd  = '*unknown*' unless $bd;
    $bt  = '*unknown*' unless $bt;

    printheader();
    print <<"EOT";


<table border="1" cellpadding="2">
<tr>
<th colspan="2">User Info</th>
</tr>

<form>
<input type="hidden" name="action" value="saveuserinfo">
<input type="hidden" name="username" value="$un">
<tr>
<th align="left">Username</th>
<td>$un</td>
</tr>

<tr>
<th align="left">IRL</th>
<td><input type="text" size="30" name="irl" value="$irl"></td>
</tr>

<tr>
<th align="left">Level</th>
<td><input type="text" size="5" name="userlevel" value="$ul"></td>
</tr>

<tr>
<th align="left">Birth date (yyyy-mm-dd)</th>
<td><input type="text" size="10" name="birthdate" value="$bd"></td>
</tr>

<tr>
<th align="left">Birth time (hh:mm:ss)</th>
<td><input type="text" size="8" name="birthtime" value="$bt"></td>
</tr>

<tr>
<td align="center"><input type="submit" value="Save"></td>
</form><form><input type="hidden" name="action" value="showuser">
<input type="hidden" name="username" value="$un">
<td align="center"><input type="submit" value="Cancel"></td>
</form>
</tr>
</form>
</table>
EOT

    return;
}

#
# ---------------------------------------------------------
#
sub saveuserinfo {
    my ( $un, $irl, $ul, $bd, $bt, $err, $res );
    $un  = $args{'username'};
    $irl = $args{'irl'};
    $ul  = $args{'userlevel'};
    $bd  = $args{'birthdate'};
    $bt  = $args{'birthtime'};

    $ul = undef unless $ul =~ /^\d+$/;
    $bd = undef unless $bd =~ /^\d\d\d\d-\d\d-\d\d$/;
    $bt = undef unless $bt =~ /^\d\d:\d\d(:\d\d)?$/;

    $res = $dbh->do( <<'EOT', {}, $irl, $ul, $bd, $bt, $un );
UPDATE
  user
SET
  irl = ?,
  level = ?,
  birthday = ?,
  birthtime = ?
WHERE
  username like ?
EOT

    printheader();
    print <<"EOT";
Saved!
<br>
<br>
<form><input type="hidden" name="action" value="showuser">
<input type="hidden" name="username" value="$un">
<input type="submit" value="Back">
</form>
EOT

    return;
}

#
# ---------------------------------------------------------
#
sub newuser {

    my ( $un, $ul, $irl, $bd, $bt, @prot, $addr, $opts );

    printheader();
    print <<'EOT';

<table border="1" cellpadding="2">
<tr>
<th colspan="2">New User:</th>
</tr>

<form>
<input type="hidden" name="action" value="makenewuser">
<tr>
<th align="left">Username</th>
<td><input type="text" size="32" name="username"></td>
</tr>

<tr>
<th align="left">Password</th>
<td><input type="text" size="32" name="password"></td>
</tr>

<tr>
<th align="left">IRL</th>
<td><input type="text" size="64" name="irl"></td>
</tr>

<tr>
<th align="left">Level</th>
<td><input type="text" size="5" name="userlevel"></td>
</tr>

<tr>
<th align="left">Birth date (yyyy-mm-dd)</th>
<td><input type="text" size="10" name="birthdate"></td>
</tr>

<tr>
<th align="left">Birth time (hh:mm:ss)</th>
<td><input type="text" size="8" name="birthtime"></td>
</tr>

<tr>

<td align="center"><input type="submit" value="Save"></td>
</form>
<form><input type="hidden" name="action" value="showallusers">
<td align="center"><input type="submit" value="Cancel"></td>
</form>
</tr>

</table>
EOT

    return;
}

#
# ---------------------------------------------------------
#
sub makenewuser {
    my ( $un, $irl, $ul, $pw, $cpw, $bd, $bt, $err, $res );
    $un  = $args{'username'};
    $pw  = $args{'password'};
    $irl = $args{'irl'};
    $ul  = $args{'userlevel'};
    $bd  = $args{'birthdate'};
    $bt  = $args{'birthtime'};

    unless ($un) {
        printheader();
        print <<"EOT";
Please fill in a username!
<br>
<br>
<form><input type="hidden" name="action" value="newuser">
<input type="submit" value="Back">
</form>
EOT
        printfooter();
        return;
    }

    $res = $dbh->selectrow_array( <<'EOT', {}, $un );
SELECT
  username
FROM
  user
WHERE
  username = ?
EOT

    if ($res) {
        printheader();
        print <<"EOT";
User '$un' already exists!
<br>
<br>
<form><input type="hidden" name="action" value="newuser">
<input type="submit" value="Back">
</form>
EOT
        printfooter();
        return;
    }

    $cpw = ($pw) ? crypt( $pw, salt() ) : undef;
    $ul = 0     unless $ul =~ /^\d+$/;
    $bd = undef unless $bd =~ /^\d\d\d\d-\d\d-\d\d$/;
    $bt = undef unless $bt =~ /^\d\d\d\d-\d\d-\d\d$/;

    $res = $dbh->do( <<'EOT', {}, $un, $cpw, $irl, $ul, $bd, $bt );
INSERT INTO
  user
SET
  username = ?,
  password = ?,
  irl = ?,
  level = ?,
  birthday = ?,
  birthtime = ?
EOT

    printheader();
    print <<"EOT";
Created new user '$un'.
<br>
<br>
<form><input type="hidden" name="action" value="showuser">
<input type="hidden" name="username" value="$un">
<input type="submit" value="Back">
</form>
EOT

    return;
}

#
# ---------------------------------------------------------
#
sub changepassword {
    my ($un);
    $un = $args{'username'};

    printheader();
    print <<"EOT";
<table border="1" cellpadding="2">
<tr>
<th colspan="2">Enter new password for user '$un'</th>
</tr><tr>
<form><input type="hidden" name="action" value="reallychangepassword">
<input type="hidden" name="username" value="$un"><td colspan="2">
<input type="text" size="32" name="password"></td>
</tr><tr>
<td align="center"><input type="Submit" value="Change Password"></td></form>
<form><input type="hidden" name="action" value="showuser">
<input type="hidden" name="username" value="$un"><td align="center">
<input type="Submit" value="Cancel"></td></form>
</table>
EOT

    printfooter();
    return;
}

#
# ---------------------------------------------------------
#
sub reallychangepassword {
    my ( $un, $pw, $cpw );
    $un = $args{'username'};
    $pw = $args{'password'};

    $cpw = crypt( $pw, salt() );
    $dbh->do( <<'EOT', {}, $cpw, $un );
UPDATE
  user
SET
  password = ?
WHERE
  username like ?
EOT

    printheader();
    print <<"EOT";
Changed!
<br>
<br>
<form><input type="hidden" name="action" value="showuser">
<input type="hidden" name="username" value="$un">
<input type="submit" value="Back">
</form>
EOT

    printfooter();
    return;
}

#
# ---------------------------------------------------------
#
sub deleteuser {
    my ($un);
    $un = $args{'username'};

    printheader();
    print <<"EOT";
<table border="1" cellpadding="2">
<tr>
<th colspan="2">Really delete user '$un'?</th>
</tr><tr>
<form><input type="hidden" name="action" value="reallydeleteuser">
<input type="hidden" name="username" value="$un">
<td align="center"><input type="Submit" value="Delete"></td></form>
<form><input type="hidden" name="action" value="showuser">
<input type="hidden" name="username" value="$un"><td align="center">
<input type="Submit" value="Cancel"></td></form>
</table>
EOT

    printfooter();
    return;
}

#
# ---------------------------------------------------------
#
sub reallydeleteuser {
    my ( $un, $err, $res );
    $un = $args{'username'};

    $res = $dbh->do( <<'EOT', {}, $un );
DELETE FROM
  user
WHERE
  username like ?
EOT

    $res = $dbh->do( <<'EOT', {}, $un );
DELETE FROM
  alias
WHERE
  username like ?
EOT

    $res = $dbh->do( <<'EOT', {}, $un );
DELETE FROM
  address
WHERE
  username like ?
EOT

    printheader();
    print <<"EOT";
<table border="1" cellpadding="2">
<tr>
<th colspan="2">Deleted user '$un'</th>
</tr>
<tr>
<form>
<td colspan="2" align="center"><input type="submit" value="Back"></td>
</form>
</tr>
</table>
EOT

    printfooter();

    return;
}

#
# ---------------------------------------------------------
#
sub editaliases {
    my ( $prev, $un, $aliases, $alias );
    $prev = $args{'prevaction'};
    $un   = $args{'username'};

    $aliases = $dbh->selectcol_arrayref( <<'EOT', {}, $un );
SELECT
  alias
FROM
  alias
WHERE
  username = ?
EOT

    printheader();
    print <<"EOT";
<table border="1" cellpadding="2">
<tr>
<th colspan="3">Aliases for user '$un'</th>
</tr>
EOT

    foreach $alias (@$aliases) {
        print <<"EOT";
<tr>
<td>$alias</td>
<form><input type="hidden" name="action" value="editalias">
<input type="hidden" name="prevaction" value="$prev">
<input type="hidden" name="username" value="$un">
<input type="hidden" name="alias" value="$alias">
<td align="center">
<input type="submit" value="Edit">
</td></form>
<form><input type="hidden" name="action" value="deletealias">
<input type="hidden" name="prevaction" value="$prev">
<input type="hidden" name="username" value="$un">
<input type="hidden" name="alias" value="$alias">
<td align="center">
<input type="submit" value="Delete">
</td></form>
</tr>
EOT

    }

    print <<"EOT";
<tr>
<form><input type="hidden" name="action" value="newalias">
<input type="hidden" name="prevaction" value="$prev">
<input type="hidden" name="username" value="$un">
<td><input type="text" size="32" name="alias">
<td colspan="2" align="center"><input type="submit" value="New"></td></form>
</tr><tr>
<form><input type="hidden" name="action" value="$prev">
<input type="hidden" name="username" value="$un">
<td colspan="3" align="center"><input type="submit" value="Done"></td></form>
</tr>
</table>
EOT

    printfooter();
    return;
}

#
# ---------------------------------------------------------
#
sub editalias {
    my ( $prev, $un, $alias );

    $prev  = $args{'prevaction'};
    $un    = $args{'username'};
    $alias = $args{'alias'};

    printheader();
    print <<"EOT";
<table border="1" cellpadding="2">
<tr>
<th colspan="2">Edit alias for user '$un'</th>
</tr><form><tr>
<input type="hidden" name="action" value="savealias">
<input type="hidden" name="username" value="$un">
<input type="hidden" name="oldalias" value="$alias">
<input type="hidden" name="prevaction" value="$prev">
<td colspan="2"><input type="text" size="32" name="alias" value="$alias"></td>
</tr><tr>
<td align="center"><input type="submit" value="Save"></td>
</form><form><input type="hidden" name="action" value="editaliases">
<input type="hidden" name="prevaction" value="$prev">
<input type="hidden" name="username" value="$un"><td>
<input type="submit" value="Cancel"></td><td>&nbsp;</td>
</tr>
</form>
</table>
EOT

    printfooter();
    return;
}

#
# ---------------------------------------------------------
#
sub deletealias {
    my ( $prev, $un, $alias, $err, $res );
    $prev  = $args{'prevaction'};
    $un    = $args{'username'};
    $alias = $args{'alias'};

    $res = $dbh->do( <<'EOT', {}, $un, $alias );
DELETE FROM
  alias
WHERE
  username like ? and
  alias like ?
EOT

    printheader();
    print <<"EOT";
<table border="1" cellpadding="2">
<tr>
<td>Deleted alias '$alias' for user '$un'</td>
</tr>
<tr>
<form>
<input type="hidden" name="action" value="editaliases">
<input type="hidden" name="prevaction" value="$prev">
<input type="hidden" name="username" value="$un">
<td align="center"><input type="submit" value="Back"></td>
</form>
</tr>
</table>
EOT

    printfooter();
    return;
}

#
# ---------------------------------------------------------
#
sub savealias {
    my ( $prev, $un, $alias, $oldalias, $err, $res );
    $prev     = $args{'prevaction'};
    $un       = $args{'username'};
    $alias    = $args{'alias'};
    $oldalias = $args{'oldalias'};

    $res = $dbh->do( <<'EOT', {}, $alias, $un, $oldalias );
UPDATE
  alias
SET
  alias = ?
WHERE
  username like ? and
  alias like ?
EOT

    printheader();
    print <<"EOT";
Saved!
<br>
<br>
<form><input type="hidden" name="action" value="editaliases">
<input type="hidden" name="prevaction" value="$prev">
<input type="hidden" name="username" value="$un">
<input type="submit" value="Back">
</form>
EOT

    return;
}

#
# ---------------------------------------------------------
#
sub newalias {
    my ( $prev, $un, $alias, $err, @res );
    $prev  = $args{'prevaction'};
    $un    = $args{'username'};
    $alias = $args{'alias'};

    @res = $dbh->selectrow_array( <<'EOT', {}, $alias );
SELECT
  username, alias
FROM
  alias
WHERE
  alias = ?
EOT

    if (@res) {
        printheader();
        print <<"EOT";
Alias '$alias' already exists for user '$un'!
<br>
<br>
<form><input type="hidden" name="action" value="editaliases">
<input type="hidden" name="prevaction" value="$prev">
<input type="hidden" name="username" value="$un">
<input type="submit" value="Back">
</form>
EOT
        printfooter();
        return;
    }

    $err = $dbh->do( <<'EOT', {}, $un, $alias );
INSERT INTO
  alias
SET
  username =?,
  alias = ?
EOT

    printheader();
    print <<"EOT";
Created new alias '$alias' for user '$un'.
<br>
<br>
<form><input type="hidden" name="action" value="editaliases">
<input type="hidden" name="prevaction" value="$prev">
<input type="hidden" name="username" value="$un">
<input type="submit" value="Back">
</form>
EOT

    return;
}

#
# ---------------------------------------------------------
# Edit Address
#
sub editaddress {
    my ( $prev, $un, $prot, $addr, $prim, $main );

    $prev = $args{'prevaction'};
    $un   = $args{'username'};
    $prot = $args{'protocol'};
    $addr = $args{'address'};
    $prim = $args{'primary'};

    $prot = escape_html($prot);
    $addr = escape_html($addr);
    $main = ( $prim eq 'true' ) ? ' checked' : '';

    printheader();
    print <<"EOT";
<table border="1" cellpadding="2">
<tr>
<th colspan="3">Edit Address for user '$un'</th>
</tr><form><tr>
<input type="hidden" name="action" value="saveaddress">
<input type="hidden" name="username" value="$un">
<input type="hidden" name="protocol" value="$prot">
<input type="hidden" name="oldaddress" value="$addr">
<input type="hidden" name="prevaction" value="$prev">
<td>$prot</td>
<td><input type="text" size="55" name="address" value="$addr"></td>
<td align="center"><input type="checkbox" name="main"$main></td>
</tr><tr>
<td align="center"><input type="submit" value="Save"></td>
</form><form><input type="hidden" name="action" value="$prev">
<input type="hidden" name="username" value="$un"><td>
<input type="submit" value="Cancel"></td><td>&nbsp;</td>
</tr>
</form>
</table>
EOT

    printfooter();
    return;
}

#
# ---------------------------------------------------------
# Delete Address
#
sub deleteaddress {
    my ( $prev, $un, $prot, $addr, $main, $err, $res );
    $prev = $args{'prevaction'};
    $un   = $args{'username'};
    $prot = $args{'protocol'};
    $addr = $args{'address'};

    printheader();
    print <<"EOT";
<table border="1" cellpadding="2">
<tr>
<th colspan="2">Really delete address?</th>
</tr>
<tr>
<td>$prot</td>
<td>$addr</td>
</tr>
<tr>
<form>
<input type="hidden" name="action" value="reallydeleteaddress">
<input type="hidden" name="username" value="$un">
<input type="hidden" name="protocol" value="$prot">
<input type="hidden" name="address" value="$addr">
<input type="hidden" name="prevaction" value="$prev">
<td align="center"><input type="submit" value="Delete"></td>
</form>
<form>
<input type="hidden" name="action" value="$prev">
<input type="hidden" name="username" value="$un">
<td align="center"><input type="submit" value="Cancel"></td>
</form>
</tr>
</table>
EOT

    printfooter();

    return;
}

#
# ---------------------------------------------------------
#
sub reallydeleteaddress {
    my ( $prev, $un, $prot, $addr, $main, $err, $res );
    $prev = $args{'prevaction'};
    $un   = $args{'username'};
    $prot = $args{'protocol'};
    $addr = $args{'address'};

    $res = $dbh->do( <<'EOT', {}, $un, $prot, $addr );
DELETE FROM
  address
WHERE
  username like ? and
  protocol like ? and
  address like ?
EOT

    printheader();
    print <<"EOT";
<table border="1" cellpadding="2">
<tr>
<th colspan="2">Deleted:</th>
</tr>
<tr>
<th>Protocol</th>
<th>Address</th>
</tr>
<tr>
<td>$prot</td>
<td>$addr</td>
</tr>
<tr>
<form><input type="hidden" name="action" value="$prev">
<input type="hidden" name="username" value="$un">
<td colspan="2" align="center"><input type="submit" value="Back"></td>
</form>
</tr>
</table>
EOT

    printfooter();
    return;
}

#
# ---------------------------------------------------------
#
sub saveaddress {
    my ( $prev, $un, $prot, $addr, $oldaddr, $main, $err, $res );
    $prev    = $args{'prevaction'};
    $un      = $args{'username'};
    $prot    = $args{'protocol'};
    $addr    = $args{'address'};
    $oldaddr = $args{'oldaddress'};
    $main    = $args{'main'};

    if ( $main eq 'on' ) {
        $main = 'true';

        $res = $dbh->do( <<'EOT', {}, $un, $prot );
UPDATE
  address
SET
  main_address = 'false'
WHERE
  username like ? and
  protocol like ?
EOT

    }
    else {
        $main = 'false';
    }

    $res = $dbh->do( <<'EOT', {}, $addr, $main, $un, $prot, $oldaddr );
UPDATE
  address
SET
  address = ?,
  main_address = ?
WHERE
  username like ? and
  protocol like ? and
  address like ?
EOT

    printheader();
    print <<"EOT";
Saved!
<br>
<br>
<form><input type="hidden" name="action" value="$prev">
<input type="hidden" name="username" value="$un">
<input type="submit" value="Back">
</form>
EOT

    return;
}

#
# ---------------------------------------------------------
#
sub newaddress {
    my ( $un, $prot, $addr, $main, $err, $res );
    $un   = $args{'username'};
    $prot = $args{'protocol'};
    $addr = $args{'address'};
    $main = $args{'main'};
    $err  = '';
    $err .= 'Empty protocol?<br>' unless $prot;
    $err .= 'Please select a protocol,<br>' if $prot eq 'protocol';
    $err .= 'Empty address?<br>' unless $addr;

    if ( $err ne '' ) {
        my ( @prots, $opts );

        $opts = "<option value=\"$prot\" selected>$prot";

        @prots = getprotocols();

        foreach (@prots) {
            $opts .= "<option value=\"$_\">$_";
        }

        $un   = escape_html($un);
        $prot = escape_html($prot);
        $addr = escape_html($addr);
        $main = ( $main eq 'on' ) ? ' checked' : '';

        printheader();
        print <<"EOT";
<table border="1" cellpadding="2">
<tr>
<th>Error:</th>
</tr>
<tr>
<td>$err</td>
</tr>
</table>
<br>
<table border="1" cellpadding="2">
<tr>
<form>
<input type="hidden" name="action" value="newaddress">
<input type="hidden" name="username" value="$un">
<td>
<select name="protocol">
$opts
</select>
</td>
<td><input type="text" name="address" value= "$addr" size="55"></td>
<td align="center"><input type="checkbox" name="main"$main></td>
<td align="center"><input type="submit" value="New"></td>
</form>
<form><input type="hidden" name="action" value="showuser">
<input type="hidden" name="username" value="$un">
<td align="center"><input type="submit" value="Cancel"></td>
</form>
</tr>
</table>
EOT

        printfooter();
        return;
    }

    if ( $main eq 'on' ) {
        $main = 'true';

        $res = $dbh->do( <<'EOT', {}, $un, $prot );
UPDATE
  address
SET
  main_address = 'false'
WHERE
  username like ? and
  protocol like ?
EOT

    }
    else {
        $main = 'false';
    }

    $res = $dbh->do( <<'EOT', {}, $un, $prot, $addr, $main );
INSERT INTO
  address (username, protocol, address, main_address)
VALUES
  (?, ?, ?, ?)
EOT

    $main = ( $main eq 'true' ) ? 'main' : '&nbsp;&nbsp;&nbsp;&nbsp;';

    printheader();
    print <<"EOT";
<table border="1" cellpadding="2">
<tr>
<th colspan="3">Address added succesfully:</th>
</tr>
<tr>
<td>$prot</td>
<td>$addr</td>
<td>$main</td>
</tr>
<tr><form><input type="hidden" name="action" value="showuser">
<input type="hidden" name="username" value="$un">
<td colspan="3" align="center"><input type="submit" value="Back"></td>
</form>
</tr>
</table>
EOT

    printfooter();

    return;
}

#
# ---------------------------------------------------------
#
sub not_implemented {
    printheader();
    print <<'EOT';
Not Implemented Yet.
<br>
<br>
<form>
<td align="center"><input type="submit" value="Back"></td>
</form>
EOT
    printfooter();
    return;
}

#
# ---------------------------------------------------------
#
sub printheader {
    print <<'EOT';
<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 3.2//EN">
<html>
<head>
<title>Multigate</title>
</head>
<body bgcolor="#AAAAAA">
<dl>
<dd><br>
<table border="1" cellpadding="2">
<tr>
<form><input type="hidden" name="action" value="showallusers">
<td align="center">
<input type="submit" value="Show All Users">
</td></form>
<form><input type="hidden" name="action" value="showallaliases">
<td align="center">
<input type="submit" value="Show All Aliases">
</td></form>
<form><input type="hidden" name="action" value="showalladdresses">
<td align="center">
<input type="submit" value="Show All Addresses">
</td></form>
</tr>
</table>
<br>
<hr>
<br>
EOT

    return;
}

#
# ---------------------------------------------------------
#
sub printfooter {
    print <<'EOT';
</dd>
</dl>
</body>
</html>
EOT

    return;
}

#
# ---------------------------------------------------------
#
sub getprotocols {
    my $prot = $dbh->selectcol_arrayref( <<'EOT');
SELECT
  protocol
FROM
  protocol
EOT
    return @$prot;
}

#
# ---------------------------------------------------------
#
sub salt {
    my @saltset = ( 0 .. 9, 'A' .. 'Z', 'a' .. 'z', '.', '/' );
    return join '', @saltset[ rand @saltset, rand @saltset ];
}

if ( defined $dbh ) {
    $dbh->disconnect;
}


#MP2 (there should be a standard function somewhere!)
sub escape_html {
        my $str = shift;

        $str =~ s/&/&amp;/g;
        $str =~ s/</&lt;/g;
        $str =~ s/>/&gt;/g;

        return $str;
}


1;    # You never know...
