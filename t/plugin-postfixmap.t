#!perl

use strict;
use warnings;

use Test::More tests => 25;
use Test::Exception;
use Test::MockObject;

use Mail::MtPolicyd::Request;
use Mail::MtPolicyd::Plugin::PostfixMap;

use DBI;

my $p = Mail::MtPolicyd::Plugin::PostfixMap->new(
	name => 'postmap',
	db_file => "t-data/plugin-postfixmap-postmap.db",
	match_action => 'dunno',
	score => 5,
);

isa_ok($p, 'Mail::MtPolicyd::Plugin::PostfixMap');

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

$r->attributes->{'client_address'} = '123.123.123.123';
lives_ok { $result = $p->run($r); } 'execute request';
isa_ok( $result, 'Mail::MtPolicyd::Plugin::Result', 'should match' );
is( $result->action, "dunno", 'must return action=dunno' );

is($session->{'score'}, 5, 'score should be 5');

$r->attributes->{'client_address'} = '123.123.124.1';
lives_ok { $result = $p->run($r); } 'execute request';
isa_ok( $result, 'Mail::MtPolicyd::Plugin::Result', 'should match' );
is( $result->action, "dunno", 'must return action=dunno' );

$r->attributes->{'client_address'} = 'fe80::250:56ff:fe85:56f5';
lives_ok { $result = $p->run($r); } 'execute request';
isa_ok( $result, 'Mail::MtPolicyd::Plugin::Result', 'should match' );
is( $result->action, "dunno", 'must return action=dunno' );

$r->attributes->{'client_address'} = 'fe81::250:56ff:eeee:ffff';
lives_ok { $result = $p->run($r); } 'execute request';
isa_ok( $result, 'Mail::MtPolicyd::Plugin::Result', 'should match' );
is( $result->action, "dunno", 'must return action=dunno' );

$p->enabled('off');
lives_ok { $result = $p->run($r); } 'execute request';
is( $result, undef, 'should do nothing' );

$p->uc_enabled('list');
$session->{'list'} = 'on';
lives_ok { $result = $p->run($r); } 'execute request';
isa_ok( $result, 'Mail::MtPolicyd::Plugin::Result', 'should match' );
is( $result->action, "dunno", 'must return action=dunno' );

$r->attributes->{'client_address'} = '192.168.0.1';
$p->not_match_action('reject no access granted');
lives_ok { $result = $p->run($r); } 'execute request';
isa_ok( $result, 'Mail::MtPolicyd::Plugin::Result', 'should match' );
is( $result->action, "reject no access granted", 'must return action=reject no access granted' );

