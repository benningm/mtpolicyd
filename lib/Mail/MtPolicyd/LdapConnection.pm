package Mail::MtPolicyd::LdapConnection;

use strict;
use MooseX::Singleton;

# ABSTRACT: singleton class to hold the ldap server connection
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
    $ldap->start_tls( verify => 'require' );
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
}

sub is_initialized {
    my ( $class, @args ) = @_;

    if( $class->meta->existing_singleton ) {
        return( 1 );
    }
    return( 0 );
}

1;

