package Mail::MtPolicyd::VirtualHost;

use Moose;
use namespace::autoclean;

# VERSION
# ABSTRACT: class for a VirtualHost instance

use Mail::MtPolicyd::PluginChain;

has 'port' => ( is => 'ro', isa => 'Str', required => 1 );
has 'name' => ( is => 'ro', isa => 'Str', required => 1 );

has 'chain' => (
	is => 'ro',
	isa => 'Mail::MtPolicyd::PluginChain',
	required => 1,
	handles => [ 'run' ],
);

sub new_from_config {
	my ( $class, $port, $config ) = @_;

	if( ! defined $config->{'Plugin'} ) {
		die('no <Plugin> defined for <VirtualHost> on port '.$port.'!');
	}
	my $vhost = $class->new(
		'port' => $port,
		'name' => $config->{'name'},
		'chain' => Mail::MtPolicyd::PluginChain->new_from_config(
			$config->{'name'},
			$config->{'Plugin'}
		),
	);

	return $vhost;
}

sub cron {
    my $self = shift;
    return $self->chain->cron(@_);
}

__PACKAGE__->meta->make_immutable;

1;

