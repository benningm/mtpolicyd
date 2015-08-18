package Mail::MtPolicyd::SqlConnection;

use strict;
use MooseX::Singleton;

# ABSTRACT: singleton class to hold the sql database connection
# VERSION

use DBI;

has 'dsn' => ( is => 'ro', isa => 'Str', required => 1 );
has 'user' => ( is => 'ro', isa => 'Str', required => 1 );
has 'password' => ( is => 'ro', isa => 'Str', required => 1 );

has 'dbh' => ( is => 'rw', isa => 'DBI::db', lazy => 1,
    default => sub {
      my $self = shift;
      return $self->_create_dbh;
    },
    handles => [ 'disconnect' ],
);

sub _create_dbh {
  my $self = shift;
  my $dbh = DBI->connect(
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
  return $dbh;
}

sub reconnect {
  my $self = shift;
  $self->dbh( $self->_create_dbh );
}

sub is_initialized {
    my ( $class, @args ) = @_;

    if( $class->meta->existing_singleton ) {
        return( 1 );
    }
    return( 0 );
}

1;

