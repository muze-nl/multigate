#
#   ICQ2000.pm
#   Version 1.00
#
#   This module is designed to give perl scripts access to the ICQ network and
#   the functions provided by it, like SMS
#
#   Written by Robin Fisher <robin@phase3solutions.com>  UIN 24340914
#   Some parts/ideas were borrowes from Jeremy Muhlich, Luke Petre and anyone else
#       who contributed to Net::ICQ
#   
#   Thanks to Markus Kern for his help with decoding the 0x0c TLV (still not complete)
#
#   Thanks to Keith Kelley and Keith Pitcher for their work on : White Pages Searches
#                                                                Normal Out going messages
#                                                                User Info Details requests
#                                                                A few other odds and ends :)
#
#   This module is provided AS IS, and I don't take any responsibility for anything u
#   do with it, or if u kill your system with it (I've no idea how u would, but I still
#   take no responsibility.) This doesn't mean you can't contact me for help, but I
#   do expect you to have a basic grasp of the Perl Lang, and I WON'T be providing
#   any other kind of support.
#
#   If you change this file, please let me know, so if it's something I haven't though
#   of or written in, I can add it, and credit will be given to you.
#   
#   PS As with all my scripts, and especially ones still under development, I take
#   no responsibility for the spelling in anyway.. : )
#
#   PPS please only contact me via ICQ if u are really having problems (otherwise
#   please use my E-mail addressa above) and if you REALLY want to add me to your ICQ
#   contact list, please mention the script in the request, or I won't know who you
#   are and there's a 99% chance I'll ignore your request (my list is getting far too
#   Long... :)
#
#######################################################################################

package ICQ2000;

use strict;
no strict 'refs';
use vars qw(
  $VERSION
  %_Login_Decoder
  %_TLV_OUT %_TLV_IN %_TLV_Length_O %_TLV_Length_I %_Srv_Codes
  %_Srv_Decoder %_Cmd_Codes %_Cmd_Encoder
  %_Status_Codes
);

use Time::Local;
use IO::Socket;
use IO::Select;
use Carp;

$VERSION = '0.2.1';

sub new {
    my ( $Package, $UIN, $Password, $AutoConnect, $ServerAddress, $ServerPort ) = @_;

    $ServerAddress or $ServerAddress = "login.icq.com";
    $ServerPort    or $ServerPort    = "5190";

    my $Me = {
        _UIN              => $UIN,
        _Password         => $Password,
        _Server           => $ServerAddress,
        _ServerPort       => $ServerPort,
        _Socket           => undef,
        _Select           => undef,
        _Seq_Num          => int( rand(0xFFFF) ),
        _Incoming_Queue   => [],
        _Outgoing_Queue   => [],
        _Hooks            => {},
        _Connected        => 0,
        _FLAP_Bytes_Left  => 0,
        _FLAP_In_progress => undef,
        _Mem              => 1,
        _Sent_Requests    => {},
        _Debug            => 0
    };

    bless( $Me, $Package );

    return $Me;
}

sub Connect {
    my ($Me) = @_;

    return ( 1, "Connection Already Established" ) if $Me->{_Connected};

    $Me->{_UIN}      or return ( 1, "Attempted to connect without UIN!" );
    $Me->{_Password} or return ( 1, "Attempted to connect without Password!" );

    $Me->{_Socket} = IO::Socket::INET->new(
        Proto    => "tcp",
        PeerAddr => $Me->{_Server},
        PeerPort => $Me->{_ServerPort}
      )
      or croak("socket error: $@");

    $Me->{_Select}    = IO::Select->new( $Me->{_Socket} );
    $Me->{_Connected} = 1;
    return (0);
}

sub Disconnect {
    my ($Me) = @_;

    $Me->{_Connected} or return ( 1, "No Connection" );

    close( $Me->{_Socket} );
    $Me->{_Select}         = undef;
    $Me->{_Connected}      = 0;
    $Me->{_Incoming_Queue} = [];
    $Me->{_Outgoing_Queue} = [];

    return (0);
}

sub Set_Login_Details {
    my ( $Me, $UIN, $Pass ) = @_;

    return ( 1, "Already Connected" ) if $Me->{_Connected};

    $Me->{_UIN}      = $UIN  if $UIN;
    $Me->{_Password} = $Pass if $Pass;
    return (0);
}

sub Set_Server_And_Port {
    my ( $Me, $ServerAndPort ) = @_;

    return ( 1, "Already Connected" ) if $Me->{_Connected};
    $ServerAndPort or return ( 1, "No Server and Port Given" );

    ( $Me->{_Server}, $Me->{_ServerPort} ) = split ( /:/, $ServerAndPort );

    $Me->{_Server} or return ( 1, "Server Change Failed" );
    $Me->{_UIN}    or return ( 1, "Port Change Failed" );

    return (0);
}

sub Execute_Once {
    my ( $Me, $Under_Object ) = @_;
    my ( $ErrID, $ErrMsg );

    $Me->{_Connected} or return ( 1, "No Connection" );

    ( $ErrID, $ErrMsg ) = $Me->Check_Incoming;
    return ( $ErrID, $ErrMsg ) if $ErrID;

    ( $ErrID, $ErrMsg ) = $Me->Deal_With_FLAPs($Under_Object);
    return ( $ErrID, $ErrMsg ) if $ErrID;

    ( $ErrID, $ErrMsg ) = $Me->Send_Outgoing;
    return ( $ErrID, $ErrMsg );
}

sub Send_Command {
    my ( $Me, $Command, $Details ) = @_;

    $Me->{_Connected} or return ( 1, "No Connection" );
    ( exists $_Cmd_Codes{$Command} ) or return ( 1, "Command Not Found" );

    &{ $_Cmd_Encoder{ $_Cmd_Codes{$Command} } } ( $Me, $Details )
      if ( exists $_Cmd_Encoder{ $_Cmd_Codes{$Command} } );
    return (0);
}

sub Add_Hook {
    my ( $Me, $HookType, $HookFunction ) = @_;

    $_Srv_Codes{$HookType} or return ( 1, "Bad Hook type!\n" );

    $Me->{_Hooks}{ $_Srv_Codes{$HookType} } = $HookFunction;
    return (0);
}

#sub to run on ALL functions (run before selective hooks..
sub Hook_All {
    my ( $Me, $HookFunction ) = @_;

    $Me->{_Hook_All} = $HookFunction;
    return (0);
}

%_Status_Codes = (
    'Online'         => 0x00020000,
    'Free_For_Chat'  => 0x00020020,
    'Away'           => 0x00020001,
    'Not_Avalible'   => 0x00020005,
    'Occupied'       => 0x00020011,
    'Do_Not_Disturb' => 0x00020013,
    'Invisable'      => 0x00020100
);

