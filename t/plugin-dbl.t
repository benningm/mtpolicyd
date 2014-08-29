#!perl

use strict;
use warnings;

use Test::More tests => 17;
use Test::Exception;
use Test::MockObject;

use Mail::MtPolicyd::Request;
use Mail::MtPolicyd::Plugin::DBL;

my $blocked = 'abizo.ru';

my $p = Mail::MtPolicyd::Plugin::DBL->new(
	name => 'sh-dbl',
	enabled => 'on',
	uc_enabled => "spamhaus",
	domain => "dbl.spamhaus.org",
	helo_name_score => 1,
	helo_name_mode => 'passive',
	sender_score => 5,
	sender_mode => 'reject',
	reverse_client_name_score => 2.5,
	reverse_client_name_mode => 'reject',
);

isa_ok($p, 'Mail::MtPolicyd::Plugin::DBL');

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
		'reverse_client_name' => 'saftpresse.bofh-noc.de',
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

# in hope that this ip stays "bad"
$r->attributes->{'reverse_client_name'} = "23.19.76.2.$blocked";
lives_ok { $result = $p->run($r); } 'execute request';
isa_ok( $result, 'Mail::MtPolicyd::Plugin::Result', 'should match' );
like( $result->action, qr/reject reverse_client_name rejected \(23.19.76.2.$blocked, \"http:\/\/www.spamhaus.org\/query\/dbl\?domain=$blocked\"\)/, 'should return a blocked header' );

is($session->{'score'}, 2.5, 'score should be 2.5');

$r->attributes->{'sender'} = "bsnobfvqzz\@$blocked";
lives_ok { $result = $p->run($r); } 'execute request';
isa_ok( $result, 'Mail::MtPolicyd::Plugin::Result', 'should match' );
like( $result->action, qr/reject sender rejected \($blocked, \"http:\/\/www.spamhaus.org\/query\/dbl\?domain=$blocked\"\)/, 'should return a reject' );

is($session->{'score'}, 7.5, 'score should be 7.5');

$p->reverse_client_name_mode('passive');
$p->sender_mode('passive');
$r->attributes->{'helo_name'} = "23.81.170.170.$blocked";
lives_ok { $result = $p->run($r); } 'execute request';
is( $result, undef, 'should take no action' );
is($session->{'score'}, 16, 'score should be 16');

# test with per-user/session setting
$p->uc_enabled('spamhaus');
$session->{'spamhaus'} = 'off';
lives_ok { $result = $p->run($r); } 'execute request';
is( $result, undef, 'should do nothing' );

