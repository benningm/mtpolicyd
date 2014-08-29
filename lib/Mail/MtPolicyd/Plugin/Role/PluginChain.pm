package Mail::MtPolicyd::Plugin::Role::PluginChain;

use Moose::Role;

# VERSION
# ABSTRACT: role for plugins to support a nested plugin chain

use Mail::MtPolicyd::PluginChain;

has 'chain' => (
	is => 'ro',
	isa => 'Maybe[Mail::MtPolicyd::PluginChain]',
	lazy => 1,
	default => sub {
		my $self = shift;
		if( defined $self->Plugin ) {
			return Mail::MtPolicyd::PluginChain->new_from_config(
				$self->vhost_name,
				$self->Plugin,
			);
		}
		return;
	},
);
has 'Plugin' => ( is => 'rw', isa => 'Maybe[HashRef]' );

1;

