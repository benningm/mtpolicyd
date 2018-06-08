package Mail::MtPolicyd::Plugin::Greylist::AWL::Sql;

use Moose;

# ABSTRACT: backend for SQL greylisting awl storage
# VERSION

use Time::Seconds;

extends 'Mail::MtPolicyd::Plugin::Greylist::AWL::Base';

with 'Mail::MtPolicyd::Role::Connection' => {
  name => 'db',
  type => 'Sql',
};

with 'Mail::MtPolicyd::Plugin::Role::SqlUtils';

has 'autowl_table' => ( is => 'rw', isa => 'Str', default => 'autowl' );

sub get {
	my ( $self, $sender_domain, $client_ip ) = @_;
	my $sql = sprintf("SELECT * FROM %s WHERE sender_domain=? AND client_ip=?",
       		$self->autowl_table );
	my $row = $self->execute_sql($sql, $sender_domain, $client_ip)->fetchrow_hashref;
  return unless defined $row;

	my $last_seen = $row->{'last_seen'};
	my $expires = $last_seen + ( ONE_DAY * $self->autowl_expire_days );
  my $now = Time::Piece->new->epoch;
	if( $now > $expires ) {
		return;
	}

  return $row->{'count'};
}

sub create {
	my ( $self, $sender_domain, $client_ip ) = @_;
    my $timestamp = 
	my $sql = sprintf("INSERT INTO %s VALUES(NULL, ?, ?, 1, %d)",
       		$self->autowl_table, Time::Piece->new->epoch );
	$self->execute_sql($sql, $sender_domain, $client_ip);
	return;
}

sub incr {
	my ( $self, $sender_domain, $client_ip ) = @_;
	my $sql = sprintf(
        "UPDATE %s SET count=count+1, last_seen=%d WHERE sender_domain=? AND client_ip=?",
        $self->autowl_table,
        Time::Piece->new->epoch );
	$self->execute_sql($sql, $sender_domain, $client_ip);
	return;
}

sub remove {
	my ( $self, $sender_domain, $client_ip ) = @_;
	my $sql = sprintf("DELETE FROM %s WHERE sender_domain=? AND client_ip=?",
       		$self->autowl_table );
	$self->execute_sql($sql, $sender_domain, $client_ip);
	return;
}

sub expire {
	my ( $self ) = @_;
	my $timeout = ONE_DAY * $self->autowl_expire_days;
  my $now = Time::Piece->new->epoch;
	my $sql = sprintf("DELETE FROM %s WHERE ? > last_seen + ?",
    $self->autowl_table );
	$self->execute_sql($sql, $now, $timeout);
	return;
}

sub init {
  my $self = shift;
  $self->check_sql_tables( %{$self->_table_definitions} );
}

has '_table_definitions' => ( is => 'ro', isa => 'HashRef', lazy => 1,
    default => sub { {
        'autowl' => {
            'mysql' => 'CREATE TABLE %TABLE_NAME% (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `sender_domain` VARCHAR(255) NOT NULL,
    `client_ip` VARCHAR(39) NOT NULL,
    `count` INT UNSIGNED NOT NULL,
    `last_seen` INT UNSIGNED NOT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `domain_ip` (`client_ip`, `sender_domain`),
    KEY(`client_ip`),
    KEY(`sender_domain`)
  ) ENGINE=%MYSQL_ENGINE%  DEFAULT CHARSET=latin1',
            'SQLite' => 'CREATE TABLE %TABLE_NAME% (
    `id` INTEGER PRIMARY KEY AUTOINCREMENT,
    `sender_domain` VARCHAR(255) NOT NULL,
    `client_ip` VARCHAR(39) NOT NULL,
    `count` INT UNSIGNED NOT NULL,
    `last_seen` INTEGER NOT NULL
)',
        },
    } },
);

1;

