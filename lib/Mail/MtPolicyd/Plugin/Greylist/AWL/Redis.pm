package Mail::MtPolicyd::Plugin::Greylist::AWL::Redis;

use Moose;

# ABSTRACT: backend for redis greylisting awl storage
# VERSION

use Time::Seconds;

extends 'Mail::MtPolicyd::Plugin::Greylist::AWL::Base';

with 'Mail::MtPolicyd::Role::Connection' => {
  name => 'redis',
  type => 'Redis',
};

has 'prefix' => ( is => 'rw', isa => 'Str', default => 'awl-' );

sub _get_key {
  my ( $self, $domain, $ip ) = @_;
  return join(',', $self->prefix, $domain, $ip);
}

sub get {
	my ( $self, $sender_domain, $client_ip ) = @_;
  my $key = $self->_get_key($sender_domain, $client_ip);
	return $self->_redis_handle->get($key);
}

sub create {
	my ( $self, $sender_domain, $client_ip ) = @_;
  my $key = $self->_get_key($sender_domain, $client_ip);
  my $expire = ONE_DAY * $self->autowl_expire_days;
	$self->_redis_handle->set( $key, '1', 'EX', $expire );
	return;
}

sub incr {
	my ( $self, $sender_domain, $client_ip ) = @_;
  my $key = $self->_get_key($sender_domain, $client_ip);
  my $count = $self->_redis_handle->incr($key, sub {});
  my $expire = ONE_DAY * $self->autowl_expire_days;
	$self->_redis_handle->expire( $key, $expire, sub {});
  $self->_redis_handle->wait_all_responses;
	return;
}

sub remove {
	my ( $self, $sender_domain, $client_ip ) = @_;
  my $key = $self->_get_key($sender_domain, $client_ip);
	$self->_redis_handle->del($key);
	return;
}


1;

