#!perl

use strict;
use warnings;

use Test::More tests => 11;
use Test::Exception;
use Test::MockObject;

use Mail::MtPolicyd::Request;
use Mail::MtPolicyd::Plugin::RegexList;

my $c = Mail::MtPolicyd::Plugin::RegexList->new(
	name => 'regex-whitelist',
	key => 'r:client_name',
  regex => [
    '^mail-[a-z][a-z]0-f[0-9]*\.google\.com$',
    '\.bofh-noc\.de$'
  ],
	action => 'accept',
);

isa_ok($c, 'Mail::MtPolicyd::Plugin::RegexList');

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
  use_caching => 0,
);

isa_ok( $r, 'Mail::MtPolicyd::Request');

my $result;

lives_ok { $result = $c->run($r); } 'execute request';
is( $result, undef, 'should not match' );

$r->attributes->{'client_name'} = 'zumsel.blablub.com';
lives_ok { $result = $c->run($r); } 'execute request';
is( $result, undef, 'should not match' );

$r->attributes->{'client_name'} = 'zumsel.bofh-noc.de';
lives_ok { $result = $c->run($r); } 'execute request';
isa_ok( $result, 'Mail::MtPolicyd::Plugin::Result', 'should match' );

is( $result->action, 'accept', 'check result' );
is( $result->abort, 1, 'check result' );

lives_ok {
  $c = Mail::MtPolicyd::Plugin::RegexList->new(
    name => 'regex-whitelist',
    key => 'r:client_name',
    regex => '\.bofh-noc\.de$',
    action => 'accept',
  );
} 'initialization with scalar regex';

