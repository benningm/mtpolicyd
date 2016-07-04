package Mail::MtPolicyd::Plugin::GeoIPAction;

use Moose;
use namespace::autoclean;

# VERSION
# ABSTRACT: mtpolicyd plugin for checking geo information of an ip

=head1 DESCRIPTION

This plugin will execute an action or score based on a previous lookup
done with GeoIPLookup plugin.

=head1 PARAMETERS

=over

=item result_from (required)

Take the GeoIP information from the result of this plugin.

The plugin in must be executed before this plugin.

=item (uc_)enabled (default: on)

Enable/disable this plugin.

=item country_codes (required)

A comma separated list of 2 letter country codes to match.

=item (uc_)mode (default: reject)

If set to 'passive' no action will be returned.

=item reject_message (default: 'delivery from %CC% (%IP%) rejected)

Could be used to specify an custom reject message.

=item score (default: empty)

A score to apply to the message.

=back

=cut

extends 'Mail::MtPolicyd::Plugin';
with 'Mail::MtPolicyd::Plugin::Role::Scoring';
with 'Mail::MtPolicyd::Plugin::Role::UserConfig' => {
	'uc_attributes' => [ 'enabled', 'mode' ],
};

use Mail::MtPolicyd::Plugin::Result;

has 'result_from' => ( is => 'rw', isa => 'Str', required => 1 );
has 'enabled' => ( is => 'rw', isa => 'Str', default => 'on' );
has 'mode' => ( is => 'rw', isa => 'Str', default => 'reject' );

has 'country_codes' => ( is => 'rw', isa => 'Str', required => 1 );
has '_country_codes' => (
	is => 'ro', isa => 'ArrayRef', lazy => 1,
	default => sub {
		my $self = shift;
		return [ split(/\s*,\s*/, $self->country_codes) ];
	},
);

sub is_in_country_codes {
	my ( $self, $cc ) = @_;
	if ( grep { $_ eq $cc } @{$self->_country_codes} ) {
		return(1);
	}
	return(0);
}

has 'reject_message' => (
	is => 'ro', isa => 'Str', default => 'delivery from %CC% (%IP%) rejected',
);

has 'score' => ( is => 'rw', isa => 'Maybe[Num]' );

sub run {
	my ( $self, $r ) = @_;
	my $ip = $r->attr('client_address');
	my $session = $r->session;
	my $mode = $self->get_uc( $session, 'mode' );
	my $enabled = $self->get_uc( $session, 'enabled' );

	if( $enabled eq 'off' ) {
		return;
	}

	my $result_key = 'geoip-'.$self->result_from.'-result';
	if( ! defined $session->{$result_key} ) {
		$self->log( $r, 'no GeoIP check result for '.$self->name.' found!');
		return;
	}
	my ( $country_code ) = @{$session->{$result_key}};
  if( ! defined $country_code ) {
    return;
  }

	if( ! $self->is_in_country_codes( $country_code ) ) {
		$self->log( $r, 'country_code '.$country_code.' of IP not in country_code list'.$self->name);
		return;
	}

	$self->log( $r, 'country code '.$country_code.' on list'.$self->name );
	if( defined $self->score && ! $r->is_already_done('geoip-'.$self->name.'-score') ) {
		$self->add_score($r, $self->name => $self->score);
	}

	if( $mode eq 'reject' ) {
		return Mail::MtPolicyd::Plugin::Result->new(
			action => $self->_get_reject_action($ip, $country_code ),
			abort => 1,
		);
	}
	if( $mode eq 'accept' || $mode eq 'dunno' ) {
		return Mail::MtPolicyd::Plugin::Result->new_dunno;
	}

	return;
}

sub _get_reject_action {
	my ( $self, $ip, $cc ) = @_;
	my $message = $self->reject_message;
	$message =~ s/%IP%/$ip/;
	$message =~ s/%CC%/$cc/;
	return('reject '.$message);
}

__PACKAGE__->meta->make_immutable;

1;