%_Cmd_Encoder = (

    #Cmd_Log_Client_Login
    '1:0:0' => sub {
        my ( $Me, $event ) = @_;
        my ($Responce);

        $Responce->{Channel_ID} = 1;
        @{ $Responce->{Data_Load} } = _int_to_bytes( 4, 1 );

        foreach ( keys %{ $event->{TVLs} } ) {
            push ( @{ $Responce->{Data_Load} }, _Write_TLV( 1, $_, $event->{TVLs}{$_} ) );
        }

        push ( @{ $Me->{_Outgoing_Queue} }, $Responce );

    },

    #Cmd_GSC_Client_Ready
    '2:1:2' => sub {
        my ( $Me, $event ) = @_;
        my ($Responce);

        @{ $Responce->{Data_Load} } = &_Make_SNAC_Header( 1, 2, 0, 0, 2 );

        push ( @{ $Responce->{Data_Load} }, _int_to_bytes( 2, 1 ) );
        push ( @{ $Responce->{Data_Load} }, _int_to_bytes( 2, 3 ) );
        push ( @{ $Responce->{Data_Load} }, _int_to_bytes( 2, 0x0110 ) );
        push ( @{ $Responce->{Data_Load} }, _int_to_bytes( 2, 0x028a ) );
        push ( @{ $Responce->{Data_Load} }, _int_to_bytes( 2, 2 ) );
        push ( @{ $Responce->{Data_Load} }, _int_to_bytes( 2, 1 ) );
        push ( @{ $Responce->{Data_Load} }, _int_to_bytes( 2, 0x0101 ) );
        push ( @{ $Responce->{Data_Load} }, _int_to_bytes( 2, 0x028a ) );
        push ( @{ $Responce->{Data_Load} }, _int_to_bytes( 2, 3 ) );
        push ( @{ $Responce->{Data_Load} }, _int_to_bytes( 2, 1 ) );
        push ( @{ $Responce->{Data_Load} }, _int_to_bytes( 2, 0x0110 ) );
        push ( @{ $Responce->{Data_Load} }, _int_to_bytes( 2, 0x028a ) );
        push ( @{ $Responce->{Data_Load} }, _int_to_bytes( 2, 0x15 ) );
        push ( @{ $Responce->{Data_Load} }, _int_to_bytes( 2, 1 ) );
        push ( @{ $Responce->{Data_Load} }, _int_to_bytes( 2, 0x0110 ) );
        push ( @{ $Responce->{Data_Load} }, _int_to_bytes( 2, 0x028a ) );
        push ( @{ $Responce->{Data_Load} }, _int_to_bytes( 2, 4 ) );
        push ( @{ $Responce->{Data_Load} }, _int_to_bytes( 2, 1 ) );
        push ( @{ $Responce->{Data_Load} }, _int_to_bytes( 2, 0x0110 ) );
        push ( @{ $Responce->{Data_Load} }, _int_to_bytes( 2, 0x028a ) );
        push ( @{ $Responce->{Data_Load} }, _int_to_bytes( 2, 6 ) );
        push ( @{ $Responce->{Data_Load} }, _int_to_bytes( 2, 1 ) );
        push ( @{ $Responce->{Data_Load} }, _int_to_bytes( 2, 0x0110 ) );
        push ( @{ $Responce->{Data_Load} }, _int_to_bytes( 2, 0x028a ) );
        push ( @{ $Responce->{Data_Load} }, _int_to_bytes( 2, 9 ) );
        push ( @{ $Responce->{Data_Load} }, _int_to_bytes( 2, 1 ) );
        push ( @{ $Responce->{Data_Load} }, _int_to_bytes( 2, 0x0110 ) );
        push ( @{ $Responce->{Data_Load} }, _int_to_bytes( 2, 0x028a ) );
        push ( @{ $Responce->{Data_Load} }, _int_to_bytes( 2, 0x0a ) );
        push ( @{ $Responce->{Data_Load} }, _int_to_bytes( 2, 1 ) );
        push ( @{ $Responce->{Data_Load} }, _int_to_bytes( 2, 0x0110 ) );
        push ( @{ $Responce->{Data_Load} }, _int_to_bytes( 2, 0x028a ) );

        push ( @{ $Me->{_Outgoing_Queue} }, $Responce );

    },

    #Cmd_GSC_Reqest_Rate_Info
    '2:1:6' => sub {
        my ( $Me, $event ) = @_;
        my ($Responce);

        @{ $Responce->{Data_Load} } = &_Make_SNAC_Header( 1, 6, 0, 0, 6 );
        push ( @{ $Me->{_Outgoing_Queue} }, $Responce );
    },

    #Cmd_GSC_Rate_Info_Ack
    '2:1:8' => sub {
        my ( $Me, $event ) = @_;
        my ($Responce);

        @{ $Responce->{Data_Load} } = &_Make_SNAC_Header( 1, 8, 0, 0, 8 );

        #another junk filled responce (AOL must like using up network resources..)
        push ( @{ $Responce->{Data_Load} }, ( 0, 1, 0, 2, 0, 3, 0, 4, 0, 5 ) );

        push ( @{ $Me->{_Outgoing_Queue} }, $Responce );
    },

    #Cmd_GSC_LoggedIn_User_Info
    '2:1:14' => sub {
        my ( $Me, $event ) = @_;
        my ($Responce);

        @{ $Responce->{Data_Load} } = &_Make_SNAC_Header( 1, 14, 0, 0, 14 );

        push ( @{ $Me->{_Outgoing_Queue} }, $Responce );
    },

    #Cmd_GSC_ICQInform
    '2:1:23' => sub {
        my ( $Me, $event ) = @_;
        my ($Responce);

        #Never changes..
        @{ $Responce->{Data_Load} } = &_Make_SNAC_Header( 1, 0x17, 0, 0, 0x17 );
        push ( @{ $Responce->{Data_Load} },
            ( 0, 1, 0, 3, 0, 2, 0, 1, 0, 3, 0, 1, 0, 21, 0, 1, 0, 4, 0, 1, 0, 6, 0, 1, 0, 9, 0, 1, 0, 10, 0, 1 ) );
        push ( @{ $Me->{_Outgoing_Queue} }, $Responce );
    },

    #Cmd_GSC_Set_Status
    '2:1:30' => sub {
        my ( $Me, $event ) = @_;
        my ( $Responce, $Responce2 );

        @{ $Responce->{Data_Load} } = &_Make_SNAC_Header( 1, 30, 0, 0, 30 );

        push ( @{ $Responce->{Data_Load} }, _Write_TLV( 2, 'Status', $_Status_Codes{ $event->{Status} } ) );

        push ( @{ $Me->{_Outgoing_Queue} }, $Responce );

        #send the "Made Change/update command" (really I don't know whta this is for..)
        @{ $Responce2->{Data_Load} } = &_Make_SNAC_Header( 1, 17, 0, 0, 17 );
        push ( @{ $Responce2->{Data_Load} }, _int_to_bytes( 4, 0 ) );

        push ( @{ $Me->{_Outgoing_Queue} }, $Responce2 );
    },

    #Cmd_LS_LoggedIn_User_Rights
    '2:2:2' => sub {
        my ( $Me, $event ) = @_;
        my ($Responce);

        @{ $Responce->{Data_Load} } = &_Make_SNAC_Header( 2, 2, 0, 0, 2 );

        push ( @{ $Me->{_Outgoing_Queue} }, $Responce );
    },

    #Cmd_LS_Set_User_Info
    '2:2:4' => sub {
        my ( $Me, $event ) = @_;
        my ($Responce);
        @{ $Responce->{Data_Load} } = &_Make_SNAC_Header( 2, 4, 0, 0, 4 );

        #if this is setting our details, shouldn't we set something? maybe later.. : )

        push ( @{ $Responce->{Data_Load} }, _int_to_bytes( 2, 5 ) );
        push ( @{ $Responce->{Data_Load} }, _int_to_bytes( 2, 32 ) );

        foreach (
            0x09, 0x46, 0x13, 0x49, 0x4c, 0x7f, 0x11, 0xd1, 0x82, 0x22, 0x44, 0x45, 0x53, 0x54, 0x00, 0x00,
            0x09, 0x46, 0x13, 0x44, 0x4c, 0x7f, 0x11, 0xd1, 0x82, 0x22, 0x44, 0x45, 0x53, 0x54, 0x00, 0x00
          )
        {
            push ( @{ $Responce->{Data_Load} }, _int_to_bytes( 1, $_ ) );

        }

        push ( @{ $Me->{_Outgoing_Queue} }, $Responce );
    },

    #Cmd_BLM_Rights_Info
    '2:3:2' => sub {
        my ( $Me, $event ) = @_;
        my ($Responce);

        @{ $Responce->{Data_Load} } = &_Make_SNAC_Header( 3, 2, 0, 0, 2 );

        push ( @{ $Me->{_Outgoing_Queue} }, $Responce );
    },

    #Cmd_CTL_UploadList
    '2:3:4' => sub {
        my ( $Me, $event ) = @_;
        my ( $Responce, @ContactList );

        @{ $Responce->{Data_Load} } = &_Make_SNAC_Header( 3, 4, 0, 0, 4 );

        #don't send the command unless we have a list to send..
        foreach ( keys %{ $event->{ContactList} } ) {
            push ( @ContactList, $_ );
        }

        return ( 1, "No contacts to send" ) if ( $#ContactList == -1 );

        foreach (@ContactList) {
            push ( @{ $Responce->{Data_Load} }, _int_to_bytes( 1, length($_) ) );
            push ( @{ $Responce->{Data_Load} }, _str_to_bytes($_) );
        }
        push ( @{ $Me->{_Outgoing_Queue} }, $Responce );
    },

    #Cmd_Mes_Add_ICBM_Param
    '2:4:2' => sub {
        my ( $Me, $event ) = @_;
        my ($Responce);

        @{ $Responce->{Data_Load} } = &_Make_SNAC_Header( 4, 2, 0, 0, 2 );

        push ( @{ $Responce->{Data_Load} }, ( 0, 0, 0, 0, 0, 3, 0x1f, 0x40, 3, 0xe7, 3, 0xef, 0, 0, 0, 0 ) );
        push ( @{ $Me->{_Outgoing_Queue} }, $Responce );
    },

    #Cmd_Mes_Param_Info
    '2:4:4' => sub {
        my ( $Me, $event ) = @_;
        my ($Responce);

        @{ $Responce->{Data_Load} } = &_Make_SNAC_Header( 4, 4, 0, 0, 4 );

        push ( @{ $Me->{_Outgoing_Queue} }, $Responce );
    },

    #Cmd_Mes_Send
    '2:4:6' => sub {

        #Send a message to someone
        my ( $Me, $event ) = @_;
        my ( $Responce, @TempPacket );
        @{ $Responce->{Data_Load} } = &_Make_SNAC_Header( 4, 6, 0, 1, 6 );
        my $uin = $event->{uin};
        my $msg = $event->{text};
        my $len = length($msg) + 4;
        push ( @TempPacket, _int_to_bytes( 4, 0x52995d00 ) );
        push ( @TempPacket, _int_to_bytes( 4, 0x69230000 ) );
        push ( @TempPacket, _int_to_bytes( 2, 0x0001 ) );
        push ( @TempPacket, _uin_to_buin($uin) );
        push ( @TempPacket, _int_to_bytes( 2, 0x0002 ) );       # TLV
        push ( @TempPacket, _int_to_bytes( 2, $len + 9 ) );     # TLV
        push ( @TempPacket, _int_to_bytes( 3, 0x050100 ) );
        push ( @TempPacket, _int_to_bytes( 4, 0x01010101 ) );
        push ( @TempPacket, _int_to_bytes( 2, $len ) );
        push ( @TempPacket, _int_to_bytes( 2, 0 ) );
        push ( @TempPacket, _int_to_bytes( 2, 0xffff ) );
        push ( @TempPacket, _str_to_bytes($msg) );
        push ( @TempPacket, _int_to_bytes( 2, 0x0006 ) );
        push ( @TempPacket, _int_to_bytes( 2, 0x0000 ) );
        push ( @{ $Responce->{Data_Load} }, @TempPacket );
        push ( @{ $Me->{_Outgoing_Queue} }, $Responce );
    },

    #Cmd_BOS_Get_Rights
    '2:9:2' => sub {
        my ( $Me, $event ) = @_;
        my ($Responce);

        @{ $Responce->{Data_Load} } = &_Make_SNAC_Header( 9, 2, 0, 0, 2 );

        push ( @{ $Me->{_Outgoing_Queue} }, $Responce );
    },

    #Cmd_BOS_Add_VisableList
    '2:9:5' => sub {
        my ( $Me, $event ) = @_;
        my ($Responce);

        @{ $Responce->{Data_Load} } = &_Make_SNAC_Header( 9, 4, 0, 0, 5 );

        foreach ( @{ $event->{VisableList} } ) {
            push ( @{ $Responce->{Data_Load} }, _int_to_bytes( 1, length($_) ) );
            push ( @{ $Responce->{Data_Load} }, _str_to_bytes($_) );
        }
        push ( @{ $Me->{_Outgoing_Queue} }, $Responce );

    },

    #Cmd_Srv_Message
    '2:21:2' => sub {
        my ( $Me, $event ) = @_;
        my ( $Responce, @TempPacket );

        @{ $Responce->{Data_Load} } = &_Make_SNAC_Header( 0x15, 2, 0, 0, ( $Me->{_Mem} * 65536 + 0x02 ) );    #strainge request ID..
        $Me->{_Mem}++;

        push ( @{ $Responce->{Data_Load} }, _int_to_bytes( 2, 0x0001 ) );

        #Argh, Finally figured this bit out!!!
        #this next four packets is the length in little endian and normal!! so work
        #out the packet length first...

        push ( @TempPacket, _int_to_endian_bytes( 4, $Me->{_UIN} ) );    #encode the ICQ num..

        if ( $event->{MessageType} eq "" ) {

            push ( @TempPacket, _int_to_bytes( 2,        0x3c00 ) );
            push ( @TempPacket, _int_to_endian_bytes( 2, $Me->{_Mem} ) );
        } elsif ( $event->{MessageType} eq "User_Info_Request" ) {

            push ( @TempPacket, _int_to_bytes( 2,        0xd007 ) );
            push ( @TempPacket, _int_to_endian_bytes( 2, $Me->{_Mem} ) );
            push ( @TempPacket, _int_to_bytes( 2,        0xb204 ) );
            push ( @TempPacket, _int_to_endian_bytes( 4, $event->{TargetUIN} ) );    #encode the ICQ num..
        }

        #White Pages Request
        #Thanks Keith
        if ( $event->{MessageType} eq "WP_Full_Request" ) {
            push ( @TempPacket, _int_to_bytes( 2,        0xd007 ) );
            push ( @TempPacket, _int_to_endian_bytes( 2, $Me->{_Mem} ) );
            push ( @TempPacket, _int_to_bytes( 2,        0x3305 ) );

            #max 20 on everything unless noted
            #first
            push ( @TempPacket, _int_to_bytes( 1, length( $event->{_firstname} ) + 1 ) );
            push ( @TempPacket, _int_to_bytes( 1, 0x00 ) );
            push ( @TempPacket, _str_to_bytes( $event->{_firstname} ) );
            push ( @TempPacket, _int_to_bytes( 1, 0x00 ) );

            #last
            push ( @TempPacket, _int_to_bytes( 1, length( $event->{_lastname} ) + 1 ) );
            push ( @TempPacket, _int_to_bytes( 1, 0x00 ) );
            push ( @TempPacket, _str_to_bytes( $event->{_lastname} ) );
            push ( @TempPacket, _int_to_bytes( 1, 0x00 ) );

            #nick            
            push ( @TempPacket, _int_to_bytes( 1, length( $event->{_nickname} ) + 1 ) );
            push ( @TempPacket, _int_to_bytes( 1, 0x00 ) );
            push ( @TempPacket, _str_to_bytes( $event->{_nickname} ) );
            push ( @TempPacket, _int_to_bytes( 1, 0x00 ) );

            #email (max 25)
            push ( @TempPacket, _int_to_bytes( 1, length( $event->{_email} ) + 1 ) );
            push ( @TempPacket, _int_to_bytes( 1, 0x00 ) );
            push ( @TempPacket, _str_to_bytes( $event->{_email} ) );
            push ( @TempPacket, _int_to_bytes( 1, 0x00 ) );

            #Min age
            push ( @TempPacket, _int_to_bytes( 1, $event->{_min_age} ) );
            push ( @TempPacket, _int_to_bytes( 1, 0x00 ) );

            #Max age
            push ( @TempPacket, _int_to_bytes( 1, $event->{_max_age} ) );
            push ( @TempPacket, _int_to_bytes( 1, 0x00 ) );

            #Sex (0,1,2)
            push ( @TempPacket, _int_to_bytes( 1, $event->{_sex} ) );

            #Language (0...see table)
            push ( @TempPacket, _int_to_bytes( 1, $event->{_language} ) );

            #city
            push ( @TempPacket, _int_to_bytes( 1, length( $event->{_city} ) + 1 ) );
            push ( @TempPacket, _int_to_bytes( 1, 0x00 ) );
            push ( @TempPacket, _str_to_bytes( $event->{_city} ) );
            push ( @TempPacket, _int_to_bytes( 1, 0x00 ) );

            #state (max 3)
            push ( @TempPacket, _int_to_bytes( 1, length( $event->{_state} ) + 1 ) );
            push ( @TempPacket, _int_to_bytes( 1, 0x00 ) );
            push ( @TempPacket, _str_to_bytes( $event->{_state} ) );
            push ( @TempPacket, _int_to_bytes( 1, 0x00 ) );

            #country (see table)
            push ( @TempPacket, _int_to_bytes( 1, $event->{_country} ) );
            push ( @TempPacket, _int_to_bytes( 1, 0x00 ) );

            #company-name
            push ( @TempPacket, _int_to_bytes( 1, length( $event->{_company_name} ) + 1 ) );
            push ( @TempPacket, _int_to_bytes( 1, 0x00 ) );
            push ( @TempPacket, _str_to_bytes( $event->{_company_name} ) );
            push ( @TempPacket, _int_to_bytes( 1, 0x00 ) );

            #company-department
            push ( @TempPacket, _int_to_bytes( 1, length( $event->{_company_dep} ) + 1 ) );
            push ( @TempPacket, _int_to_bytes( 1, 0x00 ) );
            push ( @TempPacket, _str_to_bytes( $event->{_company_dep} ) );
            push ( @TempPacket, _int_to_bytes( 1, 0x00 ) );

            #company-position
            push ( @TempPacket, _int_to_bytes( 1, length( $event->{_company_pos} ) + 1 ) );
            push ( @TempPacket, _int_to_bytes( 1, 0x00 ) );
            push ( @TempPacket, _str_to_bytes( $event->{_company_pos} ) );
            push ( @TempPacket, _int_to_bytes( 1, 0x00 ) );

            #company-occupation 
            push ( @TempPacket, _int_to_bytes( 1, $event->{_company_occ} ) );

            #past information category
            push ( @TempPacket, _int_to_bytes( 2, $event->{_past_info_cat} ) );

            #past information
            push ( @TempPacket, _int_to_bytes( 1, length( $event->{_past_info_desc} ) + 1 ) );
            push ( @TempPacket, _int_to_bytes( 1, 0x00 ) );
            push ( @TempPacket, _str_to_bytes( $event->{_past_info_desc} ) );
            push ( @TempPacket, _int_to_bytes( 1, 0x00 ) );

            #interests category (see table)
            push ( @TempPacket, _int_to_bytes( 1, $event->{_interests_cat} ) );
            push ( @TempPacket, _int_to_bytes( 1, 0x00 ) );

            #interests specific - comma, delim
            push ( @TempPacket, _int_to_bytes( 1, length( $event->{_interests_desc} ) + 1 ) );
            push ( @TempPacket, _int_to_bytes( 1, 0x00 ) );
            push ( @TempPacket, _str_to_bytes( $event->{_interests_desc} ) );
            push ( @TempPacket, _int_to_bytes( 1, 0x00 ) );

            #organization 
            push ( @TempPacket, _int_to_bytes( 1, $event->{_org_cat} ) );
            push ( @TempPacket, _int_to_bytes( 1, 0x00 ) );

            #organization specific - comma, delim
            push ( @TempPacket, _int_to_bytes( 1, length( $event->{_org_desc} ) + 1 ) );
            push ( @TempPacket, _int_to_bytes( 1, 0x00 ) );
            push ( @TempPacket, _str_to_bytes( $event->{_org_desc} ) );
            push ( @TempPacket, _int_to_bytes( 1, 0x00 ) );

            #homepage category 
            push ( @TempPacket, _int_to_bytes( 2, $event->{_homepage_cat} ) );

            #homepage 
            push ( @TempPacket, _int_to_bytes( 1, length( $event->{_homepage} ) + 1 ) );
            push ( @TempPacket, _int_to_bytes( 1, 0x00 ) );
            push ( @TempPacket, _str_to_bytes( $event->{_homepage} ) );
            push ( @TempPacket, _int_to_bytes( 1, 0x00 ) );

            #Only online users (0 or 1)
            push ( @TempPacket, _int_to_bytes( 1, $event->{_online_only} ) );

            #ICQ header
        } elsif ( $event->{MessageType} eq "Ack_Offline_Message" ) {
            push ( @TempPacket, _int_to_bytes( 2, 0x3e00 ) );
            push ( @TempPacket, _int_to_bytes( 1, $Me->{_Mem} ) );
            push ( @TempPacket, _int_to_bytes( 1, 0 ) );
        } elsif ( $event->{MessageType} eq "key" ) {
            $Me->{_Sent_Requests}{ ( ( $Me->{_Mem} - 1 ) * 65536 + 0x02 ) } = $event->{Key};

            push ( @TempPacket, _int_to_bytes( 2, 0xd007 ) );
            push ( @TempPacket, _int_to_bytes( 1, $Me->{_Mem} ) );

            push ( @TempPacket, _int_to_bytes( 3, 0x9808 ) );

            my $Key = "<key>" . $event->{Key} . "</key>";

            push ( @TempPacket, _int_to_endian_bytes( 2, length($Key) + 1 ) );
            push ( @TempPacket, _str_to_bytes($Key) );
            push ( @TempPacket, _int_to_bytes( 1,        0 ) );
        } elsif ( $event->{MessageType} eq "SMS" ) {
            push ( @TempPacket, _int_to_bytes( 2, 0xd007 ) );
            push ( @TempPacket, _int_to_bytes( 1, $Me->{_Mem} ) );

            push ( @TempPacket, _int_to_bytes( 4,  0x00821400 ) );
            push ( @TempPacket, _int_to_bytes( 4,  0x01001600 ) );
            push ( @TempPacket, _int_to_bytes( 17, 0 ) );

            my $TimeString = gmtime();
            if ( $TimeString =~ /(\w+) (\w+)  ?(\d+) (\d+:\d+:\d+) (\d+)/ ) {
                $TimeString = $1 . ", " . $3 . " " . $2 . " " . $5 . " " . $4 . " GMT";
            } else {
                print "Unable to encode time...[$TimeString]\n";
                return;
            }
            unless ( $event->{delivery_receipt} eq "Yes" ) {
                $event->{delivery_receipt} = "No";
            }
            $event->{senders_name} or ( $event->{senders_name} = "Robbot" );

            my $SMSMessage =
              "<icq_sms_message><destination>" . $event->{SMS_Dest_Number} . "</destination><text>" . $event->{text} . "</text>";
            $SMSMessage .= "<codepage>1252</codepage><senders_UIN>"
              . $Me->{_UIN}
              . "</senders_UIN><senders_name>"
              . $event->{senders_name}
              . "</senders_name>";
            $SMSMessage .=
              "<delivery_receipt>" . $event->{delivery_receipt} . "</delivery_receipt><time>$TimeString</time></icq_sms_message>";

            my $SMSLength = length($SMSMessage) + 1;

            push ( @TempPacket, _int_to_bytes( 2, $SMSLength ) );

            push ( @TempPacket, _str_to_bytes($SMSMessage) );
            push ( @TempPacket, _int_to_bytes( 1, 0 ) );    #null end..
        }

        #NOW work out that length thingy (what a crappy place for it!!!)
        push ( @{ $Responce->{Data_Load} }, _int_to_bytes( 2,        $#TempPacket + 3 ) );
        push ( @{ $Responce->{Data_Load} }, _int_to_endian_bytes( 2, $#TempPacket + 1 ) );
        push ( @{ $Responce->{Data_Load} }, @TempPacket );

        push ( @{ $Me->{_Outgoing_Queue} }, $Responce );
    }
);

%_Srv_Decoder = (

    #Srv_Lgi_Connected
    '1:0:1' => sub {
        my ( $Me, $event ) = @_;

        #non..
    },

    #Srv_GSC_Ready
    '2:1:3' => sub {
        my ( $Me, $event ) = @_;

        #nothing intresting to get from SNAC..

        return;
    },

    #Srv_GSC_Rate_Info
    "2:1:7" => sub {
        my ( $Me, $event ) = @_;

        #my ($Refined);

        #Loads of data, but I have no idea what to do with it.. 
        #(tells us all the posible commands?..)
        return ($event);
    },

    #Srv_GSC_User_Info
    '2:1:15' => sub {
        my ( $Me, $event ) = @_;
        my ( $Refined, $i, $DataLength );

        #$event->{Data_Load}

        $i = 10;

        $DataLength = ${ $event->{Data_Load} }[$i];

        $i++;
        $Refined->{Online_User} = _bytes_to_str( $event->{Data_Load}, $i, $DataLength );
        $i += $DataLength;
        $Refined->{Warning_Lev} = _bytes_to_int( $event->{Data_Load}, $i, 2 );
        $i += 4;

        ( $Refined, $i ) = &_Read_TLV( $event->{Data_Load}, 2, $i, $Refined );
        return ($Refined);
    },

    #Srv_GSC_MOTD
    '2:1:19' => sub {
        my ( $Me, $event ) = @_;
        my ( $Refined, $i );

        $i = 12;

        ( $Refined, $i ) = &_Read_TLV( $event->{Data_Load}, 2, $i, $Refined );
        return ($Refined);
    },

    #Srv_GSC_ICQClientConfirm
    '2:1:24' => sub {
        my ( $Me, $event ) = @_;
        my ($Refined);

        #$event->{Data_Load}

        return ($Refined);
    },

    #Srv_LS_Rights_Response
    '2:2:3' => sub {
        my ( $Me, $event ) = @_;
        my ($Refined);

        #no idea what to do with this data..
        #$event->{Data_Load}
        return ($Refined);
    },

    #Srv_BLM_Rights_Response
    '2:3:3' => sub {
        my ( $Me, $event ) = @_;
        my ($Refined);

        #no idea what to do with this data.. 
        #$event->{Data_Load}
        return ($Refined);
    },

    #Srv_BLM_Contact_Online
    '2:3:11' => sub {
        my ( $Me, $event ) = @_;
        my ( $Refined, $DataLength, $i );

        $i          = 10;
        $DataLength = ${ $event->{Data_Load} }[$i];
        $i++;

        $Refined->{UIN} = _bytes_to_str( $event->{Data_Load}, $i, $DataLength );
        $i += $DataLength + 4;

        ( $Refined, $i ) = _Read_TLV( $event->{Data_Load}, 2, $i, $Refined, _bytes_to_int( $event->{Data_Load}, $i - 4, 4 ) );

        #Partial Decoding of the LAN_Network_Details TLV value
        # provided by Markus Kern
        if ( $Refined->{LAN_Network_Details} ) {
            my (@U2raw) = _str_to_bytes( $Refined->{LAN_Network_Details} );
            $Refined->{LAN_IP} =
              _bytes_to_int( \@U2raw, 0, 1 ) . "."
              . _bytes_to_int( \@U2raw, 1, 1 ) . "."
              . _bytes_to_int( \@U2raw, 2, 1 ) . "."
              . _bytes_to_int( \@U2raw, 3, 1 );
            $Refined->{LAN_Port} = _bytes_to_int( \@U2raw, 4, 2 );
        }

        return ($Refined);
    },

    #Srv_BLM_Contact_Offline
    '2:3:12' => sub {
        my ( $Me, $event ) = @_;
        my ( $Refined, $DataLength, $i );

        $i          = 10;
        $DataLength = ${ $event->{Data_Load} }[$i];
        $i++;

        $Refined->{UIN} = _bytes_to_str( $event->{Data_Load}, $i, $DataLength );
        $i += $DataLength + 4;

        ( $Refined, $i ) = _Read_TLV( $event->{Data_Load}, 2, $i, $Refined, _bytes_to_int( $event->{Data_Load}, $i - 4, 4 ) );

        return ($Refined);
    },

    #Srv_Mes_Rights_Response
    '2:4:5' => sub {
        my ( $Me, $event ) = @_;
        my ($Refined);

        #no idea what to do with this data.. 
        #$event->{Data_Load}
        return ($Refined);
    },

    #Srv_Mes_Received
    '2:4:7' => sub {
        my ( $Me, $event ) = @_;
        my ( $Refined, $i, $DataLength, $DataType );

        $i = 19;

        $Refined->{SenderType} = $event->{Data_Load}->[$i];
        $i++;

        $DataLength = ${ $event->{Data_Load} }[$i];
        $i++;

        $Refined->{Sender} = _bytes_to_str( $event->{Data_Load}, $i, $DataLength );
        $i += $DataLength + 4;

        ( $Refined, $i ) = _Read_TLV( $event->{Data_Load}, 2, $i, $Refined, _bytes_to_int( $event->{Data_Load}, $i - 4, 4 ) );

        if ( $Refined->{Encoded_Message} ) {

            #this is a weird ass message, so decode it..
            my @Encoded_Message = split ( / /, $Refined->{Encoded_Message} );
            undef $Refined->{Encoded_Message};

            $Refined->{TaggedDataString} =
              _bytes_to_str( \@Encoded_Message, 0x32, _endian_bytes_to_int( \@Encoded_Message, 0x2f, 2 ) );

            $Refined = _Decode_Tagged_Text( $Refined->{TaggedDataString}, $Refined );

            return ($Refined);
        }
        $Refined->{Message_Encoding} = _bytes_to_int( $event->{Data_Load}, $i, 2 );
        $i += 2;

        if ( $Refined->{SenderType} == 1 ) {

            #normal text message..
            $Refined->{MessageType} = "Normal_Message";

            #Look at the spec to try to figure out what's missing here.
            $i += 10;
            $Refined->{BytesToCount} = _bytes_to_int( $event->{Data_Load}, $i, 2 );
            $i += 2;

            #Now some DWORD
            $i += 3;
            $Refined->{Text} = _bytes_to_str( $event->{Data_Load}, $i, $Refined->{BytesToCount} );
            $i += $Refined->{BytesToCount};
        } elsif ( $Refined->{Message_Encoding} == 5 ) {
            $DataLength = _bytes_to_int( $event->{Data_Load}, $i, 2 );
        }

        return ($Refined);
    },

    #Srv_BOS_Rights
    '2:9:3' => sub {
        my ( $Me, $event ) = @_;
        my ($Refined);

        #$event->{Data_Load}
        return ($Refined);
    },

    #Srv_Srv_Message
    '2:21:3' => sub {
        my ( $Me, $event ) = @_;
        my ( $Refined, $i );

        ################
        ##### NOTE #####
        ################
        #This Srv responce seems to be the one that AOL desided to hack ALL ICQ functions that
        # they couldn't fit under the normal AIM protocol. This means that this family
        # seems to ave a lot of sub sub sub families, and hence is a bastard to decode,
        # and then when u think u've got it, one call out of 900000 screws up in the decoding
        # so if anyone has some good insights into this family please let me know!!!!

        $Refined->{Flags} = _bytes_to_int( $event->{Data_Load}, 4, 2 );
        $Refined->{Ref}   = _bytes_to_int( $event->{Data_Load}, 6, 4 );

        if ( exists $Me->{_Sent_Requests}{ $Refined->{Ref} } ) {
            $Refined->{Responce_Type} = $Me->{_Sent_Requests}{ $Refined->{Ref} };
            undef $Me->{_Sent_Requests}{ $Refined->{Ref} };
        }

        #first ten is SNAC header, then a 00 01 (normally..) then the message's size in 
        #Normal then endian format (don't have any idea why, but it is..) but skip all that..
        $i = 16;
        $Refined->{Our_UIN} = _endian_bytes_to_int( $event->{Data_Load}, $i, 4 );
        $i += 4;

        #the first of the sub sub types..
        $Refined->{MessageType} = _endian_bytes_to_int( $event->{Data_Load}, $i, 2 );
        $i += 2;

        if ( $Refined->{MessageType} == 65 ) {
            $Refined->{MessageType} = "Offline_Message";

            # normally offline messages..
            if ( _endian_bytes_to_int( $event->{Data_Load}, $i, 2 ) == 2 ) {

                #90% sure it's an offline message..
                $i += 2;
                $Refined->{Senders_UIN} = _endian_bytes_to_int( $event->{Data_Load}, $i, 4 );
                $i += 4;

                #note, the time given is in GMT, not local, so make it local..(DIE AOL!!!)
                $Refined->{Sent_Time} = localtime(
                  timegm(
                      0,
                      _endian_bytes_to_int( $event->{Data_Load}, $i + 5, 1 ),
                      _endian_bytes_to_int( $event->{Data_Load}, $i + 4, 1 ),
                      _endian_bytes_to_int( $event->{Data_Load}, $i + 3, 1 ),
                      _endian_bytes_to_int( $event->{Data_Load}, $i + 2, 1 ) - 1,
                      _endian_bytes_to_int( $event->{Data_Load}, $i,     2 )
                  )
                );
                $i += 6;
                $Refined->{UnknownOFL} = _endian_bytes_to_int( $event->{Data_Load}, $i, 2 );

                $Refined->{Text} =
                  _bytes_to_str( $event->{Data_Load}, $i + 4, _endian_bytes_to_int( $event->{Data_Load}, $i + 2, 2 ) );
            } else {
                print "Argh, something Screwed up!!!";
                return;
            }
        } elsif ( $Refined->{MessageType} == 66 ) {
            if ( _endian_bytes_to_int( $event->{Data_Load}, $i, 2 ) == 2 ) {
                $Refined->{MessageType} = "Offline_Messages_Complete";

                #I'm guessing that's this is an "All offline messages sent" message..
            }
        } elsif ( $Refined->{MessageType} == 2010 ) {

            #Server messages stored in "html" style tags..
            $i += 2;

            $Refined->{SubMessageType} = _bytes_to_int( $event->{Data_Load}, $i, 3 );
            $i += 3;

            if ( $Refined->{SubMessageType} == 10618890 ) {

                #Ads stuff
                $Refined->{MessageType} = "Tagged_Srv_Responce";
                if ( _bytes_to_int( $event->{Data_Load}, $i, 2 ) == 41480 ) {

                    #short gap.. (this is a VERY bad way of doing this.. should fix..)
                    $i += 3;
                } else {

                    #don't know what these 11(?) bytes do..
                    $i += 11;
                }

                $Refined->{TaggedDataString} =
                  _bytes_to_str( $event->{Data_Load}, $i + 2, _bytes_to_int( $event->{Data_Load}, $i, 2 ) );
                $Refined = _Decode_Tagged_Text( $Refined->{TaggedDataString}, $Refined );
            } elsif ( $Refined->{SubMessageType} == 10748170 ) {

                #Info Request return)
                my ($BytesToCount);
                $Refined->{MessageType} = "WP_result_info";

                #Unknown word
                $i += 2;
                $Refined->{UIN} = _endian_bytes_to_int( $event->{Data_Load}, $i, 4 );
                $i += 4;
                $BytesToCount = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 2;
                $Refined->{Nickname} = _bytes_to_str( $event->{Data_Load}, $i, $BytesToCount - 1 );
                $i += $BytesToCount;
                $BytesToCount = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 2;
                $Refined->{Firstname} = _bytes_to_str( $event->{Data_Load}, $i, $BytesToCount - 1 );
                $i += $BytesToCount;
                $BytesToCount = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 2;
                $Refined->{Lastname} = _bytes_to_str( $event->{Data_Load}, $i, $BytesToCount - 1 );
                $i += $BytesToCount;
                $BytesToCount = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 2;
                $Refined->{Email} = _bytes_to_str( $event->{Data_Load}, $i, $BytesToCount - 1 );
                $i += $BytesToCount;
                $Refined->{Auth_Required} = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 1;
                $Refined->{Status} = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 1;

                #always ends with a 00
            } elsif ( $Refined->{SubMessageType} == 10748210 || $Refined->{SubMessageType} == 11403570 ) {
                $Refined->{MessageType} = "WP_Empty";

                #Empty White Page Result

            } elsif ( $Refined->{SubMessageType} == 11403530 ) {
                my ($BytesToCount);
                $Refined->{MessageType} = "WP_final_result_info";

                #Unknown word
                $i += 2;
                $Refined->{UIN} = _endian_bytes_to_int( $event->{Data_Load}, $i, 4 );
                $i += 4;
                $BytesToCount = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 2;
                $Refined->{Nickname} = _bytes_to_str( $event->{Data_Load}, $i, $BytesToCount - 1 );
                $i += $BytesToCount;
                $BytesToCount = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 2;
                $Refined->{Firstname} = _bytes_to_str( $event->{Data_Load}, $i, $BytesToCount - 1 );
                $i += $BytesToCount;
                $BytesToCount = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 2;
                $Refined->{Lastname} = _bytes_to_str( $event->{Data_Load}, $i, $BytesToCount - 1 );
                $i += $BytesToCount;
                $BytesToCount = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 2;
                $Refined->{Email} = _bytes_to_str( $event->{Data_Load}, $i, $BytesToCount - 1 );
                $i += $BytesToCount;
                $Refined->{Auth_Required} = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 1;
                $Refined->{Status} = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 1;

                #Some weird 3 bytes are thrown in - perhaps
                #a counter for total unreturned results?
                #always ends with 00 
            }

            elsif ( $Refined->{SubMessageType} == 13107210 ) {
                my ($BytesToCount);
                $Refined->{MessageType} = "User_Info_Main";

                #This isn't really correcy, since it's endian data and not normal, but
                # this will only be shown if any name etc is longer then 255 chars..
                $BytesToCount = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 2;
                $Refined->{Nickname} = _bytes_to_str( $event->{Data_Load}, $i, $BytesToCount - 1 );
                $i += $BytesToCount;
                $BytesToCount = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 2;
                $Refined->{Firstname} = _bytes_to_str( $event->{Data_Load}, $i, $BytesToCount - 1 );
                $i += $BytesToCount;
                $BytesToCount = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 2;
                $Refined->{Lastname} = _bytes_to_str( $event->{Data_Load}, $i, $BytesToCount - 1 );
                $i += $BytesToCount;
                $BytesToCount = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 2;
                $Refined->{Email} = _bytes_to_str( $event->{Data_Load}, $i, $BytesToCount - 1 );
                $i += $BytesToCount;
                $BytesToCount = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 2;
                $Refined->{City} = _bytes_to_str( $event->{Data_Load}, $i, $BytesToCount - 1 );
                $i += $BytesToCount;
                $BytesToCount = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 2;
                $Refined->{State} = _bytes_to_str( $event->{Data_Load}, $i, $BytesToCount - 1 );
                $i += $BytesToCount;
                $BytesToCount = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 2;
                $Refined->{Telephone} = _bytes_to_str( $event->{Data_Load}, $i, $BytesToCount - 1 );
                $i += $BytesToCount;
                $BytesToCount = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 2;
                $Refined->{Fax_Num} = _bytes_to_str( $event->{Data_Load}, $i, $BytesToCount - 1 );
                $i += $BytesToCount;
                $BytesToCount = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 2;
                $Refined->{Address} = _bytes_to_str( $event->{Data_Load}, $i, $BytesToCount - 1 );
                $i += $BytesToCount;
                $BytesToCount = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 2;
                $Refined->{Mobile_Phone} = _bytes_to_str( $event->{Data_Load}, $i, $BytesToCount - 1 );
                $i += $BytesToCount;
                $BytesToCount = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 2;
                $Refined->{Zip} = _bytes_to_str( $event->{Data_Load}, $i, $BytesToCount - 1 );
                $i += $BytesToCount;
                $Refined->{Country} = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 2;
                $Refined->{GMT_Code} = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 2;

            } elsif ( $Refined->{SubMessageType} == 15400970 ) {
                my ( $BytesToCount, $Extra_Email_Count );
                $Refined->{MessageType} = "User_Info_Extra_Emails";

                $Extra_Email_Count = $Refined->{Extra_Email_Count} = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 2;

                #Grab all the extra E-mails, and place them into an array..
                while ( $Extra_Email_Count > 0 ) {
                    $BytesToCount = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                    $i += 2;
                    push ( @{ $Refined->{Extra_Emails} }, _bytes_to_str( $event->{Data_Load}, $i, $BytesToCount - 1 ) );
                    $i += $BytesToCount + 1;
                    $Extra_Email_Count--;
                }

            } elsif ( $Refined->{SubMessageType} == 14417930 ) {
                my ($BytesToCount);
                $Refined->{MessageType} = "User_Info_homepage";

                #one of the 0 bytes may be the homepage category, but who cares about that
                $Refined->{Age} = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 2;
                $Refined->{Sex} = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 1;
                $BytesToCount = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 2;
                $Refined->{Homepage} = _bytes_to_str( $event->{Data_Load}, $i, $BytesToCount - 1 );
                $i += $BytesToCount;
                $Refined->{Birth_Year} = _endian_bytes_to_int( $event->{Data_Load}, $i, 2 );
                $i += 2;
                $Refined->{Birth_Month} = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 1;
                $Refined->{Birth_Day} = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 1;
                $Refined->{Language1} = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 1;
                $Refined->{Language2} = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 1;
                $Refined->{Language3} = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 1;

            } elsif ( $Refined->{SubMessageType} == 13762570 ) {
                my ($BytesToCount);
                $Refined->{MessageType} = "User_Info_Work";

                #work DC000A
                $BytesToCount = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 2;
                $Refined->{Company_City} = _bytes_to_str( $event->{Data_Load}, $i, $BytesToCount - 1 );
                $i += $BytesToCount;
                $BytesToCount = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 2;
                $Refined->{Company_State} = _bytes_to_str( $event->{Data_Load}, $i, $BytesToCount - 1 );
                $i += $BytesToCount;

                #odd 6 bytes, 2 sets of 01 00 00, almost like 2 sets of dwords that are empty
                $i += 6;
                $BytesToCount = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 2;
                $Refined->{Company_Address} = _bytes_to_str( $event->{Data_Load}, $i, $BytesToCount - 1 );
                $i += $BytesToCount;
                $BytesToCount = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 2;
                $Refined->{Company_Zip} = _bytes_to_str( $event->{Data_Load}, $i, $BytesToCount - 1 );
                $i += $BytesToCount;
                $Refined->{Company_Country} = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 2;
                $BytesToCount = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 2;
                $Refined->{Company_Name} = _bytes_to_str( $event->{Data_Load}, $i, $BytesToCount - 1 );
                $i += $BytesToCount;
                $BytesToCount = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 2;
                $Refined->{Company_Department} = _bytes_to_str( $event->{Data_Load}, $i, $BytesToCount - 1 );
                $i += $BytesToCount;
                $BytesToCount = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 2;
                $Refined->{Company_Position} = _bytes_to_str( $event->{Data_Load}, $i, $BytesToCount - 1 );
                $i += $BytesToCount;
                $Refined->{Company_Occupation} = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 2;
                $BytesToCount = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 2;
                $Refined->{Company_URL} = _bytes_to_str( $event->{Data_Load}, $i, $BytesToCount - 1 );
                $i += $BytesToCount;

            } elsif ( $Refined->{SubMessageType} == 15073290 ) {

                #about)
                my ($BytesToCount);
                $Refined->{MessageType} = "User_Info_About";
                $BytesToCount = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 2;
                $Refined->{about} = _bytes_to_str( $event->{Data_Load}, $i, $BytesToCount - 1 );
                $i += $BytesToCount;
            } elsif ( $Refined->{SubMessageType} == 15728650 ) {

                #Personal Interests)
                my ( $BytesToCount, $Int_Count );
                $Refined->{MessageType} = "User_Info_Personal_Interests";

                $Int_Count = $Refined->{Interests_Count} = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 1;

                while ( $Int_Count > 0 ) {
                    $Int_Count--;

                    push ( @{ $Refined->{Interests_Type} }, _bytes_to_int( $event->{Data_Load}, $i, 2 ) );
                    $i += 2;
                    $BytesToCount = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                    $i += 2;
                    push ( @{ $Refined->{Interests_Desc} }, _bytes_to_str( $event->{Data_Load}, $i, $BytesToCount - 1 ) );
                    $i += $BytesToCount;
                }

            } elsif ( $Refined->{SubMessageType} == 16384010 ) {

                #Past Interests Info)
                $Refined->{MessageType} = "User_Info_Past_Background";
                $Refined->{_background_count} = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 1;
                if ( $Refined->{_background_count} > 0 ) {
                    $Refined->{_background_category1} = _bytes_to_int( $event->{Data_Load}, $i, 2 );
                    $i += 2;
                    $Refined->{BytesToCount} = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                    $i += 2;
                    $Refined->{_background_description1} = _bytes_to_str( $event->{Data_Load}, $i, $Refined->{BytesToCount} - 1 );
                    $i += $Refined->{BytesToCount};
                }
                if ( $Refined->{_background_count} > 1 ) {
                    $Refined->{_background_category2} = _bytes_to_int( $event->{Data_Load}, $i, 2 );
                    $i += 2;
                    $Refined->{BytesToCount} = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                    $i += 2;
                    $Refined->{_background_description2} = _bytes_to_str( $event->{Data_Load}, $i, $Refined->{BytesToCount} - 1 );
                    $i += $Refined->{BytesToCount};
                }
                if ( $Refined->{_background_count} > 2 ) {
                    $Refined->{_background_category3} = _bytes_to_int( $event->{Data_Load}, $i, 2 );
                    $i += 2;
                    $Refined->{BytesToCount} = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                    $i += 2;
                    $Refined->{_background_description3} = _bytes_to_str( $event->{Data_Load}, $i, $Refined->{BytesToCount} - 1 );
                    $i += $Refined->{BytesToCount};
                }
                $Refined->{_organization_count} = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                $i += 1;
                if ( $Refined->{_organization_count} > 0 ) {
                    $Refined->{_organization_category1} = _bytes_to_int( $event->{Data_Load}, $i, 2 );
                    $i += 2;
                    $Refined->{BytesToCount} = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                    $i += 2;
                    $Refined->{_organization_description1} = _bytes_to_str( $event->{Data_Load}, $i, $Refined->{BytesToCount} - 1 );
                    $i += $Refined->{BytesToCount};
                }
                if ( $Refined->{_organization_count} > 1 ) {
                    $Refined->{_organization_category2} = _bytes_to_int( $event->{Data_Load}, $i, 2 );
                    $i += 2;
                    $Refined->{BytesToCount} = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                    $i += 2;
                    $Refined->{_organization_description2} = _bytes_to_str( $event->{Data_Load}, $i, $Refined->{BytesToCount} - 1 );
                    $i += $Refined->{BytesToCount};
                }
                if ( $Refined->{_organization_count} > 2 ) {
                    $Refined->{_organization_category3} = _bytes_to_int( $event->{Data_Load}, $i, 2 );
                    $i += 2;
                    $Refined->{BytesToCount} = _bytes_to_int( $event->{Data_Load}, $i, 1 );
                    $i += 2;
                    $Refined->{_organization_description3} = _bytes_to_str( $event->{Data_Load}, $i, $Refined->{BytesToCount} - 1 );
                    $i += $Refined->{BytesToCount};
                }
            }

        }

        return ($Refined);
    },

    #Srv_Disconnect_Command
    '4:0:0' => sub {
        my ( $Me, $event ) = @_;
        my ( $Refined, $i );

        ( $Refined, $i ) = &_Read_TLV( $event->{Data_Load}, 4 );

        return ($Refined);
    },
);

%_Cmd_Codes = (
    Cmd_Log_Client_Login => "1:0:0",

    Cmd_GSC_Client_Ready        => "2:1:2",
    Cmd_GSC_Reqest_Rate_Info    => "2:1:6",
    Cmd_GSC_Rate_Info_Ack       => "2:1:8",
    Cmd_GSC_LoggedIn_User_Info  => "2:1:14",
    Cmd_GSC_ICQInform           => "2:1:23",
    Cmd_GSC_Set_Status          => "2:1:30",
    Cmd_LS_LoggedIn_User_Rights => "2:2:2",
    Cmd_LS_Set_User_Info        => "2:2:4",
    Cmd_BLM_Rights_Info         => "2:3:2",
    Cmd_CTL_UploadList          => "2:3:4",
    Cmd_Mes_Add_ICBM_Param      => "2:4:2",
    Cmd_Mes_Param_Info          => "2:4:4",
    Cmd_Mes_Send                => "2:4:6",
    Cmd_BOS_Get_Rights          => "2:9:2",
    Cmd_BOS_Add_VisableList     => "2:9:5",
    Cmd_BOS_Add_InVisableList   => "2:9:7",
    Cmd_Srv_Message             => "2:21:2"
);

%_Srv_Codes = (
    Srv_Lgi_Connected => "1:0:0",

    Srv_GSC_Error            => "2:1:1",
    Srv_GSC_Ready            => "2:1:3",
    Srv_GSC_Redirect         => "2:1:5",
    Srv_GSC_Rate_Info        => "2:1:7",
    Srv_GSC_Rate_Change      => "2:1:10",
    Srv_GSC_User_Info        => "2:1:15",
    Srv_GSC_MOTD             => "2:1:19",
    Srv_GSC_ICQClientConfirm => "2:1:24",
    Srv_LS_Rights_Response   => "2:2:3",
    Srv_BLM_Rights_Response  => "2:3:3",
    Srv_BLM_Contact_Online   => "2:3:11",
    Srv_BLM_Contact_Offline  => "2:3:12",
    Srv_Mes_Rights_Response  => "2:4:5",
    Srv_Mes_Received         => "2:4:7",
    Srv_BOS_Rights           => "2:9:3",
    Srv_Srv_Message          => "2:21:3",

    Srv_Disconnect_Command => "4:0:0"
);

sub Check_Incoming {
    my ($Me) = @_;
    my ( $RawPacket, @Packet );

    while ( IO::Select->select( $Me->{_Select}, undef, undef, .00001 ) ) {
        $Me->{_Socket}->recv( $RawPacket, 10000 );

        if ( !$RawPacket ) {
            $Me->Disconnect;
            return ( 1, "Connection Lost" );
        }

        @Packet = split ( //, $RawPacket );

        foreach (@Packet) {
            $_ = ord;
        }

        my $PLength = @Packet;

        #decode the packet into FLAPs
        for ( my $i = 0 ; $i < $PLength ; $i++ ) {

            if ( $Me->{_FLAP_Bytes_Left} > 0 ) {
                push ( @{ $Me->{_FLAP_In_progress}{Data_Load} }, $Packet[$i] );

                $Me->{_FLAP_Bytes_Left}--;

                if ( $Me->{_FLAP_Bytes_Left} <= 0 ) {

                    #end the FLAP, and move it to the Queue..
                    push ( @{ $Me->{_Incoming_Queue} }, $Me->{_FLAP_In_progress} );
                    $Me->{_FLAP_In_progress} = undef;
                    $Me->{_FLAP_Bytes_Left}  = 0;
                }
                next;
            }

            #it's a new FLAP..
            $Packet[$i] == 42 or croak("Recieved Data Missaligned!");

            foreach ( $i .. $i + 5 ) {
                push ( @{ $Me->{_FLAP_In_progress}{Header} }, $Packet[$_] );
            }
            $Me->{_FLAP_In_progress}{Channel_ID}  = _bytes_to_int( \@Packet, $i + 1, 1 );
            $Me->{_FLAP_In_progress}{Sequence_ID} = _bytes_to_int( \@Packet, $i + 2, 2 );
            $Me->{_FLAP_In_progress}{Data_Size} = $Me->{_FLAP_Bytes_Left} = _bytes_to_int( \@Packet, $i + 4, 2 );
            $Me->{_FLAP_In_progress}{Family_ID} = _bytes_to_int( \@Packet, $i + 6, 2 );
            $Me->{_FLAP_In_progress}{Sub_ID}    = _bytes_to_int( \@Packet, $i + 8, 2 );

            $i += 5;
        }
    }
    return (0);
}

sub Deal_With_FLAPs {
    my ( $Me, $Under_Object ) = @_;

    foreach ( @{ $Me->{_Incoming_Queue} } ) {

        if ( $Me->{_Debug} ) {
            print "Incomming..\n";
            _print_packet( $_->{Header}, $_->{Data_Load} );

            #print "[".$_->{Channel_ID}."][".$_->{Sequence_ID}."][".$_->{Data_Size}."][".$_->{Family_ID}."][".$_->{Sub_ID}."]\n";
        }

        my $ID = $_->{Channel_ID} . ":" . $_->{Family_ID} . ":" . $_->{Sub_ID};
        $ID = "1:0:0" if ( $_->{Channel_ID} == 1 );
        $ID = "4:0:0" if ( $_->{Channel_ID} == 4 );

        my ($Refined);
        $Refined = &{ $_Srv_Decoder{$ID} } ( $Me, $_ )
          if ( exists $_Srv_Decoder{$ID} );

        if ( exists $Me->{_Hook_All} ) {
            &{ $Me->{_Hook_All} } ( $Under_Object, $_->{Channel_ID}, $ID, $Refined );
        }

        if ( exists $Me->{_Hooks}{$ID} ) {
            &{ $Me->{_Hooks}{$ID} } ( $Me, $Refined );
        }
    }
    $Me->{_Incoming_Queue} = [];
    return (0);
}

sub Send_Outgoing {
    my ($Me) = @_;
    my ( $Chan, $Data_Size, @Header, $Raw_Data );

    foreach ( @{ $Me->{_Outgoing_Queue} } ) {

        if ( $_->{Channel_ID} ) { $Chan = $_->{Channel_ID}; }
        else { $Chan = 2; }
        $Data_Size = @{ $_->{Data_Load} };

        @Header = ( 42, $Chan );

        $Me->{_Seq_Num}++;
        $Me->{_Seq_Num} = 0 if $Me->{_Seq_Num} > 65535;

        push ( @Header, _int_to_bytes( 2, $Me->{_Seq_Num} ) );
        push ( @Header, _int_to_bytes( 2, $Data_Size ) );

        foreach (@Header) {
            $Raw_Data .= chr($_);
        }
        foreach ( @{ $_->{Data_Load} } ) {
            $Raw_Data .= chr($_);
        }

        print "Outgoing..\n" if $Me->{_Debug};
        _print_packet( \@Header, \@{ $_->{Data_Load} } ) if $Me->{_Debug};
    }

    #send them all off..
    if ($Raw_Data) {
        $Me->{_Socket}->send($Raw_Data);
    }

    $Me->{_Outgoing_Queue} = [];
    return (0);
}

#########################
### Private functions ###
#########################

#These functions should only ever be run from within the ICQ object..

# _bytes_to_int(array_ref, start, bytes)
#
# Converts the byte array referenced by <array_ref>, starting at offset
# <start> and running for <bytes> values, into an integer, and returns it.
# The bytes in the array must be in little-endian order.
#
# _bytes_to_int([0x34, 0x12, 0xAA, 0xBB], 0, 2) == 0x1234
# _bytes_to_int([0x34, 0x12, 0xAA, 0xBB], 2, 1) == 0xAA

sub _endian_bytes_to_int {
    my ( $array, $start, $bytes ) = @_;
    my ($ret);

    $ret = 0;
    for ( my $i = $start + $bytes - 1 ; $i >= $start ; $i-- ) {
        $ret <<= 8;
        $ret |= ( $array->[$i] or 0 );
    }

    return $ret;
}

sub _bytes_to_int {
    my ( $array, $start, $bytes ) = @_;
    my ($ret);

    $ret = 0;
    for ( my $i = $start ; $i < $start + $bytes ; $i++ ) {
        $ret <<= 8;
        $ret |= ( $array->[$i] or 0 );
    }

    return $ret;
}

# _int_to_endian_bytes(bytes, val)
#
# Converts <val> into an array of <bytes> bytes and returns it.
# If <val> is too big, only the <bytes> least significant bytes are
# returned.  The array is in little-endian order.
#
# _int_to_bytes(2, 0x1234)  == (0x34, 0x12)
# _int_to_bytes(2, 0x12345) == (0x45, 0x23)

sub _int_to_endian_bytes {
    my ( $bytes, $val ) = @_;
    my (@ret);

    for ( my $i = 0 ; $i < $bytes ; $i++ ) {
        push @ret, ( $val >> ( $i * 8 ) & 0xFF );
    }

    return @ret;
}

# _int_to_bytes(bytes, val)
#
# Converts <val> into an array of <bytes> bytes and returns it.
# If <val> is too big, only the <bytes> least significant bytes are
# returned.  The array is not little-endian order.
#
# _int_to_bytes(2, 0x1234)  == (0x12, 0x34)
# _int_to_bytes(2, 0x12345) == (0x12, 0x34)

sub _int_to_bytes {
    my ( $bytes, $val ) = @_;
    my (@ret);

    for ( my $i = 0 ; $i < $bytes ; $i++ ) {
        unshift @ret, ( $val >> ( $i * 8 ) & 0xFF );
    }

    return @ret;
}

# _str_to_bytes(str, add_zero)
#
# Converts <str> into an array of bytes and returns it.  
#
# _str_to_bytes('foo')     == ('f', 'o', 'o')

sub _str_to_bytes {
    my ($string) = @_;
    my (@ret);

    # the ?: keeps split() from complaining about undefined values
    foreach ( split ( //, defined($string) ? $string : '' ) ) {
        push @ret, ord($_);
    }

    return @ret;
}

# _bytes_to_str(array_ref, start, bytes)
#
# Converts the byte array referenced by <array_ref>, starting at offset
# <start> and running for <bytes> values, into a string, and returns it.
#
# _bytes_to_str([0x12, 'f', 'o', 'o', '!'], 1, 3) == 'foo'

sub _bytes_to_str {

    # thanks to Dimitar Peikov for the fix
    my ( $array, $start, $bytes ) = @_;
    my ($ret);

    $ret = '';
    for ( my $i = $start ; $i < $start + $bytes ; $i++ ) {
        $ret .= $array->[$i] ? chr( $array->[$i] ) : '';
    }

    return $ret;
}

# print_packet(Header_packet_ref, Body_packet_ref)
#
# Dumps the ICQ packet contained in the byte array referenced by
# <packet_ref> to STDOUT. 
#
#   Format :
#            xx xx xx xx xx xx xx xx xx xx xx xx xx xx xx xx  abcdefghiklmnopq
#            xx xx xx xx xx xx xx xx xx xx xx xx xx xx xx xx  abcdefghiklmnopq

sub _print_packet {
    my ( $Header, $packet ) = @_;
    my ( $Counter, $TLine );

    foreach (@$Header) {
        $Counter++;

        print sprintf( "%02X ", $_ );

        if ( $_ >= 32 ) {
            $TLine .= chr($_);
        } else {
            $TLine .= ".";
        }

        if ( $Counter % 16 == 0 ) {
            print "  " . $TLine . "\n";
            $TLine = '';
        }
    }
    while ( $Counter > 16 ) { $Counter -= 16 }

    if ( 16 - $Counter > 1 && $Counter > 0 ) {
        foreach ( 1 .. ( 16 - $Counter ) ) {
            print "   ";
        }
        print "  " . $TLine . "\n";
    }
    $TLine   = '';
    $Counter = 0;

    foreach (@$packet) {
        $Counter++;

        print sprintf( "%02X ", $_ );

        if ( $_ >= 32 ) {
            $TLine .= chr($_);
        } else {
            $TLine .= ".";
        }

        if ( $Counter % 16 == 0 ) {
            print "  " . $TLine . "\n";
            $TLine = '';
        }
    }
    while ( $Counter > 16 ) { $Counter -= 16 }

    if ( 16 - $Counter > 1 && $Counter > 0 ) {
        foreach ( 1 .. ( 16 - $Counter ) ) {
            print "   ";
        }
        print "  " . $TLine . "\n";
    }
    print "\n";
}

# _uin_to_buin(str, add_zero)
#
# Converts <str> into an array of bytes and returns it.
#
# _str_to_bytes('foo')   == ('f', 'o', 'o')

sub _uin_to_buin {
    my ($uin) = @_;
    my (@ret);
    push @ret, length($uin);

    # the ?: keeps split() from complaining about undefined values
    foreach ( split ( //, defined($uin) ? $uin : '' ) ) {
        push @ret, ord($_);
    }
    return @ret;
}

# _Password_Encrypt(Password_String)
# Encrypts the password for sending to the server using a simple XOR "encryption" method
sub _Password_Encrypt {
    my ($Password) = @_;
    my ($FinishedString);

    my @Pass = split ( //, $Password );

    foreach (@Pass) {
        $_ = ord($_);
    }

    my @encoding_table = ( 0xf3, 0x26, 0x81, 0xc4, 0x39, 0x86, 0xdb, 0x92, 0x71, 0xa3, 0xb9, 0xe6, 0x53, 0x7a, 0x95, 0x7c );

    for ( my $i = 0 ; $i < length($Password) ; $i++ ) {
        $FinishedString .= chr( $Pass[$i] ^ $encoding_table[$i] );
    }

    return ($FinishedString);
}

# _Make_SNAC_Header(Comand_Family, Sub_Family, FlagA, FlagB, RequestID)
#makes the SNAC header which has to be at the top of every command..

sub _Make_SNAC_Header {
    my ( $Family, $Sub_Family, $FlagA, $FlagB, $RequestID ) = @_;

    my @Header = _int_to_bytes( 2, $Family );
    push ( @Header, _int_to_bytes( 2, $Sub_Family ) );
    push ( @Header, _int_to_bytes( 1, $FlagA ) );
    push ( @Header, _int_to_bytes( 1, $FlagB ) );
    push ( @Header, _int_to_bytes( 4, $RequestID ) );

    return @Header;
}

#this function takes a tagged string (like the server sends..) and breaks it up into
# it's parts...

sub _Decode_Tagged_Text {
    my ( $String, $Details ) = @_;
    my ( $Key, $Data, $i );

    while ( length($String) > 2 && $String =~ s/^[^<>]*<(\w+)>// ) {
        $Key = $1;
        if ( $String =~ s/^[^<>]*(<.+>.+<.+>)[^<>]*<\/$Key>// ) {
            $Details->{$Key} = _Decode_Tagged_Text( $1, $Details->{$Key} );
        } else {
            $String =~ s/^(.+)<\/$Key>//;
            $Details->{$Key} = $1;
        }
    }
    return ($Details);
}

#####################
### TLV functions ###
#####################

# TLV (Type, Length, Value) is the way much of the data is sent an recieved
# The Data below contains the definitions of the Types, their lengths, and what kind
# of data is to be expected (eg strings or ints etc..)
# Also has the _Write_TLV and _Read_TLV functions..

#definitions for the TLVs types being sent from the server..
#The first digit (2 or 4) denotes the FLAP's Chan
%_TLV_IN = (
    2 => {
        User_Class          => 0x01,    #!?????
        Signup_Date         => 0x02,    #! doesn't really work for ICQ, set to date of login, 1 sec before normal login date..
        SignOn_Date         => 0x03,    #!
        Port                => 0x04,    #! ?? This is mainly a guess..
        Encoded_Message     => 0x05,    #!
        Online_Status       => 0x06,    #!
        Ip_Address          => 0x0a,    #! in 4 byte format..
        Web_Address         => 0x0b,    #!
        LAN_Network_Details => 0x0c,    #! (long like 25 bytes..)
        Unknown03           => 0x0d,    #! ???
        Time_Online         => 0x0f     #!
    },
    4 => {
        UIN               => 0x01,    #!
        HTML_Address      => 0x04,    #!
        Server_And_Port   => 0x05,    #!
        Connection_Cookie => 0x06,    #!
        Error_Code        => 0x08,    #! 1 = Bad username, 2 = Turboing (eg logging in/out too often and too fast..) 5 = bad pass,
        Disconnect_Code   => 0x09,    #! 1 = Kicked due to second login of username.
        Unknown01         => 0x0c,    #!
    },

);

#definitions for the TLVs types being sent from us to the server..
#The first digit (1 or 2) denotes the FLAP's Chan
%_TLV_OUT = (
    1 => {
        UIN                => 0x01,    #!
        Password           => 0x02,    #!
        ClientProfile      => 0x03,    #!
        User_Info          => 0x05,
        Connection_Cookie  => 0x06,    #!
        CountryCode        => 0x0e,    #!
        Language           => 0x0f,    #!
        ClientBuildMinor   => 0x14,    #!
        ClientType         => 0x16,    #!
        ClientVersionMajor => 0x17,    #!
        ClientVersionMinor => 0x18,    #!
        ClientICQNumber    => 0x19,    #!
        ClientBuildMajor   => 0x1a     #!
    },
    2 => {
        Status    => 0x06,    #!
        Unknown00 => 0x08,    #!????
        Unknown01 => 0x0c,    #!????
        Unknown00 => 0x08,    #!????
    }
);

#if the TLV is a number, we define the number of bytes to use..(note all numbers are their decimal value, not hex)
# 1000 denotes a "raw" data input, and is encoded differently..
# 999 denotes a pasword and is encrypted..
%_TLV_Length_O = (
    1 => {
        2  => 999,
        6  => 1000,
        20 => 4,
        22 => 2,
        23 => 2,
        24 => 2,
        25 => 2,
        26 => 2
    },
    2 => {
        6 => 4,
        8 => 2,
    },
);

#This defines the type of data we expect comming in, the codes are as follows..
# 0 or no entry = String
# 1 = Int
# 2 = Raw (obtains the data still as a string of numbers seperated by spaces)
# 3 = IP

%_TLV_Length_I = (
    2 => {
        1  => 1,
        2  => 1,
        3  => 1,
        4  => 1,
        5  => 2,
        6  => 1,
        10 => 3,
        15 => 1,
    },
    4 => {
        8 => 1,
        6 => 2,
    },
);

# _Write_TLV(Message_Channel, Type_Value, Info_To_Encode)
#
# This creates an packet array ready for sending to the server, containing the given data

sub _Write_TLV {
    my ( $Chan, $Value, $Infomation ) = @_;
    my (@Data);

    $Value = $_TLV_OUT{$Chan}{$Value} if ( exists $_TLV_OUT{$Chan}{$Value} );

    @Data = _int_to_bytes( 2, $Value );

    my $TLV_Value_exists = exists $_TLV_Length_O{$Chan}{$Value};    #needed for quick fix :)

    if ( $TLV_Value_exists && ( $_TLV_Length_O{$Chan}{$Value} == 999 ) ) {
        push ( @Data, _int_to_bytes( 2, length($Infomation) ) );
        push ( @Data, _str_to_bytes( &_Password_Encrypt($Infomation) ) );
    } elsif ( $TLV_Value_exists && ( $_TLV_Length_O{$Chan}{$Value} == 1000 ) ) {

        #get it as an array!
        my @Cookie = split ( / /, $Infomation );
        my $CLength = @Cookie;
        push ( @Data, _int_to_bytes( 2, $CLength ) );
        push ( @Data, @Cookie );
    } elsif ($TLV_Value_exists) {

        #their a number, and need a set byte size..
        push ( @Data, _int_to_bytes( 2, $_TLV_Length_O{$Chan}{$Value} ) );
        push ( @Data, _int_to_bytes( $_TLV_Length_O{$Chan}{$Value}, $Infomation ) );
    } else {
        push ( @Data, _int_to_bytes( 2, length($Infomation) ) );
        push ( @Data, _str_to_bytes($Infomation) );
    }

    return (@Data);
}

# _Read_TLV(Array_to_Read, Message_Channel, Starting_offset_in_array, Array_for_results, Max_number_of_TLVs)
#
# This reads through an packet array picking out and decoding all the TLVs it can find,
# till it reaches the end of the array, or else reaches the Max_Num value (counted in TLVs not bytes..)
# It returns an Hash containing the found types/values and the final of set.

sub _Read_TLV {
    my ( $Array, $Chan, $Start, $Details, $Max ) = @_;
    my ( $i, $ArrayLength, $DataType, $DataLength, $DataTypeName );

    $ArrayLength = @$Array;

    $Start or $Start = 0;
    $Max   or $Max   = 100000;

    for ( $i = $Start ; $i < $ArrayLength ; ) {

        #only get up to the max number of TVLs
        $Max or last;
        $Max--;

        #read in the Data Type/length..
        $DataType = _bytes_to_int( $Array, $i, 2 );
        $DataLength = _bytes_to_int( $Array, $i + 2, 2 );
        $i += 4;

        #find the name of this data type..
        $DataTypeName = $DataType;
        foreach ( keys %{ $_TLV_IN{$Chan} } ) {
            $DataTypeName = $_ if ( $_TLV_IN{$Chan}{$_} == $DataType );
        }

        my $TLV_length_exists = exists $_TLV_Length_I{$Chan}{$DataType};    #quick fix

        if ( $TLV_length_exists && ( $_TLV_Length_I{$Chan}{$DataType} == 2 ) ) {

            #get it as an array!
            for ( my $p = 0 ; $p < $DataLength ; $p++ ) {
                $Details->{$DataTypeName} .= $Array->[ $i + $p ] . " ";
            }
            chop $Details->{$DataTypeName};
        } elsif ( $TLV_length_exists && ( $_TLV_Length_I{$Chan}{$DataType} == 3 ) ) {

            #get it as IP address
            if ( $DataLength != 4 ) {
                print "Argh, This an't an IP!!!\n";
            } else {
                $Details->{$DataTypeName} =
                  _bytes_to_int( $Array, $i, 1 ) . "."
                  . _bytes_to_int( $Array, $i + 1, 1 ) . "."
                  . _bytes_to_int( $Array, $i + 2, 1 ) . "."
                  . _bytes_to_int( $Array, $i + 3, 1 );
            }
        } elsif ( $TLV_length_exists && ( $_TLV_Length_I{$Chan}{$DataType} == 1 ) ) {

            #we're getting a number...
            $Details->{$DataTypeName} = _bytes_to_int( $Array, $i, $DataLength );
        } else {
            $Details->{$DataTypeName} = _bytes_to_str( $Array, $i, $DataLength );
        }
        $i += $DataLength;
    }
    return ( $Details, $i );
}

1;
