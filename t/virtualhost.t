#!perl

use strict;
use warnings;

use Test::More tests => 5;
use Test::Exception;
use Test::MockObject;

use Mail::MtPolicyd::Request;
use Mail::MtPolicyd::VirtualHost;
use Mail::MtPolicyd::PluginChain;
use Mail::MtPolicyd::Plugin::Action;

my $vhost = Mail::MtPolicyd::VirtualHost->new(
	port => 12345,
	name => "test-host",
	chain => Mail::MtPolicyd::PluginChain->new(
		vhost_name => 'test-host',
		plugins => [
			Mail::MtPolicyd::Plugin::Action->new(
				name => 'test-action-1',
				action => 'reject',
			),
			# check order
			Mail::MtPolicyd::Plugin::Action->new(
				name => 'test-action-2',
				action => 'should not happen',
			),
		],
	),
);

isa_ok($vhost, 'Mail::MtPolicyd::VirtualHost');

my $session = { '_instance' => 'abcd1234' };

# fake a Server object
my $server = Test::MockObject->new;
$server->set_isa('Net::Server');
$server->set_true('log');

my $r = Mail::MtPolicyd::Request->new(
	attributes => {
		'instance' => 'abcd1234',
		'request' => 'smtpd_access_policy',
		'protocol_state' => 'RCPT',
		'protocol_name' => 'SMTP',
		'helo_name' => 'some.domain.tld',
		'queue_id' => '8045F2AB23',
		'sender' => 'foo@bar.tld',
		'recipient' => 'bar@foo.tld',
		'recipient_count' => '0',
		'client_address' => '1.2.3.4',
		'client_name' => 'another.domain.tld',
		'reverse_client_name' => 'another.domain.tld',
	},
	session => $session,
	server => $server,
);

isa_ok( $r, 'Mail::MtPolicyd::Request');

my $result;

lives_ok { $result = $vhost->run($r); } 'execute request';

isa_ok( $result, 'Mail::MtPolicyd::Result' );

is( $result->as_policyd_response, "action=reject\n\n", 'check result' );

