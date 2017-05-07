package Mail::MtPolicyd::Plugin::Greylist::Ticket::Base;

use Moose;

# ABSTRACT: base class for greylisting ticket storage backends
# VERSION

has 'min_retry_wait' => ( is => 'rw', isa => 'Int', default => 60*5 );
has 'max_retry_wait' => ( is => 'rw', isa => 'Int', default => 60*60*2 );

has 'prefix' => ( is => 'rw', isa => 'Str', default => '' );

sub _get_key {
	my ( $self, $sender, $ip, $rcpt ) = @_;
	return join(",", $sender, $ip, $rcpt );
}

sub init {
  my $self = shift;
  return;
}

sub get {
	my ( $self, $r, $sender, $ip, $rcpt ) = @_;
  die('not implemented');
}

sub is_valid {
	my ( $self, $ticket ) = @_;
  die('not implemented');
}

sub remove {
	my ( $self, $r, $sender, $ip, $rcpt ) = @_;
  die('not implemented');
}

sub create {
	my ( $self, $r, $sender, $ip, $rcpt ) = @_;
  die('not implemented');
}

sub expire { }

1;

