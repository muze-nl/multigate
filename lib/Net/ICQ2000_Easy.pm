#
#   ICQ2000_Easy.pm
#   Version 1.01
#
#   This module is designed to give Easier access to my ICQ2000.pm Package.
#
#   This is done by using the base package, but automatically handling a large number
#   of jobs, like logging in, and Contact list management.
#
#   Written by Robin Fisher <robin@phase3solutions.com>  UIN 24340914
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
#   Long... : )
#
#######################################################################################

package ICQ2000_Easy;

use lib './lib';

use Net::ICQ2000;
use strict;
no strict 'refs';
use vars qw(
  %lookup_occupation %lookup_sex %lookup_WP_status %_Status_Codes
  %lookup_language %lookup_country %lookup_pastbackground %lookup_organization %lookup_interest
);

# if AutoConnect is set higher then 1, a full login is made, but if set to one or less, only the 
# Nessesary login steps are taken. A value of Zero means that when the new object is constructed,
# it won't automaticly connect to the ICQ server, and instead u need to run the connect function.

sub new {
    my ( $Package, $UIN, $Password, $AutoConnect ) = @_;
    my ( $ErrID, $ErrMsg );

    my $Me = {
        _ICQ2000                   => undef,
        _UIN                       => $UIN,
        _Password                  => $Password,
        _Auto_Login                => $AutoConnect,
        _Contact_List              => {},
        _Connection_Cookie         => 0,
        _Sent_Requests             => {},
        _Status                    => "Online",
        _Auto_Ack_Offline_Messages => 0,
        _Error_Hook                => undef,
        _Debug                     => 0
    };

    bless( $Me, $Package );

    $Me->{_ICQ2000} = ICQ2000->new( $UIN, $Password );

    #register our major Hook..
    $Me->{_ICQ2000}->Hook_All( \&_Automatic_Functions );

    ( $ErrID, $ErrMsg ) = $Me->{_ICQ2000}->Connect() if $AutoConnect;

    return ($Me);
}

sub Connected {
    my ($Me) = @_;
    return ( $Me->{_ICQ2000}->{_Connected} );
}

sub Connect {
    my ( $Me, $UIN, $Pass ) = @_;
    my ( $ErrID, $ErrMsg );

    return ( 1, "Connection Already Established" )
      if $Me->{_ICQ2000}->{_Connected};

    $Me->{_UIN}      = $UIN  if $UIN;
    $Me->{_Password} = $Pass if $Pass;

    unless ( $Me->{_UIN} && $Me->{_Password} ) {
        return ( 1, "Attempted to connect without UIN/Pass" );
    }

    ( $ErrID, $ErrMsg ) = $Me->{_ICQ2000}->Set_Login_Details( $Me->{_UIN}, $Me->{_Password} );
    return ( $ErrID, $ErrMsg ) if $ErrID;

    ( $ErrID, $ErrMsg ) = $Me->{_ICQ2000}->Connect();
    return ( $ErrID, $ErrMsg );
}

sub Disconnect {
    my ($Me) = @_;
    my ( $ErrID, $ErrMsg );

    $Me->{_ICQ2000}->{_Connected} or return ( 1, "No Connection" );

    foreach ( keys %{ $Me->{_Contact_List} } ) {
        $Me->{_Contact_List}{$_}{Status}     = 0;
        $Me->{_Contact_List}{$_}{IP_Address} = undef;
    }

    ( $ErrID, $ErrMsg ) = $Me->{_ICQ2000}->Disconnect();
    return ( $ErrID, $ErrMsg );
}

sub Setup_Contact_List {
    my ( $Me, $ContactList ) = @_;

    $Me->{_Contact_List} = $ContactList;

    foreach ( keys %{ $Me->{_Contact_List} } ) {
        $Me->{_Contact_List}{$_}{Status}     = 0;
        $Me->{_Contact_List}{$_}{IP_Address} = undef;
    }
    return (0);
}

