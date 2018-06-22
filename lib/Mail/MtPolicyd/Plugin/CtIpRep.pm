package Mail::MtPolicyd::Plugin::CtIpRep;

use Moose;
use namespace::autoclean;

# VERSION
# ABSTRACT: mtpolicyd plugin for the Commtouch IP reputation service (ctipd)

=head1 DESCRIPTION

This plugin will query the Commtouch IP Reputation service (ctipd).

The used protocol is HTTP.

The services will return a status permfail or tempfail.

=cut

extends 'Mail::MtPolicyd::Plugin';
with 'Mail::MtPolicyd::Plugin::Role::Scoring';
with 'Mail::MtPolicyd::Plugin::Role::UserConfig' => {
	'uc_attributes' => [ 'enabled', 'tempfail_mode', 'permfail_mode' ],
};

use Mail::MtPolicyd::Plugin::Result;

use LWP::UserAgent;
use HTTP::Request::Common;

=head1 PARAMETERS

=over

=item (uc_)enabled (default: on)

Enable/disable the plugin.

=item url (default: http://localhost:8080/ctipd/iprep)

The URL to access the ctipd daemon.

=item key (default: empty)

If an authentication key is required by the ctipd.

=item reject_message (default: 550 delivery from %IP% is rejected. Check at http://www.commtouch.com/Site/Resources/Check_IP_Reputation.asp. Reference code: %REFID%)

This parameter could be used to specify a custom reject message if message is rejected.

=item defer_message (default: 450 delivery from %IP% is deferred,repeatedly. Send again or check at http://www.commtouch.com/Site/Resources/Check_IP_Reputation.asp. Reference code: %REFID%)

This parameter could be used to specify a custom message is a message is to be deferred.

=item (uc_)permfail_mode, (uc_)tempfail_mode (default: reject, defer)

Action to take when the service return permfail/tempfail status:

=over

=item reject

=item defer

=item passive

=back

=item permfail_score, tempfail_score (default: empty)

Apply the specified score.

=back

=cut

has 'enabled' => ( is => 'rw', isa => 'Str', default => 'on' );

has '_agent' => (
	is => 'ro', isa => 'LWP::UserAgent', lazy => 1,
	default => sub { LWP::UserAgent->new }
);
has 'url' => (
	is => 'ro', isa => 'Str', default => 'http://localhost:8080/ctipd/iprep',
);
has 'key' => ( is => 'ro', isa => 'Maybe[Str]' );

has 'reject_message' => (
	is => 'rw', isa => 'Str', default => '550 delivery from %IP% is rejected. Check at http://www.commtouch.com/Site/Resources/Check_IP_Reputation.asp. Reference code: %REFID%',
);
has 'defer_message' => (
	is => 'rw', isa => 'Str', default => '450 delivery from %IP% is deferred,repeatedly. Send again or check at http://www.commtouch.com/Site/Resources/Check_IP_Reputation.asp. Reference code: %REFID%',
);

has 'permfail_score' => ( is => 'rw', isa => 'Maybe[Num]' );
has 'permfail_mode' => ( is => 'rw', isa => 'Str', default => 'reject' );

has 'tempfail_score' => ( is => 'rw', isa => 'Maybe[Num]' );
has 'tempfail_mode' => ( is => 'rw', isa => 'Str', default => 'defer' );

sub _scan_ip {
	my ( $self, $ip ) = @_;
	my $request = "x-ctch-request-type: classifyip\r\n".
		"x-ctch-pver: 1.0\r\n";
	if( defined $self->key ) {
		$request .= 'x-ctch-key: '.$self->key."\r\n";
	}
	$request .= "\r\n";
	$request .= 'x-ctch-ip: '.$ip."\r\n";

	my $response = $self->_agent->request(POST $self->url, Content => $request );
	if( $response->code ne 200 ) {
		die('error while accessing Commtouch ctipd: '.$response->status_line);
	}
	my $content = $response->content;
	my ( $action ) = $content =~ m/^x-ctch-dm-action:(.*)\r$/m;
	my ( $refid ) = $content =~ m/^x-ctch-refid:(.*)\r$/m;
	if( ! defined $action ) {
		die('could not find action in response: '.$content);
	}

	return( $action, $refid );
}

sub run {
	my ( $self, $r ) = @_;
	my $ip = $r->attr('client_address');
	my $session = $r->session;
	my $mode;

	if( ! defined $ip ) {
		die('no client_address in request!');
	}

	my $enabled = $self->get_uc($session, 'enabled');
	if( $enabled eq 'off' ) {
		return;
	}
		
	my ( $result, $refid ) = $r->do_cached( $self->name.'-result',
		sub{ $self->_scan_ip( $ip ) } );

	if( $result eq 'accept') {
		$self->log( $r, 'CtIpRep: sender IP is ok' );
		return; # do nothing
	} elsif( $result eq 'permfail' ) {
		$mode = $self->get_uc( $session, 'permfail_mode' );
		if( $self->permfail_score 
				&& ! $r->is_already_done($self->name.'-score') ) {
			$self->add_score($r, $self->name => $self->permfail_score);
		}
	} elsif ($result eq 'tempfail' ) {
		$mode = $self->get_uc( $session, 'tempfail_mode' );
		if( $self->tempfail_score
				&& ! $r->is_already_done($self->name.'-score') ) {
			$self->add_score($r, $self->name => $self->tempfail_score);
		}
	} else {
		die('unknown ctiprep action: '.$result);
	}
	$self->log($r, 'CtIpRep: result='.$result.', mode='.$mode);

	if ( $mode eq 'reject' || $mode eq 'defer' ) {
		return Mail::MtPolicyd::Plugin::Result->new(
			action => $self->_build_action($mode, $ip, $refid),
			abort => 1,
		);
	}
	return;
}

sub _build_action {
	my ( $self, $action, $ip, $refid ) = @_;
	my $message;
	if( $action eq 'reject' ) {
		$message = $self->reject_message;
	} elsif ( $action eq 'defer' ) {
		$message = $self->defer_message;
	} else {
		die('unknown action: '.$action);
	}
	$message =~ s/%IP%/$ip/;
	$message =~ s/%REFID%/$refid/;

	return($action.' '.$message);
}

__PACKAGE__->meta->make_immutable;

1;

