#!perl

use strict;
use warnings;

use Test::More;
use Test::Exception;
use Test::MockObject;

use Mail::MtPolicyd::Request;
use Mail::MtPolicyd::Plugin::CtIpRep;

use LWP::UserAgent;

eval {
        my $agent = LWP::UserAgent->new;
        my $response = $agent->get('http://localhost:8080/');
	if( ! defined $response || ! defined $response->code ) {
		die('unknown response');
	}
        if( $response->code =~ m/^5/ ) {
                die('no server on http://localhost:8080/');
        }
        if( ! defined $response->server ||  $response->server !~ m/^CTCFC/ ) {
		my $vendor = defined $response->server ? $response->server : 'none';
                die('wrong server vendor ('.$vendor.')');
        }
};
if( $@ ) {
        plan skip_all => 'no ctipd found ('.$@.')';
}

plan tests => 16;

my $p = Mail::MtPolicyd::Plugin::CtIpRep->new(
	name => 'commtouch',
	enabled => 'on',
	tempfail_score => 2.5,
	permfail_score => 5,
	tempfail_mode => 'passive', 
	permfail_mode => 'reject',
);

isa_ok($p, 'Mail::MtPolicyd::Plugin::CtIpRep');

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

# in hope that this ip stays "bad"
$r->attributes->{'client_address'} = '201.216.207.129';
lives_ok { $result = $p->run($r); } 'execute request';
isa_ok( $result, 'Mail::MtPolicyd::Plugin::Result', 'should match' );
like( $result->action, qr/reject 550 delivery from 201.216.207.129 is rejected./, 'should return a reject' );
is($session->{'score'}, 5, 'score should be 5');

# test with per-user/session setting
$p->uc_enabled('ctrep');
$session->{'ctrep'} = 'off';
lives_ok { $result = $p->run($r); } 'execute request';
is( $result, undef, 'should do nothing' );

$p->uc_enabled(undef);
$p->permfail_mode('passive');
$p->tempfail_mode('passive');
lives_ok { $result = $p->run($r); } 'execute request';
is( $result, undef, 'should do nothing' );
is($session->{'score'}, 10, 'score should be 10');

$p->permfail_mode('defer');
lives_ok { $result = $p->run($r); } 'execute request';
like( $result->action, qr/defer 450 delivery from 201.216.207.129 is deferred,repeatedly. Send again or check at http:\/\/www.commtouch.com\/Site\/Resources\/Check_IP_Reputation.asp. Reference code: tid=.*/, 'should return a reject' );
is($session->{'score'}, 15, 'score should be 15');
