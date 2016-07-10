package Mail::MtPolicyd::SessionCache::Memcached;

use Moose;

extends 'Mail::MtPolicyd::SessionCache::Base';

with 'Mail::MtPolicyd::Role::Connection' => {
  name => 'memcached',
  type => 'Memcached',
};

has 'expire' => ( is => 'ro', isa => 'Int', default => 5 * 60 );

has 'lock_wait' => ( is => 'rw', isa => 'Int', default => 50 );
has 'lock_max_retry' => ( is => 'rw', isa => 'Int', default => 50 );
has 'lock_timeout' => ( is => 'rw', isa => 'Int', default => 10 );

sub shutdown {
  my $self = shift;
  $self->_memcached_handle->disconnect_all;
  return;
}

sub _acquire_session_lock {
	my ( $self, $instance ) = @_;
	my $lock = 'lock_'.$instance;

	for( my $try = 1 ; $try < $self->lock_max_retry ; $try++ ) {
		if( $self->_memcached_handle->add($lock, 1, $self->lock_ttl) ) {
			return; # lock created
		}
		usleep( $self->lock_wait * $try );
	}

	die('could not acquire lock for session '.$instance);
	return;
}

sub _release_session_lock {
	my ( $self, $instance ) = @_;
	my $lock = 'lock_'.$instance;

	$self->_memcached_handle->delete($lock);

	return;
}

sub retrieve_session {
	my ($self, $instance ) = @_;

	if( ! defined $instance ) {
		return;
	}

	$self->_acquire_session_lock( $instance );

	if( my $session = $self->_memcached_handle->get($instance) ) {
		return($session);
	}
	
	return( { '_instance' => $instance } );
}

sub store_session {
	my ($self, $session ) = @_;
	my $instance = $session->{'_instance'};

	if( ! defined $session || ! defined $instance ) {
		return;
	}
	
	$self->_memcached_handle->set($instance, $session, $self->expire);

	$self->_release_session_lock($instance);

	return;
}

1;

