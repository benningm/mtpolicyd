#!perl

use strict;
use warnings;

use Test::More tests => 11;
use Test::Exception;
use Test::MockObject;
use Test::Mock::Net::Server::Mail;

use Mail::MtPolicyd::Request;
use Mail::MtPolicyd::Plugin::SMTPVerify;

my $s = Test::Mock::Net::Server::Mail->new;
$s->start_ok;
 
my $p = Mail::MtPolicyd::Plugin::SMTPVerify->new(
	name => 'smtpverify',
  host => $s->bind_address,
  port => $s->port,
  perm_fail_action => "reject %MSG%",
  temp_fail_action => "defer %MSG%",
  has_starttls_score => -5,
  no_starttls_score => 5,
  perm_fail_score => 10,
);

isa_ok($p, 'Mail::MtPolicyd::Plugin::SMTPVerify');

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
		'sender' => 'good-sender@testdomain.tld',
		'recipient' => 'good-rcpt@testdomain.tld',
    'size' => 10240,
	},
	session => $session,
	server => $server,
	use_caching => 0,
);

isa_ok( $r, 'Mail::MtPolicyd::Request');

my $result;

lives_ok { $result = $p->run($r); } 'execute request';
is( $result, undef, 'should not match return an action' );
cmp_ok( $r->session->{'score'}, '==', -5, 'score must be 5');

$r->attributes->{'recipient'} = 'bad-rcpt@testdomain.tld';
lives_ok { $result = $p->run($r); } 'execute request';
isa_ok( $result, 'Mail::MtPolicyd::Plugin::Result' );
cmp_ok( $r->session->{'score'}, '==', 0, 'score must be 0');
like( $result->action, qr/^reject.*address rejected/, 'action' );

$s->stop_ok;

