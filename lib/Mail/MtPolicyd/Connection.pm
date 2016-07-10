package Mail::MtPolicyd::Connection;

use Moose;

has 'name' => ( is => 'ro', isa => 'Str', required => 1 );

sub init {
  my $self = shift;
  return;
}

sub reconnect {
  my $self = shift;
  return;
}

sub shutdown {
  my $self = shift;
  return;
}

1;

