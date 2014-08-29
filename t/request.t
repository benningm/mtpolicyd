#!perl

use strict;
use warnings;

use Test::More tests => 4;
use Test::MockObject;

use Mail::MtPolicyd::Request;

my $session = { '_instance' => 'abcd1234' };

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

is($r->type, 'smtpd_access_policy', 'check ->type');
is($r->attr('queue_id'), '8045F2AB23', 'check ->attr');

can_ok($r, 'log', 'new_from_fh');

