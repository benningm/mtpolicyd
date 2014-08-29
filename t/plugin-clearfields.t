#!perl

use strict;
use warnings;

use Test::More tests => 12;
use Test::Exception;
use Test::MockObject;

use Mail::MtPolicyd::Request;
use Mail::MtPolicyd::Plugin::ClearFields;

my $c = Mail::MtPolicyd::Plugin::ClearFields->new(
	name => 'test',
	fields => 'zumsel',
	fields_prefix => 'sh_zen,sh_dbl',
);

isa_ok($c, 'Mail::MtPolicyd::Plugin::ClearFields');

my $session = {
	'_instance' => 'abcd1234',
	'zumsel' => 'zumsel',
	'sh_zen' => 'zumsel',
	'sh_zen_XBL' => 'zumsel',
	'sh_zen_SBL' => 'zumsel',
	'sh_dbl_helo' => 'zumsel',
	'sh_dbl' => 'zumsel',
	'bla' => 'zumsel',
	'blub' => 'zumsel',
};

# fake a Server object
my $server = Test::MockObject->new;
$server->set_isa('Net::Server');
$server->mock( 'log',
    sub { my ( $self, $level, $message ) = @_; print '# LOG('.$level.'): '.$message."\n" } );

my $r = Mail::MtPolicyd::Request->new(
	attributes => {
		'instance' => 'abcd1234',
	},
	session => $session,
	server => $server,
);

isa_ok( $r, 'Mail::MtPolicyd::Request');

my $result;

lives_ok { $result = $c->run($r); } 'execute request';
is( $result, undef, 'should not match' );

is( $session->{'bla'}, 'zumsel', 'check result' );
is( $session->{'blub'}, 'zumsel', 'check result' );

is( $session->{'zumsel'}, undef, 'check result' );

is( $session->{'sh_zen'}, undef, 'check result' );
is( $session->{'sh_zen_XBL'}, undef, 'check result' );
is( $session->{'sh_zen_SBL'}, undef, 'check result' );

is( $session->{'sh_dbl'}, undef, 'check result' );
is( $session->{'sh_dbl_helo'}, undef, 'check result' );

