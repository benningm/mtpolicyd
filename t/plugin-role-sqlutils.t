#!perl

use strict;
use warnings;

use Test::More tests => 23;
use Test::Exception;

use Mail::MtPolicyd::ConnectionPool;


package Mail::MtPolicyd::Plugin::TestSqlUtils;

use Moose;

extends 'Mail::MtPolicyd::Plugin';
with 'Mail::MtPolicyd::Role::Connection' => {
  name => 'db',
  type => 'Sql',
};
with 'Mail::MtPolicyd::Plugin::Role::SqlUtils';

package Mail::MtPolicyd::Plugin::TestSqlUtilsMySQL;

use Moose;
use Test::MockObject;

extends 'Mail::MtPolicyd::Plugin';
has '_db_handle' => (
  is => 'ro',
  default => sub {
    my $dbh = Test::MockObject->new();
    $dbh->mock( 'quote_identifier', sub {
      my $self = shift;
      return shift;
    } );
    $dbh->{'Driver'} = {'Name' => 'mysql'};
    $dbh->mock( 'do', sub {
      my $self = shift;
      $self->{'do_sql'} = shift;
      return;
    } );
    return $dbh;
  },
);
with 'Mail::MtPolicyd::Plugin::Role::SqlUtils';

package main;

import Mail::MtPolicyd::Plugin::TestSqlUtils;
import Mail::MtPolicyd::Plugin::TestSqlUtilsMySQL;

my $sql = Mail::MtPolicyd::Plugin::TestSqlUtils->new(
    name => 'sqlutils-test',
);
isa_ok($sql, 'Mail::MtPolicyd::Plugin::TestSqlUtils');

throws_ok { $sql->init(); } qr/no connection db configured!/, 'must die in init() when db unavailable';

# build a fake database with an in-memory SQLite DB
Mail::MtPolicyd::ConnectionPool->load_connection( 'db', {
  module => 'Sql',
  dsn => 'dbi:SQLite::memory:',
  user => '',
  password => '',
} );

lives_ok { $sql->init(); } 'init() when db available';

throws_ok {
    $sql->create_sql_table('table', {} );
} qr/no data definition for table/, 'must fail without a definition for driver';

throws_ok {
    $sql->create_sql_table('table', { '*' => 'bla' } );
} qr/syntax error/, 'must use * CREATE and fail with syntax error';

throws_ok {
    $sql->create_sql_table('table', { 'SQLite' => 'blub', '*' => 'bla' } );
} qr/blub/, 'must use SQLite CREATE and fail with syntax error';

ok( ! $sql->sql_table_exists('zumsel'), 'table does not exist' );

lives_ok {
    $sql->create_sql_table('zumsel', {
        'SQLite' => 'CREATE TABLE %TABLE_NAME% (
 `id` INTEGER PRIMARY KEY AUTOINCREMENT,
 `client_ip` varchar(255) DEFAULT NULL
)'
     } );
} 'must create table zumsel';

ok( $sql->sql_table_exists('zumsel'), 'table must exist' );

lives_ok {
    $sql->check_sql_tables(
        'zumsel' => { '*' => 'bla' },
    );
} 'must not try to create table if it already exists';

throws_ok {
    $sql->check_sql_tables(
        'zumsel' => { '*' => 'blub' },
        'bla' => { '*' => 'bla' },
    );
} qr/near "bla": syntax error/, 'must try to create table if it does not exist and fail';

my $sth;
lives_ok {
    $sth = $sql->execute_sql('SELECT 1');
} 'execute_sql must live';

isa_ok( $sth, 'DBI::st');

throws_ok {
    $sth = $sql->execute_sql('bla');
} qr/syntax error/, 'execute_sql must die on error';

#
# MySQL settings tests
#

$sql = Mail::MtPolicyd::Plugin::TestSqlUtilsMySQL->new(
    name => 'sqlutils-mysql-test',
);
isa_ok($sql, 'Mail::MtPolicyd::Plugin::TestSqlUtilsMySQL');

lives_ok { $sql->init(); } 'init() when db available';

lives_ok {
    $sql->create_sql_table('zumsel', {
        'mysql' => 'CREATE TABLE %TABLE_NAME% (
 `id` INTEGER PRIMARY KEY AUTOINCREMENT,
 `client_ip` varchar(255) DEFAULT NULL
) ENGINE=%MYSQL_ENGINE%  DEFAULT CHARSET=latin1'
     } );
} 'should not fail (mocked)';

like($sql->_db_handle->{'do_sql'}, qr/CREATE TABLE zumsel/, 'table name must be set');
like($sql->_db_handle->{'do_sql'}, qr/ENGINE=MyISAM/, 'engine must be set to MyISAM (default)');

lives_ok {
    $sql->mysql_engine('InnoDB');
} 'setting mysql_engine must live';


lives_ok {
    $sql->create_sql_table('blablub', {
        'mysql' => 'CREATE TABLE %TABLE_NAME% (
 `id` INTEGER PRIMARY KEY AUTOINCREMENT,
 `client_ip` varchar(255) DEFAULT NULL
) ENGINE=%MYSQL_ENGINE%  DEFAULT CHARSET=latin1'
     } );
} 'should not fail (mocked)';

like($sql->_db_handle->{'do_sql'}, qr/CREATE TABLE blablub/, 'table name must be set');
like($sql->_db_handle->{'do_sql'}, qr/ENGINE=InnoDB/, 'engine must be set to InnoDB');