sub Auto_Ack_Offline_Messages {
    my ( $Me, $Setting ) = @_;
    $Me->{_Auto_Ack_Offline_Messages} = $Setting;
    return (0);
}

sub Execute_Once {
    my ($Me) = @_;
    my ( $ErrID, $ErrMsg );

    $Me->{_ICQ2000}->{_Connected} or return ( 1, "No Connection" );
    ( $ErrID, $ErrMsg ) = $Me->{_ICQ2000}->Execute_Once($Me);

    return ( $ErrID, $ErrMsg );
}

sub Send_Command {
    my ( $Me, $Command, $Details ) = @_;
    my ( $ErrID, $ErrMsg );

    ( $ErrID, $ErrMsg ) = $Me->{_ICQ2000}->Send_Command( $Command, $Details );
    return ( $ErrID, $ErrMsg );
}

sub Add_Hook {
    my ( $Me, $HookType, $HookFunction ) = @_;
    my ( $ErrID, $ErrMsg );

    ( $ErrID, $ErrMsg ) = $Me->{_ICQ2000}->Add_Hook( $HookType, $HookFunction );
    return ( $ErrID, $ErrMsg );
}

sub Add_Error_Hook {
    my ( $Me, $HookFunction ) = @_;

    $Me->{_Error_Hook} = $HookFunction;
    return (0);
}

sub Set_Debugging {
    my ( $Me, $DebugLev ) = @_;

    if ( $DebugLev & 1 ) {
        $Me->{_ICQ2000}->{_Debug} = 1;
    } else {
        $Me->{_ICQ2000}->{_Debug} = 0;
    }

    if ( $DebugLev & 2 ) {
        $Me->{_Debug} = 1;
    } else {
        $Me->{_Debug} = 0;
    }

    return (0);
}

