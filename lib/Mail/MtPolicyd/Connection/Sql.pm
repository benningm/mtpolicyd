package Mail::MtPolicyd::Connection::Sql;

use Moose;

extends 'Mail::MtPolicyd::Connection';

# ABSTRACT: Connection pool sql connection object
# VERSION

use DBI;

has 'dsn' => ( is => 'ro', isa => 'Str', required => 1 );
has 'user' => ( is => 'ro', isa => 'Str', default => '' );
has 'password' => ( is => 'ro', isa => 'Str', default => '' );

has 'handle' => ( is => 'rw', isa => 'DBI::db', lazy => 1,
    default => sub {
      my $self = shift;
      return $self->_create_handle;
    },
    handles => [ 'disconnect' ],
);

sub _create_handle {
  my $self = shift;
  my $handle = DBI->connect(
    $self->dsn,
    $self->user,
    $self->password,
    {
      RaiseError => 1,
      PrintError => 0,
      AutoCommit => 1,
      mysql_auto_reconnect => 1,
    },
  );
  return $handle;
}

sub reconnect {
  my $self = shift;
  $self->handle( $self->_create_handle );
}

1;

