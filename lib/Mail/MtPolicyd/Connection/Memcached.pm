package Mail::MtPolicyd::Connection::Memcached;

use Moose;

# VERSION
# ABSTRACT: a memcached connection plugin for mtpolicyd

extends 'Mail::MtPolicyd::Connection';

=head1 SYNOPSIS

  <Connection memcached>
    module = "Memcached"
    servers = "127.0.0.1:11211"
    # namespace = "mt-"
  </Connection>

=head1 PARAMETERS

=over

=item servers (default: 127.0.0.1:11211)

Comma seperated list for memcached servers to connect.

=item debug (default: 0)

Enable to debug memcached connection.

=item namespace (default: '')

Set a prefix used for all keys of this connection.

=back

=cut

use Cache::Memcached;

has 'servers' => ( is => 'ro', isa => 'Str', default => '127.0.0.1:11211' );
has '_servers' => (
  is => 'ro', isa => 'ArrayRef[Str]', lazy => 1,
  default => sub {
    my $self = shift;
    return [ split(/\s*,\s*/, $self->servers) ];
  },
);

has 'debug' => ( is => 'ro', isa => 'Bool', default => 0 );
has 'namespace' => ( is => 'ro', isa => 'Str', default => '');

sub _create_handle {
  my $self = shift;
  return Cache::Memcached->new( {
    'servers' => $self->_servers,
    'debug' => $self->debug,
    'namespace' => $self->namespace,
  } );
}

has 'handle' => (
  is => 'rw', isa => 'Cache::Memcached', lazy => 1,
  default => sub {
    my $self = shift;
    $self->_create_handle
  },
);

sub reconnect {
  my $self = shift;
  $self->handle( $self->_create_handle );
  return;
}

sub shutdown {
  my $self = shift;
  $self->handle->disconnect_all;
  return;
}

1;

