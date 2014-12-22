#!perl

use strict;
use warnings;

use Test::More tests => 25;
use Test::Exception;
use Test::MockObject;

use Mail::MtPolicyd::Request;
use Mail::MtPolicyd::Plugin::RBL;

my $p = Mail::MtPolicyd::Plugin::RBL->new(
	name => 'sh-rbl',
	enabled => 'on',
	uc_enabled => "spamhaus",
	mode => 'reject',
	domain => "zen.spamhaus.org",
	score => 5,
);

isa_ok($p, 'Mail::MtPolicyd::Plugin::RBL');

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
		'client_address' => '127.0.0.1',
	},
	session => $session,
	server => $server,
	use_caching => 0,
);

isa_ok( $r, 'Mail::MtPolicyd::Request');

my $result;

lives_ok { $result = $p->run($r); } 'execute request';
is( $result, undef, 'should not match' );

# XBL test address
$r->attributes->{'client_address'} = '127.0.0.4';
lives_ok { $result = $p->run($r); } 'execute request';
isa_ok( $result, 'Mail::MtPolicyd::Plugin::Result', 'should match' );
like( $result->action, qr/reject delivery from 127.0.0.4 rejected \("http:\/\/www.spamhaus.org\/query\/bl\?ip=127.0.0.4"\)/, 'should return a reject action' );

is($session->{'score'}, 5, 'score should be 5');

# test with per-user/session setting
$p->uc_enabled('spamhaus');
$session->{'spamhaus'} = 'off';
lives_ok { $result = $p->run($r); } 'execute request';
is( $result, undef, 'should do nothing' );

$session->{'spamhaus'} = 'on';
lives_ok { $result = $p->run($r); } 'execute request';
isa_ok( $result, 'Mail::MtPolicyd::Plugin::Result', 'should match' );
like( $result->action, qr/reject delivery from 127.0.0.4 rejected \("http:\/\/www.spamhaus.org\/query\/bl\?ip=127.0.0.4"\)/, 'should return a reject action' );
is($session->{'score'}, 10, 'score should be 10');

$p->mode('passive');
$r->use_caching(1);
lives_ok { $result = $p->run($r); } 'execute request';
is( $result, undef, 'should not return an action' );
is($session->{'score'}, 15, 'score should be 15');

# TEST RBLAction
use Mail::MtPolicyd::Plugin::RBLAction;

$p = Mail::MtPolicyd::Plugin::RBLAction->new(
	name => 'sh-rbl-sbl',
	result_from => 'sh-rbl',
	mode => 'reject',
	re_match => '^127\.0\.0\.[23]$', # on SBL?
	score => 5,
);
isa_ok($p, 'Mail::MtPolicyd::Plugin::RBLAction');
lives_ok { $result = $p->run($r); } 'execute request';
is( $result, undef, 'should do nothing' );
is($session->{'score'}, 15, 'score should be 15');

$p->re_match('^127\.0\.0\.[4-7]$'); # on XBL?
$p->name('sh-rbl-xbl');
lives_ok { $result = $p->run($r); } 'execute request';
isa_ok( $result, 'Mail::MtPolicyd::Plugin::Result', 'should match' );
like( $result->action, qr/reject delivery from 127.0.0.4 rejected \("http:\/\/www.spamhaus.org\/query\/bl\?ip=127.0.0.4"\)/, 'should return a reject action' );
is($session->{'score'}, 20, 'score should be 20');

