package Mail::MtPolicyd::Connection::Memcached;

use Moose;

extends 'Mail::MtPolicyd::Connection';

use Cache::Memcached;

has 'servers' => ( is => 'ro', isa => 'Str', required => 1 );
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