#these are the functions that automaticly deal with some needed responces..
sub _Automatic_Functions {
    my ( $Me, $ChanID, $CommandID, $Details ) = @_;

    if ( $ChanID == 1 ) {

        #login FLAP..
        my ($Responce);

        if ( $Me->{_Connection_Cookie} ) {
            print "Sending Cookie\n" if ( $Me->{_Debug} );

            #Second time connected, so send the cookie..

            $Responce->{TVLs}{Connection_Cookie} = $Me->{_Connection_Cookie};

            $Me->Send_Command( "Cmd_Log_Client_Login", $Responce );

            #wipe the now used cookie (eat? :)
            $Me->{_Connection_Cookie} = 0;
            return;
        }

        #send the login details..

        $Responce->{TVLs}{UIN}                = $Me->{_UIN};
        $Responce->{TVLs}{Password}           = $Me->{_Password};
        $Responce->{TVLs}{ClientProfile}      = "ICQ Inc. - Product of ICQ (TM).2000b.4.63.1.3279.85";
        $Responce->{TVLs}{ClientType}         = 266;
        $Responce->{TVLs}{ClientVersionMajor} = 4;
        $Responce->{TVLs}{ClientVersionMinor} = 63;
        $Responce->{TVLs}{ClientICQNumber}    = 1;
        $Responce->{TVLs}{ClientBuildMajor}   = 3279;
        $Responce->{TVLs}{ClientBuildMinor}   = 85;
        $Responce->{TVLs}{Language}           = "en";
        $Responce->{TVLs}{CountryCode}        = "us";

        $Me->Send_Command( "Cmd_Log_Client_Login", $Responce );
        return;
    } elsif ( $ChanID == 4 ) {

        #Disconnect FLAP..

        #croak("Server got our UIN wrong!![".$Details->{UIN}."]") if ($Details->{UIN} != $Me->{_UIN});

        if ( $Details->{Connection_Cookie} && $Details->{Server_And_Port} ) {

            #we have logged in correctly and need to disconnect and reconnect..
            $Me->{_Connection_Cookie} = $Details->{Connection_Cookie};
            $Me->Disconnect();
            $Me->{_ICQ2000}->Set_Server_And_Port( $Details->{Server_And_Port} );
            $Me->Connect();
            return;
        }

        $Me->Disconnect();
        if ( exists $Me->{_Error_Hook} ) {
            my $Message;

            if ( $Details->{Error_Code} == 1 ) {
                $Message = "Bad Username";
            } elsif ( $Details->{Error_Code} == 2 ) {
                $Message = "Blocked due to Turboing";
            } elsif ( $Details->{Error_Code} == 5 ) {
                $Message = "Bad Password";
            } elsif ( $Details->{Error_Code} == 24 ) {
                $Message = "Rate limit exceeded.";
            }

            &{ $Me->{_Error_Hook} } ( $Me, $Details->{Error_Code}, $Message );
        }

    } elsif ( $CommandID eq "2:1:3" ) {
        $Me->Send_Command("Cmd_GSC_ICQInform");
    } elsif ( $CommandID eq "2:1:7" ) {
        if ( $Me->{_Auto_Login} > 1 ) {

            #ack the rate info..
            $Me->Send_Command("Cmd_GSC_Rate_Info_Ack");

            #also send some other requests..
            $Me->Send_Command("Cmd_GSC_LoggedIn_User_Info");
            $Me->Send_Command("Cmd_LS_LoggedIn_User_Rights");
            $Me->Send_Command("Cmd_BLM_Rights_Info");
            $Me->Send_Command("Cmd_Mes_Param_Info");
            $Me->Send_Command("Cmd_BOS_Get_Rights");
        }
    } elsif ( $CommandID eq "2:1:15" ) {
        $Details->{Status_Code} = ( $Details->{Online_Status} & 0xFFFF );
        $Details->{Status_Word} = $_Status_Codes{ $Details->{Status_Code} };
    } elsif ( $CommandID eq "2:1:24" ) {

        if ( $Me->{_Auto_Login} > 1 ) {
            $Me->Send_Command("Cmd_GSC_Reqest_Rate_Info");
        } else {
            my ($Responce);
            $Responce->{Status} = $Me->{_Status};
            $Me->Send_Command( "Cmd_GSC_Set_Status", $Responce );
            $Me->Send_Command("Cmd_GSC_Client_Ready");
        }
    } elsif ( $CommandID eq "2:3:11" ) {    #user online
            #Translate the Status details..

        $Details->{Status_Code} = ( $Details->{Online_Status} & 0xFFFF );
        $Details->{Status_Word} = $_Status_Codes{ $Details->{Status_Code} };

        $Me->{_Contact_List}{ $Details->{UIN} }{Status}     = $Details->{Status_Code};
        $Me->{_Contact_List}{ $Details->{UIN} }{IP_Address} = $Details->{Ip_Address};
        $Details->{Nick} = $Me->{_Contact_List}{ $Details->{UIN} }{NickName};
    } elsif ( $CommandID eq "2:3:12" ) {    #user Offline
        $Me->{_Contact_List}{ $Details->{UIN} }{Status}     = 0;
        $Me->{_Contact_List}{ $Details->{UIN} }{IP_Address} = undef;
        $Details->{Nick} = $Me->{_Contact_List}{ $Details->{UIN} }{NickName};
    } elsif ( $CommandID eq "2:9:3" ) {
        if ( $Me->{_Auto_Login} > 1 ) {
            $Me->Send_Command("Cmd_Mes_Add_ICBM_Param");
            $Me->Send_Command("Cmd_LS_Set_User_Info");

            #$Me->{_Contact_List}
            $Me->Send_Command( "Cmd_CTL_UploadList", { ContactList => $Me->{_Contact_List} } );

            #send the visible list..
            my (@VisibleList);
            foreach ( keys %{ $Me->{_Contact_List} } ) {
                if ( $Me->{_Contact_List}->{$_}->{Always_Visible} eq "Yes" ) {
                    push ( @VisibleList, $_ );
                }
            }
            $Me->Send_Command( "Cmd_BOS_Add_VisableList", { VisableList => @VisibleList } );

            $Me->Send_Command( "Cmd_GSC_Set_Status", { Status => $Me->{_Status} } );
            $Me->Send_Command("Cmd_GSC_Client_Ready");

            #now send all the Ad requests (hey, this is how the client does it.. : /
            $Me->Send_Command("Cmd_Srv_Message");
            $Me->Send_Command( "Cmd_Srv_Message", { MessageType => "key", Key => "DataFilesIP" } );
            $Me->Send_Command( "Cmd_Srv_Message", { MessageType => "key", Key => "BannersIP" } );
            $Me->Send_Command( "Cmd_Srv_Message", { MessageType => "key", Key => "ChannelsIP" } );
        }
    } elsif ( $CommandID eq "2:21:3" ) {
        if ( $Details->{MessageType} eq "Offline_Messages_Complete" && $Me->{_Auto_Ack_Offline_Messages} ) {
            $Me->Send_Command( "Cmd_Srv_Message", { MessageType => "Ack_Offline_Message" } );
        } elsif ( $Details->{MessageType} eq "User_Info_Main" ) {
            $Details->{Country} = $lookup_country{ $Details->{Country} };
        } elsif ( $Details->{MessageType} eq "User_Info_homepage" ) {
            $Details->{Language1} = $lookup_language{ $Details->{Language1} };
            $Details->{Language2} = $lookup_language{ $Details->{Language2} };
            $Details->{Language3} = $lookup_language{ $Details->{Language3} };
            $Details->{Sex}       = $lookup_sex{ $Details->{Sex} };

        } elsif ( $Details->{MessageType} eq "User_Info_Work" ) {
            $Details->{Company_Country}    = $lookup_country{ $Details->{Company_Country} };
            $Details->{Company_Occupation} = $lookup_occupation{ $Details->{Company_Occupation} };

        } elsif ( $Details->{MessageType} eq "WP_result_info" || $Details->{MessageType} eq "WP_final_result_info" ) {
            if ( $Details->{Auth_Required} == 1 ) {
                $Details->{Auth_Required} = "Always";
            } else {
                $Details->{Auth_Required} = "Authorize";
            }

            $Details->{Status} = $lookup_WP_status{ $Details->{Status} };
        }
    } else {
        print "[$ChanID][$CommandID]\n" if ( $Me->{_Debug} );
    }
}

