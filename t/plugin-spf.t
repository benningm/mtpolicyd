#!perl

use strict;
use warnings;

use Test::More tests => 9;
use Test::Exception;
use Test::MockObject;

use Mail::MtPolicyd::Request;
use Mail::MtPolicyd::Plugin::SPF;

my $p = Mail::MtPolicyd::Plugin::SPF->new(
	name => 'spg',
	enabled => 'on',
	pass_score => -10,
	pass_action => 'passive',
	fail_score => 5,
	fail_action => 'reject',
);

isa_ok($p, 'Mail::MtPolicyd::Plugin::SPF');

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
		'helo_name' => 'saftpresse.bofh-noc.de',
		'client_address' => '88.198.77.182',
		'sender' => 'ich@markusbenning.de',
	},
	session => $session,
	server => $server,
	use_caching => 0,
);

isa_ok( $r, 'Mail::MtPolicyd::Request');

my $result;

lives_ok { $result = $p->run($r); } 'execute request';
is( $result, undef, 'should not match' );
is($session->{'score'}, -10, 'score should be -10');

$r->attributes->{'client_address'} = '192.168.2.1';
lives_ok { $result = $p->run($r); } 'execute request';
isa_ok( $result, 'Mail::MtPolicyd::Plugin::Result' );
like( $result->action, qr/reject SPF validation failed: markusbenning.de: Sender is not authorized by default to use/, 'check action' );
is($session->{'score'}, -5, 'score should be -5');

