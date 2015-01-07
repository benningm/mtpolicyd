#!perl

use strict;
use warnings;

use Test::More tests => 65;
use Test::Exception;
use Test::MockObject;

use Mail::MtPolicyd::Request;
use Mail::MtPolicyd::SqlConnection;
use Mail::MtPolicyd::Plugin::Accounting;
use Mail::MtPolicyd::Plugin::Quota;

use DBI;

my $p = Mail::MtPolicyd::Plugin::Accounting->new(
	name => 'acct_test',
    fields => 'client_address,sender,recipient',
);
isa_ok($p, 'Mail::MtPolicyd::Plugin::Accounting');

# build a fake database with an in-memory SQLite DB
Mail::MtPolicyd::SqlConnection->initialize(
    dsn => 'dbi:SQLite::memory:',
    user => '',
    password => '',
);

lives_ok {
    $p->init();
} 'plugin initialization';

my $session = {
	'_instance' => 'abcd1234',
};

# fake a Server object
my $server = Test::MockObject->new;
$server->set_isa('Net::Server');
$server->mock( 'log',
    sub { my ( $self, $level, $message ) = @_; print '# LOG('.$level.'): '.$message."\n" } );

my $r = Mail::MtPolicyd::Request->new(
    attributes => {
        'instance' => 'abcd1234',
        'client_address' => '192.168.0.1',
        'sender' => 'sender@testdomain.de',
        'recipient' => 'newrcpt@mydomain.de',
        'size' => '13371',
        'recipient_count' => '0',
    },
    session => $session,
    server => $server,
    use_caching => 0,
);
isa_ok( $r, 'Mail::MtPolicyd::Request');

sub cmp_table_numrows_ok {
    my ( $table, $op, $rows, $desc ) = @_;
    my $dbh = Mail::MtPolicyd::SqlConnection->instance->dbh;
    my $table_name = $dbh->quote_identifier( $table );
    my $sql = "SELECT * FROM $table_name";
    my $sth = $dbh->prepare( $sql );
    $sth->execute;
    $sth->fetchall_arrayref;
    return cmp_ok( $sth->rows, $op, $rows, $desc);
}

sub cmp_table_value_ok {
    my ( $table, $key, $field, $op, $count ) = @_;
    my $dbh = Mail::MtPolicyd::SqlConnection->instance->dbh;

    my $table_name = $dbh->quote_identifier( $table );
    my $field_name = $dbh->quote_identifier( $field );
    my $key_name = $dbh->quote_identifier('key');
    my $key_value = $dbh->quote($key);
    my $sql = "SELECT $field_name FROM $table_name WHERE $key_name=$key_value";

    my $sth = $dbh->prepare( $sql );
    $sth->execute;
    my $row = $sth->fetchrow_arrayref;

    my $desc = "counter $field in table $table for $key";
    return cmp_ok( $row->[0], $op, $count, $desc);
}

my $result;
lives_ok { $result = $p->run($r); } 'execute request';
ok( ! defined $result, 'should never return something' );

cmp_table_numrows_ok('acct_client_address', '==', 1, 'table must have 1 row');
cmp_table_numrows_ok('acct_sender', '==', 1, 'table must have 1 row');
cmp_table_numrows_ok('acct_recipient', '==', 1, 'table must have 1 row');

foreach my $cnt (1..10) {
    lives_ok { $result = $p->run($r); } 'execute request '.$cnt;
}

cmp_table_numrows_ok('acct_client_address', '==', 1, 'table must have 1 row');
cmp_table_numrows_ok('acct_sender', '==', 1, 'table must have 1 row');
cmp_table_numrows_ok('acct_recipient', '==', 1, 'table must have 1 row');

foreach my $cnt (1..10) {
    $r->attributes->{'client_address'} = "192.168.1.$cnt";
    lives_ok { $result = $p->run($r); } 'execute request for client_address '.$cnt;
}

cmp_table_numrows_ok('acct_client_address', '==', 11, 'table must have 1 row');
cmp_table_numrows_ok('acct_sender', '==', 1, 'table must have 1 row');
cmp_table_numrows_ok('acct_recipient', '==', 1, 'table must have 1 row');

$r->attributes->{'client_address'} = '192.168.2.1';
$r->attributes->{'recipient_count'} = '10';
foreach my $cnt (1..10) {
    $r->attributes->{'sender'} = 'sender'.$cnt.'@testdomain.de';
    lives_ok { $result = $p->run($r); } 'execute request for sender '.$cnt;
}

cmp_table_numrows_ok('acct_client_address', '==', 12, 'table must have 12 rows');
cmp_table_numrows_ok('acct_sender', '==', 11, 'table must have 11 rows');
cmp_table_numrows_ok('acct_recipient', '==', 1, 'table must have 1 row');

# now check some counters

cmp_table_value_ok('acct_client_address', '192.168.0.1', 'count', '==', '11');
cmp_table_value_ok('acct_client_address', '192.168.0.1', 'count_rcpt', '==', '11');
cmp_table_value_ok('acct_client_address', '192.168.0.1', 'size', '==', '147081');
cmp_table_value_ok('acct_client_address', '192.168.0.1', 'size_rcpt', '==', '147081');

cmp_table_value_ok('acct_client_address', '192.168.1.1', 'count', '==', '1');
cmp_table_value_ok('acct_client_address', '192.168.1.1', 'count_rcpt', '==', '1');
cmp_table_value_ok('acct_client_address', '192.168.1.1', 'size', '==', '13371');
cmp_table_value_ok('acct_client_address', '192.168.1.1', 'size_rcpt', '==', '13371');

cmp_table_value_ok('acct_client_address', '192.168.2.1', 'count', '==', '10');
cmp_table_value_ok('acct_client_address', '192.168.2.1', 'count_rcpt', '==', '100');
cmp_table_value_ok('acct_client_address', '192.168.2.1', 'size', '==', '133710');
cmp_table_value_ok('acct_client_address', '192.168.2.1', 'size_rcpt', '==', '1337100');

# Plugin::Quota checks

$p = Mail::MtPolicyd::Plugin::Quota->new(
	name => 'quota_test',
    field => 'client_address',
    metric => 'count',
    threshold => 1000,
);
isa_ok($p, 'Mail::MtPolicyd::Plugin::Quota');

$r->attributes->{'client_address'} = '192.168.0.1';

lives_ok { $result = $p->run($r); } 'execute request';
is( $result, undef, 'should not match' );

$p->threshold(11);
lives_ok { $result = $p->run($r); } 'execute request';
isa_ok( $result, 'Mail::MtPolicyd::Plugin::Result', 'should match' );
cmp_ok( $result->action, 'eq', 'defer smtp traffic quota has been exceeded', 'check action');