#now some lookup tables for the White Pages..(might move to seprate file..)

%_Status_Codes = (
    0   => 'Online',
    32  => 'Free for Chat',
    1   => 'Away',
    5   => 'N/A',
    17  => 'Occupied',
    19  => 'Do Not Disturb',
    256 => 'Invisible'
);

%lookup_sex = (
    0 => "not specified",
    1 => "female",
    2 => "male"
);

%lookup_WP_status = (
    0 => "Offline",
    1 => "Online",
    2 => "Unreleased"
);

%lookup_occupation = (
    1  => "Academic",
    2  => "Administrative",
    3  => "Art/Entertainment",
    4  => "College Student",
    5  => "Computers",
    6  => "Community & Social",
    7  => "Education",
    8  => "Engineering",
    9  => "Financial Services",
    10 => "Government",
    11 => "High School Student",
    12 => "Home",
    13 => "ICQ - Providing Help",
    14 => "Law",
    15 => "Managerial",
    16 => "Manufacturing",
    17 => "Medical/Health",
    18 => "Military",
    19 => "Non-Government Organization",
    20 => "Professional",
    21 => "Retail",
    22 => "Retired",
    23 => "Science & Research",
    24 => "Sports",
    25 => "Technical",
    26 => "University Student",
    27 => "Web Building",
    99 => "Other Services",
);

