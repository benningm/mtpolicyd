package Mail::MtPolicyd::Plugin::SPF;

use Moose;
use namespace::autoclean;

# VERSION
# ABSTRACT: mtpolicyd plugin to apply SPF checks

=head1 DESCRIPTION

This plugin applies Sender Policy Framework(SPF) checks.

Checks are implemented using the Mail::SPF perl module.

=head1 PARAMETERS

=over

=item (uc_)enabled (default: on)

Enable/disable the plugin.

=item pass_mode (default: passive)

How to behave if the SPF checks passed successfully:

=over

=item passive

Just apply score. Do not return an action.

=item accept, dunno

Will return an 'dunno' action.

=back

=item pass_score (default: empty)

Score to apply when the sender has been successfully checked against SPF.

=item fail_mode (default: reject)

=over

=item reject

Return an reject action.

=item passive

Just apply score and do not return an action.

=back

=item reject_message (default: )

If fail_mode is set to 'reject' this message is used in the reject.

The following pattern will be replaced in the string:

=over

=item %LOCAL_EXPL%

Will be replaced with a (local) explanation of the check result.

=item %AUTH_EXPL%

Will be replaced with a URL to the explanation of the result.

This URL could be configured with 'default_authority_explanation'.

=back

=item fail_score (default: empty)

Score to apply if the sender failed the SPF checks.

=item default_authority_explanation (default: See http://www.%{d}/why/id=%{S};ip=%{I};r=%{R})

String to return as an URL pointing to an explanation of the SPF check result.

See Mail::SPF::Server for details.

=item hostname (default: empty)

An hostname to show in the default_authority_explanation as generating server.

=back

=head1 EXAMPLE

  <Plugin spf>
    module = "SPF"
    pass_mode = passive
    pass_score = -10
    fail_mode = reject
    #fail_score = 10
  </Plugin>

=cut

extends 'Mail::MtPolicyd::Plugin';

with 'Mail::MtPolicyd::Plugin::Role::Scoring';
with 'Mail::MtPolicyd::Plugin::Role::UserConfig' => {
	'uc_attributes' => [ 'enabled' ],
};

use Mail::MtPolicyd::Plugin::Result;

use Mail::SPF;

has 'enabled' => ( is => 'rw', isa => 'Str', default => 'on' );

has 'pass_score' => ( is => 'rw', isa => 'Maybe[Num]' );
has 'pass_mode' => ( is => 'rw', isa => 'Str', default => 'passive' );

has 'fail_score' => ( is => 'rw', isa => 'Maybe[Num]' );
has 'fail_mode' => ( is => 'rw', isa => 'Str', default => 'reject' );

has 'reject_message' => ( is => 'rw', isa => 'Str',
	default => 'SPF validation failed: %LOCAL_EXPL%' );

has 'default_authority_explanation' => ( is => 'ro', isa => 'Str',
	default => 'See http://www.%{d}/why/id=%{S};ip=%{I};r=%{R}' );
has 'hostname' => ( is => 'ro', isa => 'Str', default => '' );

has '_spf' => ( is => 'ro', isa => 'Mail::SPF::Server', lazy => 1,
	default => sub {
		my $self = shift;
		return Mail::SPF::Server->new(
			default_authority_explanation => $self->default_authority_explanation,
			hostname => $self->hostname,
		);
	},
);

sub run {
	my ( $self, $r ) = @_;
	my $session = $r->session;

	my $enabled = $self->get_uc($session, 'enabled');
	if( $enabled eq 'off' ) {
		return;
	}

	my $ip = $r->attr('client_address');
	my $sender = $r->attr('sender');
	my $helo = $r->attr('helo_name');

	if( ! defined $ip || ! defined $sender || ! defined $helo ) {
		$self->logdie('request atttributes client_address, sender, helo_name required!');
	}

	my $request = Mail::SPF::Request->new(
		scope => 'mfrom',
		identity => $sender,
		ip_address  => $ip,
		helo_identity => $helo,
	);
	my $result = $self->_spf->process($request);

	if( $result->code eq 'neutral') {
		$self->log( $r, 'SPF status neutral. (no SPF records)');
		return;
	} elsif( $result->code eq 'fail') {
		$self->log( $r, 'SPF check failed: '.$result->local_explanation);
		if( defined $self->fail_score && ! $r->is_already_done($self->name.'-score') ) {
			$self->add_score( $r, $self->name => $self->fail_score );
		}
		if( $self->fail_mode eq 'reject') {
			return Mail::MtPolicyd::Plugin::Result->new(
				action => $self->_get_reject_action($result),
				abort => 1,
			);
		}
		return;
	} elsif( $result->code eq 'pass' ) {
		$self->log( $r, 'SPF check passed');
		if( defined $self->pass_score && ! $r->is_already_done($self->name.'-score') ) {
			$self->add_score( $r, $self->name => $self->pass_score );
		}
		if( $self->pass_mode eq 'accept' || $self->pass_mode eq 'dunno') {
			return Mail::MtPolicyd::Plugin::Result->new_dunno;
		}
		return;
	}

	$self->log( $r, 'spf check failed: '.$result->local_explanation );
	return;
}

sub _get_reject_action {
	my ( $self, $result ) = @_;
	my $message = $self->reject_message;

	if( $message =~ /%LOCAL_EXPL%/) {
		my $expl = $result->local_explanation;
		$message =~ s/%LOCAL_EXPL%/$expl/;
	}
	if( $message =~ /%AUTH_EXPL%/) {
		my $expl = '';
		if( $result->can('authority_explanation') ) {
			$expl = $result->authority_explanation;
		}
		$message =~ s/%AUTH_EXPL%/$expl/;
	}

	return('reject '.$message);
}

__PACKAGE__->meta->make_immutable;

1;

