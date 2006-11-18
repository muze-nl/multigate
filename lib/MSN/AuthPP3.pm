#! perl -w
#
# Copyright Siebe Tolsma, 2006
# All Rights Reserved.
#
# Edited by John Welch, 2006
#================================================
package MSN::AuthPP3;
#================================================

# Modules!
use strict;
use vars qw($ua);

use LWP::UserAgent;
use HTML::Entities qw(decode_entities);
use HTTP::Request;

# Create new UA object we can use
our $ua =
	LWP::UserAgent->new(
		timeout => 5,
		max_redirect => 0,
		agent => 'Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1; .NET CLR 1.1.4322)'
	);

sub new
{	# Returns a newly blessed object
	my ($class,$object) = (shift,shift); 
	my ($user, $pass, $ticket) = (shift, shift, shift);

        my $self  =
        {
                Handle                                => $user,
                Password                                => $pass,
                Ticket                                => $ticket
        };

        bless( $self, $class );

	#print "Handle: $self->{Handle}\n";
	#print "Password: $self->{Password}\n";
	#print "Ticket: $self->{Ticket}\n";

	if($self->{Handle} && $self->{Password} && $self->{Ticket})
	{	# HTML encode everything!
		$self->{Handle} = $self->html_encode($self->{Handle});
		$self->{Password} = $self->html_encode($self->{Password});

		$self->{Ticket} =~ s/,/&/g;
		$self->{Ticket} = $self->url_decode($self->{Ticket});
		$self->{Ticket} = $self->html_encode($self->{Ticket});

		return $self;
	}

	return;
}

sub auth
{
	my ($self) = @_;
	
	# Compile the body (ugh)
	my $body = 
		'<?xml version="1.0" encoding="UTF-8"?>' .
		'<Envelope xmlns="http://schemas.xmlsoap.org/soap/envelope/" xmlns:wsse="http://schemas.xmlsoap.org/ws/2003/06/secext" xmlns:saml="urn:oasis:names:tc:SAML:1.0:assertion" xmlns:wsp="http://schemas.xmlsoap.org/ws/2002/12/policy" xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd" xmlns:wsa="http://schemas.xmlsoap.org/ws/2004/03/addressing" xmlns:wssc="http://schemas.xmlsoap.org/ws/2004/04/sc" xmlns:wst="http://schemas.xmlsoap.org/ws/2004/04/trust">' .
			'<Header>' .
				'<ps:AuthInfo xmlns:ps="http://schemas.microsoft.com/Passport/SoapServices/PPCRL" Id="PPAuthInfo">' .
					'<ps:HostingApp>{7108E71A-9926-4FCB-BCC9-9A9D3F32E423}</ps:HostingApp>' .
					'<ps:BinaryVersion>3</ps:BinaryVersion>' .
					'<ps:UIVersion>1</ps:UIVersion>' .
					'<ps:Cookies></ps:Cookies>' .
					'<ps:RequestParams>AQAAAAIAAABsYwQAAAAxMDMz</ps:RequestParams>' .
				'</ps:AuthInfo>' .
				'<wsse:Security>' .
					'<wsse:UsernameToken Id="user">' .
						'<wsse:Username>' . $self->{Handle} . '</wsse:Username>' .
						'<wsse:Password>' . $self->{Password} . '</wsse:Password>' .
					'</wsse:UsernameToken>' .
				'</wsse:Security>' .
			'</Header>' .
			'<Body>' .
				'<ps:RequestMultipleSecurityTokens xmlns:ps="http://schemas.microsoft.com/Passport/SoapServices/PPCRL" Id="RSTS">' .
					'<wst:RequestSecurityToken Id="RST0">' .
						'<wst:RequestType>http://schemas.xmlsoap.org/ws/2004/04/security/trust/Issue</wst:RequestType>' .
						'<wsp:AppliesTo><wsa:EndpointReference><wsa:Address>http://Passport.NET/tb</wsa:Address></wsa:EndpointReference></wsp:AppliesTo>' .
					'</wst:RequestSecurityToken>' .
					'<wst:RequestSecurityToken Id="RST1">' .
						'<wst:RequestType>http://schemas.xmlsoap.org/ws/2004/04/security/trust/Issue</wst:RequestType>' .
						'<wsp:AppliesTo><wsa:EndpointReference><wsa:Address>messenger.msn.com</wsa:Address></wsa:EndpointReference></wsp:AppliesTo>' .
						'<wsse:PolicyReference URI="?' . $self->{Ticket} . '"></wsse:PolicyReference>' .
					'</wst:RequestSecurityToken>' .
				'</ps:RequestMultipleSecurityTokens>' .
			'</Body>' .
		'</Envelope>';

	# Do a new POST request then
	my $req = HTTP::Request->new(POST => "https://loginnet.passport.com/RST.srf");
	   $req->content($body);
	my $checkerror = '<faultcode>wsse:FailedAuthentication</faultcode>';
	my $resp = $ua->request($req);
	#print $resp->content;
	if($resp->is_success)
	{	# Grab the content and then strip it down	
		if(my ($ticket) = ($resp->content =~ m!<wsse:binarysecuritytoken.*?>(t=.*?&amp;p=.*?)</!i)) {
			# We found a ticket, yayayya!
			return $self->html_decode($ticket);
		} elsif ($resp->content =~ m/$checkerror/i) {
			print "Authentication failed. Login details incorrect.\n";
			return undef;
		} else {
			print "Authentication failed. An unknown error occurred.\n";
			return undef;
		}
	} else {
		print "Authentication request failed, the authentication server appears to be down or is not responding. Check your firewall.\n";
	}
	
	return undef;
}

sub html_encode
{	# Does a quick HTML encode routine
	my ($self, $string) = @_;
	
		$string =~ s/&/&amp;/g;
		$string =~ s/</&lt;/g;
		$string =~ s/>/&gt;/g;
		$string =~ s/'/&apos;/g;
		$string =~ s/"/&quot;/g;

	return $string;	
}

sub html_decode
{	# Does a quick HTML decode
	my ($self, $string) = @_;
	return decode_entities($string);
}

sub url_decode
{	# URL decode the string
	my ($self, $string) = @_;
		$string =~ s/\%(..)/pack("H*", $1)/eg;

	return $string;
}

1;