%lookup_language = (
    1  => 'Arabic',
    2  => 'Bhojpuri',
    3  => 'Bulgarian',
    4  => 'Burmese',
    5  => 'Cantonese',
    6  => 'Catalan',
    7  => 'Chinese',
    8  => 'Croatian',
    9  => 'Czech',
    10 => 'Danish',
    11 => 'Dutch',
    12 => 'English',
    13 => 'Esperanto',
    14 => 'Estonian',
    15 => 'Farsi',
    16 => 'Finnish',
    17 => 'French',
    18 => 'Gaelic',
    19 => 'German',
    20 => 'Greek',
    21 => 'Hebrew',
    22 => 'Hindi',
    23 => 'Hungarian',
    24 => 'Icelandic',
    25 => 'Indonesian',
    26 => 'Italian',
    27 => 'Japanese',
    28 => 'Khmer',
    29 => 'Korean',
    30 => 'Lao',
    31 => 'Latvian',
    32 => 'Lithuanian',
    33 => 'Malay',
    34 => 'Norwegian',
    35 => 'Polish',
    36 => 'Portuguese',
    37 => 'Romanian',
    38 => 'Russian',
    39 => 'Serbian',
    40 => 'Slovak',
    41 => 'Slovenian',
    42 => 'Somali',
    43 => 'Spanish',
    44 => 'Swahili',
    45 => 'Swedish',
    46 => 'Tagalog',
    47 => 'Tatar',
    48 => 'Thai',
    49 => 'Turkish',
    50 => 'Ukrainian',
    51 => 'Urdu',
    52 => 'Vietnamese',
    53 => 'Yiddish',
    54 => 'Yoruba',
    55 => 'Afrikaans',
    56 => 'Bosnian',
    57 => 'Persian',
    58 => 'Albanian',
    59 => 'Armenian',
    60 => 'Punjabi',
    61 => 'Chamorro',
    62 => 'Mongolian',
    63 => 'Mandarin',
    64 => 'Taiwaness',
    65 => 'Macedonian',
    66 => 'Sindhi',
    67 => 'Welsh',
    68 => 'Azerbaijani',
    69 => 'Kurdish',
    70 => 'Gujarati',
    71 => 'Tamil',
    72 => 'Belorussian',
    73 => 'Unknown',
);

%lookup_country = (
    1     => "USA",
    7     => "Russia",
    20    => "Egypt",
    27    => "South Africa",
    30    => "Greece",
    31    => "Netherlands",
    32    => "Belgium",
    33    => "France",
    33    => "Monaco",
    34    => "Spain",
    36    => "Hungary",
    38    => "Yugoslavia",
    39    => "Italy",
    39    => "San Marino",
    39    => "Vatican City",
    40    => "Romania",
    41    => "Liechtenstein",
    41    => "Switzerland",
    42    => "Czech Republic",
    43    => "Austria",
    44    => "UK",
    45    => "Denmark",
    46    => "Sweden",
    47    => "Norway",
    48    => "Poland",
    49    => "Germany",
    51    => "Peru",
    52    => "Mexico",
    53    => "Guantanomo Bay",
    54    => "Argentina",
    55    => "Brazil",
    56    => "Chile",
    57    => "Columbia",
    58    => "Venezuela",
    60    => "Malaysia",
    61    => "Australia",
    62    => "Indonesia",
    63    => "Philippines",
    64    => "New Zealand",
    65    => "Singapore",
    66    => "Thailand",
    81    => "Japan",
    82    => "South Korea",
    84    => "Vietnam",
    86    => "China",
    90    => "Turkey",
    91    => "India",
    92    => "Pakistan",
    94    => "Sri Lanka",
    98    => "Iran",
    107   => "Canada",
    212   => "Morocco",
    213   => "Algeria",
    216   => "Tunisia",
    218   => "Libya",
    221   => "Senegal",
    223   => "Mali",
    225   => "Ivory Coast",
    231   => "Liberia",
    233   => "Ghana",
    234   => "Nigeria",
    237   => "Cameroon",
    241   => "Gabon",
    243   => "Zaire",
    251   => "Ethiopia",
    254   => "Kenya",
    255   => "Tanzania",
    263   => "Zimbabwe",
    264   => "Namibia",
    265   => "Malawi",
    297   => "Aruba",
    351   => "Portugal",
    352   => "Luxembourg",
    353   => "Ireland",
    354   => "Iceland",
    356   => "Malta",
    357   => "Cyprus",
    358   => "Finland",
    359   => "Bulgaria",
    380   => "Ukraine",
    501   => "Belize",
    502   => "Guatemala",
    503   => "El Salvador",
    504   => "Honduras",
    505   => "Nicaragua",
    506   => "Costa Rice",
    507   => "Panama",
    509   => "Haiti",
    590   => "Guadeloupe",
    591   => "Bolivia",
    592   => "Guyana",
    593   => "Ecuador",
    595   => "Paraguay",
    596   => "French Antilles",
    597   => "Suriname",
    598   => "Uruguay",
    599   => "Netherlands Antilles",
    670   => "Saipan",
    670   => "Saipan",
    671   => "Guam",
    675   => "Papua New Guinea",
    679   => "Fiji",
    684   => "American Samoa",
    687   => "New Caledonia",
    689   => "French Polynesia",
    852   => "Hong Kong",
    868   => "Trinidad and Tobago",
    880   => "Bangladesh",
    886   => "Taiwan",
    962   => "Jordan",
    964   => "Iraq",
    965   => "Kuwait",
    966   => "Saudia Arabia",
    967   => "Yemen",
    968   => "Oman",
    971   => "United Arab Emirates",
    972   => "Israel",
    973   => "Bahrain",
    974   => "Qatar",
    977   => "Nepal",
    4201  => "Slovak Republic",
    65535 => "Not entered",
);

