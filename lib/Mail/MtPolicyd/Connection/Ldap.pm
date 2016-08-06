package Mail::MtPolicyd::Connection::Ldap;

use Moose;

extends 'Mail::MtPolicyd::Connection';

# ABSTRACT: a LDAP connection plugin for mtpolicyd
# VERSION

use Net::LDAP;

=head1 SYNOPSIS

  <Connection ldap>
    module = "Ldap"
    host = "localhost"
  </Connection>

=head1 PARAMETERS

=over

=item host (default: 'localhost')

LDAP server to connect to.

=item port (default: 389)

LDAP servers port number to connect to.

=item keepalive (default: 1)

Enable connection keepalive for this connection.

=item timeout (default: 120)

Timeout in seconds for operations on this connection.

=item binddn (default: undef)

If set a bind with this binddn is done when connecting.

=item password (default: undef)


=item starttls (default: 1)

Enable or disabled the use of starttls. (TLS/SSL encryption)

=back

=cut

has 'host' => ( is => 'ro', isa => 'Str', default => 'localhost' );
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

