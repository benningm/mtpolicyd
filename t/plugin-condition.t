#!perl

use strict;
use warnings;

use Test::More tests => 19;
use Test::Exception;
use Test::MockObject;

use Mail::MtPolicyd::Request;
use Mail::MtPolicyd::Plugin::Condition;

my $c = Mail::MtPolicyd::Plugin::Condition->new(
	name => 'greylist',
	key => 's:greylisting',
	match => 'on',
	action => 'postgrey_users',
);

isa_ok($c, 'Mail::MtPolicyd::Plugin::Condition');

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
    'queue_id' => '4561B3D95D8B',
	},
	session => $session,
	server => $server,
);

isa_ok( $r, 'Mail::MtPolicyd::Request');

my $result;

lives_ok { $result = $c->run($r); } 'execute request';
is( $result, undef, 'should not match' );

$session->{'greylisting'} = 'off';
lives_ok { $result = $c->run($r); } 'execute request';
is( $result, undef, 'should not match' );

$session->{'greylisting'} = 'on';
lives_ok { $result = $c->run($r); } 'execute request';
isa_ok( $result, 'Mail::MtPolicyd::Plugin::Result', 'should match' );

is( $result->action, 'postgrey_users', 'check result' );
is( $result->abort, 1, 'check result' );

$c->action( undef );
$c->Plugin( { 'test' => { module => 'Action', action => 'zumsel' } } );

lives_ok { ( $result ) = $c->run($r); } 'execute request';
isa_ok( $result, 'Mail::MtPolicyd::Plugin::Result', 'should match' );
is( $result->action, 'zumsel', 'check result' );
is( $result->abort, 1, 'check result' );

# use a request attribute
$c = Mail::MtPolicyd::Plugin::Condition->new(
	name => 'by_queueid',
	key => 'r:queue_id',
	match => '4561B3D95D8B',
	action => 'reject',
);
lives_ok { ( $result ) = $c->run($r); } 'execute by_queueid request';
isa_ok( $result, 'Mail::MtPolicyd::Plugin::Result', 'check must match' );
is( $result->action, 'reject', 'check must return reject action' );

# test invert option
$c->invert(1);
lives_ok { ( $result ) = $c->run($r); } 'execute by_queueid request';
is( $result, undef, 'must not match when inverted' );

