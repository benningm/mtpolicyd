package Mail::MtPolicyd::Plugin::GeoIPLookup;

use Moose;
use namespace::autoclean;

# VERSION
# ABSTRACT: mtpolicyd plugin for checking geo information of an client_address

extends 'Mail::MtPolicyd::Plugin';

use Mail::MtPolicyd::Plugin::Result;

use Geo::IP;

=head1 DESCRIPTION

This plugin queries a GeoIP for the country code of the client_address.
The plugin is devided in this plugin which does the Lookup and the GeoIPAction
plugin which can be used to take actions based on country code.

=head1 PARAMETERS

=over

=item database (default: /usr/share/GeoIP/GeoIP.dat)

The path to the geoip country database.

=back

=head1 MAXMIND GEOIP COUNTRY DATABASE

On a debian system you can install the country database with the geoip-database package.

You also download it directly from Maxmind:

http://dev.maxmind.com/geoip/geoip2/geolite2/

(choose "GeoLite2 Country/DB")

=cut

has '_geoip' => (
	is => 'ro', isa => 'Geo::IP', lazy => 1,
	default => sub {
		my $self = shift;
		Geo::IP->open( $self->database, GEOIP_STANDARD );
	},
);

has 'database' => ( is => 'rw', isa => 'Str', default => '/usr/share/GeoIP/GeoIP.dat');

sub run {
	my ( $self, $r ) = @_;
	my $ip = $r->attr('client_address');
	my $session = $r->session;

	my ( $result ) = $r->do_cached('geoip-'.$self->name.'-result',
		sub { $self->_geoip->country_code_by_addr( $ip ) } );

	if( ! defined $result ) {
		$self->log($r, 'no GeoIP record for '.$ip.' found');
	}

	return;
}

__PACKAGE__->meta->make_immutable;

1;

