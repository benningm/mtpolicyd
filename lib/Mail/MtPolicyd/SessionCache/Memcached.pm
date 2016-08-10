package Mail::MtPolicyd::SessionCache::Memcached;

use Moose;

# VERSION
# ABSTRACT: session cache adapter for memcached

extends 'Mail::MtPolicyd::SessionCache::Base';

with 'Mail::MtPolicyd::Role::Connection' => {
  name => 'memcached',
  type => 'Memcached',
};

use Time::HiRes qw(usleep);

=head1 SYNOPSIS

  <SessionCache>
    module = "Memcached"
    #memcached = "memcached"
    # expire session cache entries
    expire = "300"
    # wait timeout will be increased each time 50,100,150,... (usec)
    lock_wait=50
    # abort after n retries
    lock_max_retry=50
    # session lock times out after (sec)
    lock_timeout=10
  </SessionCache>

=head1 PARAMETERS

=over

=item memcached (default: memcached)

Name of the database connection to use.

You have to define this connection first.

see L<Mail::MtPolicyd::Connection::Memcached>

=item expire (default: 5*60)

Timeout in seconds for sessions.

=item lock_wait (default: 50)

Timeout for retry when session is locked in milliseconds.

The retry will be done in multiples of this timeout.

When set to 50 retry will be done in 50, 100, 150ms...

=item lock_max_retry (default: 50)

Maximum number of retries before giving up to obtain lock on a
session.

=item lock_timeout (default: 10)

Timeout of session locks in seconds.

=back

=cut

has 'expire' => ( is => 'ro', isa => 'Int', default => 5 * 60 );

has 'lock_wait' => ( is => 'rw', isa => 'Int', default => 50 );
has 'lock_max_retry' => ( is => 'rw', isa => 'Int', default => 50 );
has 'lock_timeout' => ( is => 'rw', isa => 'Int', default => 10 );

sub _acquire_session_lock {
	my ( $self, $instance ) = @_;
	my $lock = 'lock_'.$instance;

	for( my $try = 1 ; $try < $self->lock_max_retry ; $try++ ) {
		if( $self->_memcached_handle->add($lock, 1, $self->lock_timeout) ) {
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

