package Mail::MtPolicyd::Connection::Ldap;

use Moose;

extends 'Mail::MtPolicyd::Connection';

# ABSTRACT: connection pool object to hold a ldap connection
# VERSION

use Net::LDAP;

has 'host' => ( is => 'ro', isa => 'Str', required => 1 );
has 'port' => ( is => 'ro', isa => 'Int', default => 389 );

has 'keepalive' => ( is => 'ro', isa => 'Bool', default => 1 );
has 'timeout' => ( is => 'ro', isa => 'Int', default => 120 );

has 'binddn' => ( is => 'ro', isa => 'Maybe[Str]' );
has 'password' => ( is => 'ro', isa => 'Maybe[Str]' );

has 'starttls' => ( is => 'ro', isa => 'Bool', default => 1 );

has 'handle' => ( is => 'rw', isa => 'Net::LDAP', lazy => 1,
    default => sub {
      my $self = shift;
      return $self->_connect_ldap;
    },
    handles => {
      'disconnect' => 'unbind',
    },
);

has 'connection_class' => ( is => 'ro', isa => 'Maybe[Str]' );

sub _connect_ldap {
  my $self = shift;
  my $ldap_class = 'Net::LDAP';

  if( defined $self->connection_class ) {
    $ldap_class = $self->connection_class;
    eval "require $ldap_class;"; ## no critic
  }

  my $ldap = $ldap_class->new(
    $self->host,
    port => $self->port,
    keepalive => $self->keepalive,
    timeout => $self->timeout,
    onerror => 'die',
  ) or die ('cant connect ldap: '.$@);

  if( $self->starttls ) {
    eval{ $ldap->start_tls( verify => 'require' ); };
    if( $@ ) { die('starttls on ldap connection failed: '.$@); }
  }

  if( defined $self->binddn ) {
    $ldap->bind( $self->binddn, password => $self->password );
  } else {
    $ldap->bind; # anonymous bind
  }

  return $ldap;
}

sub reconnect {
  my $self = shift;
  $self->handle( $self->_connect_ldap );
  return;
}

sub shutdown {
  my $self = shift;
  $self->handle->unbind;
  return;
}

1;

