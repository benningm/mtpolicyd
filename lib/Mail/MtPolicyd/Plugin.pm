package Mail::MtPolicyd::Plugin;

use Moose;
use namespace::autoclean;

# VERSION
# ABSTRACT: a base class for plugins

=head1 ATTRIBUTES

=head2 name

Contains a string with the name of this plugin as specified in the configuration.

=head2 log_level (default: 4)

The log_level used when the plugin calls $self->log( $r, $msg ).

=cut

has 'name' => ( is => 'rw', isa => 'Str', required => 1 );
has 'log_level' => ( is => 'ro', isa => 'Int', default => 4 );
has 'vhost_name' => ( is => 'ro', isa => 'Maybe[Str]' );

=head1 METHODS

=head2 run( $r )

This method has be implemented by the plugin which inherits from this base class.

=head2 log( $r, $msg )

This method could be used by the plugin to log something.

Since this is mostly for debugging the default is to log plugin specific
messages with log_level=4. (see log_level attribute)

=cut

sub run {
	my ( $self, $r ) = @_;
	die('plugin did not implement run method!');
}

sub log {
	my ($self, $r, $msg) = @_;
	if( defined $self->vhost_name ) {
		$msg = $self->vhost_name.': '.$msg;
	}
	$r->log($self->log_level, $msg);

	return;
}

__PACKAGE__->meta->make_immutable;

1;