%lookup_pastbackground = (
    300 => "Elementary School",
    301 => "High School",
    302 => "College",
    303 => "University",
    304 => "Military",
    305 => "Past Work Place",
    306 => "Past Organization",
    399 => "Other",
);

%lookup_organization = (
    200 => "Alumni Org.",
    201 => "Charity Org.",
    202 => "Club/Social Org.",
    203 => "Community Org.",
    204 => "Cultural Org.",
    205 => "Fan Clubs",
    206 => "Fraternity/Sorority",
    207 => "Hobbyists Org.",
    208 => "International Org.",
    209 => "Nature and Environment Org.",
    210 => "Professional Org.",
    211 => "Scientific/Technical Org.",
    212 => "Self Improvement Group",
    213 => "Spiritual/Religious Org.",
    214 => "Sports Org.",
    215 => "Support Org.",
    216 => "Trade and Business Org.",
    217 => "Union",
    218 => "Voluntary Org.",
    299 => "Other",
);

%lookup_interest = (
    134 => "60's",
    135 => "70's",
    136 => "80's",
    100 => "Art",
    128 => "Astronomy",
    147 => "Audio and Visual",
    125 => "Business",
    146 => "Business Services",
    101 => "Cars",
    102 => "Celebrity Fans",
    130 => "Clothing",
    103 => "Collections",
    104 => "Computers",
    140 => "Consumer Electronics",
    105 => "Culture",
    122 => "Ecology",
    139 => "Entertainment",
    138 => "Finance and Corporate",
    106 => "Fitness",
    107 => "Games",
    124 => "Government",
    142 => "Health and Beauty",
    108 => "Hobbies",
    150 => "Home Automation",
    144 => "Household Products",
    109 => "ICQ - Help",
    110 => "Internet",
    111 => "Lifestyle",
    145 => "Mail Order Catalog",
    143 => "Media",
    112 => "Movies and TV",
    113 => "Music",
    126 => "Mystics",
    123 => "News and Media",
    114 => "Outdoors",
    115 => "Parenting",
    131 => "Parties",
    116 => "Pets and Animals",
    149 => "Publishing",
    117 => "Religion",
    141 => "Retail Stores",
    118 => "Science",
    119 => "Skills",
    133 => "Social science",
    129 => "Space",
    148 => "Sporting and Athletic",
    120 => "Sports",
    127 => "Travel",
    121 => "Web Design",
    132 => "Women",
);
1;
