#!/usr/bin/perl -w

#
# multigate user edit module
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
    'edituserinfo'         => \&edituserinfo,
    'saveuserinfo'         => \&saveuserinfo,
    'changepassword'       => \&changepassword,
    'reallychangepassword' => \&reallychangepassword,
    'editaddress'          => \&editaddress,
    'saveaddress'          => \&saveaddress,
    'deleteaddress'        => \&deleteaddress,
    'reallydeleteaddress'  => \&reallydeleteaddress,
    'newaddress'           => \&newaddress,
    '_default_'            => \&showuser,
);

#MP1
#$r = Apache->request;
#$user = $r->connection->user;
#MP2
$r = Apache2::RequestUtil->request;
$req = Apache2::Request->new($r);
$r->content_type('text/html');
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
exit;

#
# ---------------------------------------------------------
#
sub showuser {
    my ( $irl, $bd, $bt, @prot, $addr, $opts );
    ( $irl, $bd, $bt ) = $dbh->selectrow_array( <<'EOT', {}, $user );
SELECT
  irl, birthday, birthtime
FROM
  user
WHERE
  username LIKE ?
EOT

    $irl = '*unkown*' unless $irl;
    $bd  = '*unkown*' unless $bd;
    $bt  = '*unkown*' unless $bt;

    $addr = $dbh->selectall_arrayref( <<'EOT', {}, $user );
SELECT
  protocol, address, main_address
FROM
  address
WHERE
  username LIKE ?
EOT

    printheader();
    print <<"EOT";

<h2>Lees dit eerst!</h2>

Een paar tips:<br><br>
<ul>
<li>Bij het protocol sms willen we het nummer ZONDER +316 hebben,
dus ook zonder 06, maar gewoon de laatste 8 cijfers.</li> 
<li>Bij irc willen we een hostmask hebben in de vorm: nick!user\@host, <b>zonder rare kringeltjes
enzo</b>. Ook (nog) zonder wildcards want die parsen we <i>nog</i> niet.</li>
<li>Het sms-nummer van multigate is: xxxxxx</li>
<li>Het icq-nummer van multigate is: xxxxxxx</li>
<li>Het msn-adres van multigate is: xxxxxx</li>
<li>Het jabber-adres van multigate is xxxxxx</li>
<li>Het email-adres van multigate is xxxxx (gebruik het subject voor je berichten!)</li>
<li>Het vinkje geeft aan of het je main-address is voor dat protocol. D.w.z.
daar komen je messages aan. Met andere adressen kun je je wel bekend
maken bij multigate, maar je kunt er niets op ontvangen. Er mag maar 1 adres per protocol 'main' zijn.</li>
<li>Op <b>adressen zonder vinkje</b> (dus niet main) kun je <b>geen berichten
</b>ontvangen van anderen!</li>
<li>Zet per protocol precies 1 adres op main.</li>
</ul>
<p>
In zo'n sms of icq kan dan als tekst staan:<br>
!weer<br>
!irc #chat hallo mensen, ik kan ook al multigaten.<br>
!icq titanhead !tv film<br>
<br>
Ofwel: !protocol ontvanger bericht  of<br>
!commando [argumenten], zoals !weer, !tt 108, !lhs ie hello world, etc.<br>
In een bericht kan dus ook een commando staan. Bovendien kunnen commando's
op elkaar gestapeld worden: !haxor !weer of !lhs eg !slashdot. 
<br>
Veel plezier!<br>
<p>
Ylebre, a6502  en Titanhead
<p>


<table border="1" cellpadding="2">
<tr>
<th colspan="3">User Info</th>
</tr>

<tr>
<th align="left">Username</th>
<td colspan="2">$user</td>
</tr>

<tr>
<th align="left">IRL</th>
<td colspan="2">$irl</td>
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
<th>&nbsp;</th>
<form><input type="hidden" name="action" value="edituserinfo"><td>
<input type="submit" value="Edit User Info">
</td></form>
<form><input type="hidden" name="action" value="changepassword"><td>
<input type="submit" value="Change Password">
</td></form>
</tr>
</table>
<br>
EOT

    my ( $aliases, $alias );

    $aliases = $dbh->selectcol_arrayref( <<'EOT', {}, $user );
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
<th>Aliases for user $user</th>
</tr>
<tr>
<td>$alias</td>
</tr>
</table>
EOT

    }
    else {
        print <<"EOT";
<table border="1" cellpadding="2">
<tr>
<th>No aliases defined for user $user</th>
</tr>
</table>
EOT

    }

    print <<"EOT";

<br>

<table border="1" cellpadding="2">
<tr>
<th colspan="5">Adresses</th>
</tr>

