#!perl

use strict;
use warnings;

use Test::More tests => 12;
use Test::Exception;
use Test::MockObject;

use Mail::MtPolicyd::Request;
use Mail::MtPolicyd::Plugin::SaAwlLookup;

my $p = Mail::MtPolicyd::Plugin::SaAwlLookup->new(
	name => 'sa-awl',
	enabled => 'on',
    db_file => '/dev/null',
    _awl => {
        'good@mtpolicyd.org|ip=12.34|totscore' => 20,
        'good@mtpolicyd.org|ip=12.34' => 100,
        'bad@mtpolicyd.org|ip=12.34|totscore' => 2000,
        'bad@mtpolicyd.org|ip=12.34' => 100,
        'low@mtpolicyd.org|ip=12.34' => 1,
        'low@mtpolicyd.org|ip=12.34' => 1,
    },
);

isa_ok($p, 'Mail::MtPolicyd::Plugin::SaAwlLookup');

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
is( $result, undef, 'should never match' );

cmp_ok( $p->truncate_ip('12.34.56.78'),
    'eq', '12.34', 'ipv4 must be truncated correctly');
cmp_ok( $p->truncate_ip('2a01:4f8:d12:242::2'),
    'eq', '2A01:04F8:0D12::', 'ipv6 must be truncated correctly');

lives_ok { $result = $p->run($r); } 'execute request';
is( $result, undef, 'should never match' );

$r->attributes->{'sender'} = 'bad@mtpolicyd.org';
$r->use_caching(1);
lives_ok { $result = $p->run($r); } 'execute request';

ok( defined $session->{'sa-awl-sa-awl-result'}, 'result must be stored in session');

my $reputation = $session->{'sa-awl-sa-awl-result'};
cmp_ok( $reputation->[0], '==', 100, 'count in reputation must be 100');
cmp_ok( $reputation->[1], '==', 20, 'score in reputation must be 20');

