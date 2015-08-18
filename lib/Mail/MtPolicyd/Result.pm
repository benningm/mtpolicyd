package Mail::MtPolicyd::Result;

use Moose;
use namespace::autoclean;

# VERSION
# ABSTRACT: class to hold the results of a request returned by plugins

has 'plugin_results' => (
	is => 'ro',
	isa => 'ArrayRef[Mail::MtPolicyd::Plugin::Result]',
	lazy => 1,
	default => sub { [] },
	traits => [ 'Array' ],
	handles => {
		'add_plugin_result' => 'push',
	},
);

has 'last_match' => ( is => 'rw', isa => 'Maybe[Str]' );

sub actions {
	my $self = shift;
	return map {
		defined $_->action ? $_->action : ()
	} @{$self->plugin_results};
}

sub as_log {
	my $self = shift;
	return join(',', $self->actions);
}

sub as_policyd_response {
	my $self = shift;
	my @actions = $self->actions;
	if( ! @actions ) {
		# we have nothing to say
		return("action=dunno\n\n");
	}
	return('action='.join("\naction=", @actions)."\n\n");
}

__PACKAGE__->meta->make_immutable;

1;

