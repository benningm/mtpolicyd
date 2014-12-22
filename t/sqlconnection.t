#!perl

use strict;
use warnings;

use Test::More tests => 7;
use Test::Exception;

use Mail::MtPolicyd::SqlConnection;

ok( ! Mail::MtPolicyd::SqlConnection->is_initialized, 'must be uninitialized');

dies_ok {
    Mail::MtPolicyd::SqlConnection->dbh;
} 'accessing dbh must die if uninitialized';

# build a fake database with an in-memory SQLite DB
Mail::MtPolicyd::SqlConnection->initialize(
    dsn => 'dbi:SQLite::memory:',
    user => '',
    password => '',
);
isa_ok( Mail::MtPolicyd::SqlConnection->instance, 'Mail::MtPolicyd::SqlConnection');
ok( Mail::MtPolicyd::SqlConnection->is_initialized, 'must be initialized');

my $dbh = Mail::MtPolicyd::SqlConnection->dbh;
isa_ok( $dbh, 'DBI::db');

lives_ok {
    $dbh->do(
    'CREATE TABLE `list` (
       `id` INTEGER PRIMARY KEY AUTOINCREMENT,
       `client_ip` varchar(255) DEFAULT NULL
     )'
    );
    $dbh->do("INSERT INTO `list` VALUES (NULL, '192.168.0.1');");
} 'test some valid sql';

throws_ok { $dbh->do('zumsel') } qr/syntax error/, 'must die on errors';

