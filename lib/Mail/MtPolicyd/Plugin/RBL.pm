package Mail::MtPolicyd::Plugin::RBL;

use Moose;
use namespace::autoclean;

# VERSION
# ABSTRACT: mtpolicyd plugin for checking the client-address against an RBL

=head1 DESCRIPTION

This plugin queries a DNS black/white list.

=cut

extends 'Mail::MtPolicyd::Plugin';
with 'Mail::MtPolicyd::Plugin::Role::Scoring';
with 'Mail::MtPolicyd::Plugin::Role::UserConfig' => {
	'uc_attributes' => [ 'enabled' ],
};

use Mail::MtPolicyd::Plugin::Result;

use Mail::RBL;

=head1 PARAMETERS

=over

=item domain (required)

The domain of the blacklist to query.

=item (uc_)enabled (default: on)

Enable/disable this check.

=item mode (default: reject)

=over

=item reject

Reject the message. (reject)

=item accept

Stop processing an accept this message. (dunno)

=item passive

Only apply the score if one is given.

=back

=item reject_message (default: delivery from %IP% rejected %INFO%)

A pattern for the reject message if mode is set to 'reject'.

=item score (default: empty)

Apply this score if the check matched.

=back

=head1 EXAMPLE DNS BLACKLIST

  <Plugin sorbs.net>
    module = "RBL"
    mode = "passive"
    domain="dnsbl.sorbs.net"
    score = 5
  </Plugin>

=head1 EXAMPLE DNS WHITELIST

  <Plugin dnswl.org>
    module = "RBL"
    mode = "accept" # will stop here
    domain="list.dnswl.org"
  </Plugin>

=cut

has 'domain' => ( is => 'rw', isa => 'Str', required => 1 );
has 'enabled' => ( is => 'rw', isa => 'Str', default => 'on' );

has 'mode' => ( is => 'rw', isa => 'Str', default => 'reject' );

has 'reject_message' => (
	is => 'ro', isa => 'Str', default => 'delivery from %IP% rejected %INFO%',
);

has 'score' => ( is => 'rw', isa => 'Maybe[Num]' );

has '_rbl' => (
	is => 'ro', isa => 'Mail::RBL', lazy => 1,
	default => sub {
		my $self = shift;
		Mail::RBL->new($self->domain)
	},
);

sub run {
	my ( $self, $r ) = @_;
	my $ip = $r->attr('client_address');
	my $session = $r->session;

	my $enabled = $self->get_uc( $session, 'enabled' );
	if( $enabled eq 'off' ) {
		return;
	}
		
	my ( $ip_result, $info ) = $r->do_cached('rbl-'.$self->name.'-result',
		sub { $self->_rbl->check( $ip ) } );

	if( ! defined $ip_result ) {
		$self->log($r, 'ip '.$ip.' not on '.$self->domain.' blacklist');
		return; # host is not on the list
	}
	$self->log($r, 'ip '.$ip.' on '.$self->domain.' blacklist'.( defined $info ? ' ('.$info.')' : '' ) );
	if( defined $self->score && ! $r->is_already_done('rbl-'.$self->name.'-score') ) {
		$self->add_score($r, $self->name => $self->score);
	}

	if( $self->mode eq 'reject' ) {
		return Mail::MtPolicyd::Plugin::Result->new(
			action => $self->_get_reject_action($ip, $info),
			abort => 1,
		);
	}
	if( $self->mode eq 'accept' ) {
		return Mail::MtPolicyd::Plugin::Result->new_dunno;
	}

	return;
}

sub _get_reject_action {
	my ( $self, $ip, $info ) = @_;
	my $message = $self->reject_message;
	$message =~ s/%IP%/$ip/;
	if( defined $info && $info ne '' ) {
		$message =~ s/%INFO%/($info)/;
	} else {
		$message =~ s/%INFO%//;
	}
	return('reject '.$message);
}

__PACKAGE__->meta->make_immutable;

1;

