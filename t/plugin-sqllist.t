#!perl

use strict;
use warnings;

use Test::More tests => 16;
use Test::Exception;
use Test::MockObject;

use Mail::MtPolicyd::Request;
use Mail::MtPolicyd::SqlConnection;
use Mail::MtPolicyd::Plugin::SqlList;

use DBI;

my $p = Mail::MtPolicyd::Plugin::SqlList->new(
	name => 'mylist',
	sql_query => "SELECT client_ip FROM list WHERE client_ip = ?",
	match_action => 'dunno',
	score => 5,
);

isa_ok($p, 'Mail::MtPolicyd::Plugin::SqlList');

my $session = {
	'_instance' => 'abcd1234',
};

# build a fake database with an in-memory SQLite DB
Mail::MtPolicyd::SqlConnection->initialize(
    dsn => 'dbi:SQLite::memory:',
    user => '',
    password => '',
);
my $dbh = Mail::MtPolicyd::SqlConnection->dbh;
$dbh->do(
'CREATE TABLE `list` (
   `id` INTEGER PRIMARY KEY AUTOINCREMENT,
   `client_ip` varchar(255) DEFAULT NULL
 )'
);
# insert test data
$dbh->do("INSERT INTO `list` VALUES (NULL, '192.168.0.1');");

# fake a Server object
my $server = Test::MockObject->new;
$server->set_isa('Net::Server');
$server->mock( 'log',
    sub { my ( $self, $level, $message ) = @_; print '# LOG('.$level.'): '.$message."\n" } );
$server->mock( 'get_dbh',
    sub { return $dbh; } );

my $r = Mail::MtPolicyd::Request->new(
	attributes => {
		'instance' => 'abcd1234',
		'client_address' => '192.168.0.0',
	},
	session => $session,
	server => $server,
	use_caching => 0,
);

isa_ok( $r, 'Mail::MtPolicyd::Request');

my $result;

lives_ok { $result = $p->run($r); } 'execute request';
is( $result, undef, 'should not return a result' );

$r->attributes->{'client_address'} = '192.168.0.1';
lives_ok { $result = $p->run($r); } 'execute request';
isa_ok( $result, 'Mail::MtPolicyd::Plugin::Result', 'should match' );
is( $result->action, "dunno", 'must return action=dunno' );

is($session->{'score'}, 5, 'score should be 5');

$p->enabled('off');
lives_ok { $result = $p->run($r); } 'execute request';
is( $result, undef, 'should do nothing' );

$p->uc_enabled('list');
$session->{'list'} = 'on';
lives_ok { $result = $p->run($r); } 'execute request';
isa_ok( $result, 'Mail::MtPolicyd::Plugin::Result', 'should match' );
is( $result->action, "dunno", 'must return action=dunno' );

$r->attributes->{'client_address'} = '192.168.0.0';
$p->not_match_action('reject no access granted');
lives_ok { $result = $p->run($r); } 'execute request';
isa_ok( $result, 'Mail::MtPolicyd::Plugin::Result', 'should match' );
is( $result->action, "reject no access granted", 'must return action=reject no access granted' );

