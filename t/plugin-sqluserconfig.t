#!perl

use strict;
use warnings;

use Test::More tests => 5;
use Test::Exception;
use Test::MockObject;

use Mail::MtPolicyd::ConnectionPool;
use Mail::MtPolicyd::Request;
use Mail::MtPolicyd::Plugin::SqlUserConfig;

use DBI;

my $p = Mail::MtPolicyd::Plugin::SqlUserConfig->new(
	name => 'sqluserconfig-test',
	sql_query => "SELECT config FROM user_config WHERE address=?",
);

isa_ok($p, 'Mail::MtPolicyd::Plugin::SqlUserConfig');

my $session = {
	'_instance' => 'abcd1234',
};

# build a fake database with an in-memory SQLite DB
Mail::MtPolicyd::ConnectionPool->load_connection( 'db', {
  module => 'Sql',
  dsn => 'dbi:SQLite::memory:',
  user => '',
  password => '',
} );
my $dbh = Mail::MtPolicyd::ConnectionPool->get_handle('db');
$dbh->do(
'CREATE TABLE `user_config` (
   `id` INTEGER PRIMARY KEY AUTOINCREMENT,
   `address` varchar(255) DEFAULT NULL,
   `config` TEXT NOT NULL
 )'
);
# insert test data
$dbh->do("INSERT INTO `user_config` VALUES (NULL, 'ich\@markusbenning.de', '{ \"test\": \"bla\" }');");

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
		'recipient' => 'ich@markusbenning.de',
	},
	session => $session,
	server => $server,
);

isa_ok( $r, 'Mail::MtPolicyd::Request');

my $result;

lives_ok { $result = $p->run($r); } 'execute request';
is( $result, undef, 'should not return a result' );

is( $session->{'test'}, 'bla', 'field test should be bla in session');

