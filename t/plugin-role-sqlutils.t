#!perl

use strict;
use warnings;

use Test::More tests => 14;
use Test::Exception;

use Mail::MtPolicyd::SqlConnection;


package Mail::MtPolicyd::Plugin::TestSqlUtils;

use Moose;

extends 'Mail::MtPolicyd::Plugin';
with 'Mail::MtPolicyd::Plugin::Role::SqlUtils';

package main;

import Mail::MtPolicyd::Plugin::TestSqlUtils;

my $sql = Mail::MtPolicyd::Plugin::TestSqlUtils->new(
    name => 'sqlutils-test',
);
isa_ok($sql, 'Mail::MtPolicyd::Plugin::TestSqlUtils');

throws_ok { $sql->init(); } qr/no sql database initialized, but required for plugin sqlutils-test/, 'must die in init() when db unavailable';

# build a fake database with an in-memory SQLite DB
Mail::MtPolicyd::SqlConnection->initialize(
    dsn => 'dbi:SQLite::memory:',
    user => '',
    password => '',
);

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

