package Mail::MtPolicyd::Plugin::Greylist::AWL::Base;

use Moose;

# ABSTRACT: base class for grelisting AWL storage backends
# VERSION

has 'autowl_expire_days' => ( is => 'rw', isa => 'Int', default => 60 );

sub init {
  my $self = shift;
  return;
}

sub get {
	my ( $self, $sender_domain, $client_ip ) = @_;
  die('not implemented');
}

sub create {
	my ( $self, $sender_domain, $client_ip ) = @_;
  die('not implemented');
}

sub incr {
	my ( $self, $sender_domain, $client_ip ) = @_;
  die('not implemented');
}

sub remove {
	my ( $self, $sender_domain, $client_ip ) = @_;
  die('not implemented');
}

sub expire { }

1;