EOT

    foreach (@$addr) {
        my ( $prot, $addr, $prim ) = @$_;
        $prot = escape_html($prot);
        $addr = escape_html($addr);
        $prim = ( $prim eq 'true' ) ? 'main' : '&nbsp';
        print <<"EOT";
<tr>
<th align="left">$prot</th>
<td>$addr</td>
<td>$prim</td>
<form><input type="hidden" name="action" value="editaddress">
<input type="hidden" name="protocol" value="$prot">
<input type="hidden" name="address" value="$addr"><td align="center">
<input type="submit" value="Edit">
</td></form>
<form><input type="hidden" name="action" value="deleteaddress">
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
#
sub edituserinfo {

    my ( $ul, $irl, $bd, $bt, @prot, $addr, $opts );

    ( $irl, $ul, $bd, $bt ) = $dbh->selectrow_array( <<'EOT', {}, $user );
SELECT
  irl, level, birthday, birthtime
FROM
  user
WHERE
  username LIKE ?
EOT

    $irl = '*unkown*' unless $irl;
    $bd  = '*unkown*' unless $bd;
    $bt  = '*unkown*' unless $bt;

    printheader();
    print <<"EOT";


<table border="1" cellpadding="2">
<tr>
<th colspan="2">User Info</th>
</tr>

<form>
<input type="hidden" name="action" value="saveuserinfo">
<input type="hidden" name="username" value="$user">
<tr>
<th align="left">Username</th>
<td>$user</td>
</tr>

<tr>
<th align="left">Level</th>
<td>$ul</td>
</tr>

<tr>
<th align="left">IRL</th>
<td><input type="text" size="30" name="irl" value="$irl"></td>
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
    my ( $irl, $bd, $bt, $err, $res );
    $irl = $args{'irl'};
    $bd  = $args{'birthdate'};
    $bt  = $args{'birthtime'};

    $bd = undef unless $bd =~ /^\d\d\d\d-\d\d-\d\d$/;
    $bt = undef unless $bt =~ /^\d\d\:\d\d(:\d\d)?$/;

    $res = $dbh->do( <<'EOT', {}, $irl, $bd, $bt, $user );
UPDATE
  user
SET
  irl = ?,
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
<input type="submit" value="Back">
</form>
EOT

    return;
}

#
# ---------------------------------------------------------
#
sub changepassword {

    printheader();
    print <<"EOT";
<table border="1" cellpadding="2">
<tr>
<th colspan="2">Enter new password for user '$user'</th>
</tr><tr>
<form><input type="hidden" name="action" value="reallychangepassword">
<input type="hidden" name="username" value="$user"><td colspan="2">
<input type="password" size="32" name="password"></td>
</tr><tr>
<td align="center"><input type="Submit" value="Change Password"></td></form>
<form><input type="hidden" name="action" value="showuser"><td align="center">
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
    my ( $pw, $cpw );
    $pw = $args{'password'};

    $cpw = crypt( $pw, salt() );
    $dbh->do( <<'EOT', {}, $cpw, $user );
UPDATE
  user
SET
  password = ?
WHERE
  username like ?
EOT

    printheader();
    print <<"EOT";
Your password has been changed. The change will take effect after aprox. 10
minutes idle time on this site.
<br>
<br>
<form><input type="hidden" name="action" value="showuser">
<input type="submit" value="Back">
</form>
EOT

    printfooter();
    return;
}

#
# ---------------------------------------------------------
# Edit Address
#
sub editaddress {
    my ( $prot, $addr, $prim, $main );

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
<th colspan="3">Edit Address for user '$user'</th>
</tr><form><tr>
<input type="hidden" name="action" value="saveaddress">
<input type="hidden" name="protocol" value="$prot">
<input type="hidden" name="oldaddress" value="$addr">
<td>$prot</td>
<td><input type="text" size="55" name="address" value="$addr"></td>
<td align="center"><input type="checkbox" name="main"$main></td>
</tr><tr>
<td align="center"><input type="submit" value="Save"></td>
</form><form><td><input type="hidden" name="action" value="showuser">
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
sub saveaddress {
    my ( $prot, $addr, $oldaddr, $main, $err, $res );
    $prot    = $args{'protocol'};
    $addr    = $args{'address'};
    $oldaddr = $args{'oldaddress'};
    $main    = $args{'main'};

    if ( $main eq 'on' ) {
        $main = 'true';

        $res = $dbh->do( <<'EOT', {}, $user, $prot );
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

    $res = $dbh->do( <<'EOT', {}, $addr, $main, $user, $prot, $oldaddr );
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
<form><input type="hidden" name="action" value="showuser">
<input type="submit" value="Back">
</form>
EOT

    return;
}

#
# ---------------------------------------------------------
# Delete Address
#
sub deleteaddress {
    my ( $prot, $addr, $main, $err, $res );
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
<input type="hidden" name="protocol" value="$prot">
<input type="hidden" name="address" value="$addr">
<td align="center"><input type="submit" value="Ok"></td>
</form>
<form>
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
    my ( $prot, $addr, $main, $err, $res );
    $prot = $args{'protocol'};
    $addr = $args{'address'};

    $res = $dbh->do( <<'EOT', {}, $user, $prot, $addr );
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
sub newaddress {
    my ( $prot, $addr, $main, $err, $res );
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
<td>
<select name="protocol">
$opts
</select>
</td>
<td><input type="text" name="address" value= "$addr" size="55"></td>
<td align="center"><input type="checkbox" name="main"$main></td>
<td align="center"><input type="submit" value="New"></td>
</form>
<form>
<td align="center"><input type="submit" value="Cancel"></td>
</form>
</tr>
</table>
EOT

        printfooter();
        return;
    }

    $main = ( $main eq 'on' ) ? 'true' : 'false';

    $res = $dbh->do( <<'EOT', {}, $user, $prot, $addr, $main );
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
<tr><form>
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
