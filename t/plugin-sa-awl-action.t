#!perl

use strict;
use warnings;

use Test::More tests => 18;
use Test::Exception;
use Test::MockObject;

use Mail::MtPolicyd::Request;
use Mail::MtPolicyd::Plugin::SaAwlLookup;
use Mail::MtPolicyd::Plugin::SaAwlAction;

my $p = Mail::MtPolicyd::Plugin::SaAwlAction->new(
	name => 'sa-awl-test',
	enabled => 'on',
    result_from => 'amavis',
);

isa_ok($p, 'Mail::MtPolicyd::Plugin::SaAwlAction');

my $session = {
	'_instance' => 'abcd1234',
    'sa-awl-amavis-result' => [ 100, 1.4 ],
};

# fake a Server object
my $server = Test::MockObject->new;
$server->set_isa('Net::Server');
$server->mock( 'log',
    sub { my ( $self, $level, $message ) = @_; print '# LOG('.$level.'): '.$message."\n" } );

my $r = Mail::MtPolicyd::Request->new(
	attributes => {
		'instance' => 'abcd1234',
		'client_address' => '12.34.56.78',
		'sender' => 'good@mtpolicyd.org',
	},
	session => $session,
	server => $server,
	use_caching => 0,
);

isa_ok( $r, 'Mail::MtPolicyd::Request');

my $result;

lives_ok { $result = $p->run($r); } 'execute request';
is( $result, undef, 'should not match' );

$session->{'sa-awl-amavis-result'} = [100, 20];
lives_ok { $result = $p->run($r); } 'execute request';
isa_ok( $result, 'Mail::MtPolicyd::Plugin::Result', 'must match' );
like( $result->action, qr/^reject/, 'must return an reject action' );

$p->mode('passive');
$p->score_factor(0.5);
lives_ok { $result = $p->run($r); } 'execute request';
is( $result, undef, 'should never match (mode passive)' );
cmp_ok( $session->{'score'}, '==', 10, 'score must be 10 (20 * factor 0.5)');

$session->{'score'} = 0;
$p->score_factor(undef);
$p->score(5);
lives_ok { $result = $p->run($r); } 'execute request';
is( $result, undef, 'should never match (mode passive)' );
cmp_ok( $session->{'score'}, '==', 5, 'score must be 5');

$p->mode('accept');
$p->threshold(-1);
$p->match('lt');
lives_ok { $result = $p->run($r); } 'execute request';
is( $result, undef, 'should not match' );

$session->{'sa-awl-amavis-result'} = [100, -5];
lives_ok { $result = $p->run($r); } 'execute request';
isa_ok( $result, 'Mail::MtPolicyd::Plugin::Result', 'must match' );
cmp_ok( $result->action, 'eq', 'dunno', 'action must be dunno' );

