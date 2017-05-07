package Mail::MtPolicyd::Plugin::Greylist::Ticket::Redis;

use Moose;

# ABSTRACT: greylisting ticket storage backend for redis
# VERSION

extends 'Mail::MtPolicyd::Plugin::Greylist::Ticket::Base';

with 'Mail::MtPolicyd::Role::Connection' => {
  name => 'redis',
  type => 'Redis',
};

sub get {
	my ( $self, $r, $sender, $ip, $rcpt ) = @_;
	my $key = $self->_get_key($sender, $ip, $rcpt);
	if( my $ticket = $self->_redis_handle->get( $key ) ) {
		return( $ticket );
	}
	return;
}

sub is_valid {
	my ( $self, $ticket ) = @_;
	if( time > $ticket ) {
		return 1;
	}
	return 0;
}

sub remove {
	my ( $self, $r, $sender, $ip, $rcpt ) = @_;
	my $key = $self->_get_key($sender, $ip, $rcpt);
	$self->_redis_handle->del( $key );
	return;
}

sub create {
	my ( $self, $r, $sender, $ip, $rcpt ) = @_;
	my $ticket = time + $self->min_retry_wait;
	my $key = $self->_get_key($sender, $ip, $rcpt);
	$self->_redis_handle->set( $key, $ticket, 'EX', $self->max_retry_wait );
	return;
}

1;

