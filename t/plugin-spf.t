#!perl

use strict;
use warnings;

use Test::More tests => 77;
use Test::Exception;
use Test::MockObject;

use Mail::MtPolicyd::Request;
use Mail::MtPolicyd::Plugin::SPF;

my $p;

# fake a Server object
my $server = Test::MockObject->new;
$server->set_isa('Net::Server');
$server->mock( 'log',
    sub { my ( $self, $level, $message ) = @_; print '# LOG('.$level.'): '.$message."\n" } );

sub test_request {
  my ($ip, $addr, $action, $score) = @_;

  my $session = {
    '_instance' => 'abcd1234',
  };

  my $r = Mail::MtPolicyd::Request->new(
    attributes => {
      'instance' => 'abcd1234',
      'helo_name' => 'affenschaukel.bofh-noc.de',
      'client_address' => $ip,
      'sender' => $addr,
    },
    session => $session,
    server => $server,
    use_caching => 0,
  );
  isa_ok( $r, 'Mail::MtPolicyd::Request');

  my $result;
  lives_ok { $result = $p->run($r); } 'execute request';
  if(defined $action) {
    isa_ok( $result, 'Mail::MtPolicyd::Plugin::Result' );
    like( $result->action, $action, 'check action' );
  } else {
    is( $result, undef, 'should not match' );
  }
  is($session->{'score'}, $score, "test score");

  return;
}

$p = Mail::MtPolicyd::Plugin::SPF->new(
  name => 'spf',
  enabled => 'on',
  pass_score => -10,
  pass_mode => 'passive',
  fail_score => 5,
  fail_mode => 'reject',
);
isa_ok($p, 'Mail::MtPolicyd::Plugin::SPF');

test_request('78.47.220.83', 'spf@markusbenning.de', undef, -10);
test_request('192.168.1.1', 'spf@markusbenning.de', qr/reject SPF validation failed/, 5);
test_request('192.168.1.1', 'spf@spf-fail.bofh-noc.de', qr/reject SPF validation failed/, 5);
test_request('192.168.1.1', 'spf@spf-pass.bofh-noc.de', undef, -10);
test_request('192.168.1.1', 'spf@spf-softfail.bofh-noc.de', undef, undef);
test_request('192.168.1.1', 'spf@spf-permerror-syntax.bofh-noc.de', qr/reject spf mfrom check failed/, undef);

$p = Mail::MtPolicyd::Plugin::SPF->new(
  name => 'spf',
  enabled => 'on',
  softfail_mode => 'reject',
  softfail_score => 5,
);
isa_ok($p, 'Mail::MtPolicyd::Plugin::SPF');

test_request('192.168.1.1', 'spf@spf-softfail.bofh-noc.de', qr/reject SPF validation failed/, 5);

$p = Mail::MtPolicyd::Plugin::SPF->new(
  name => 'spf',
  enabled => 'on',
  permerror_mode => 'passive',
  permerror_score => 15,
);
isa_ok($p, 'Mail::MtPolicyd::Plugin::SPF');

test_request('192.168.1.1', 'spf@spf-permerror-syntax.bofh-noc.de', undef, 15);

$p = Mail::MtPolicyd::Plugin::SPF->new(
  name => 'spf',
  enabled => 'on',
  pass_mode => 'passive',
  softfail_mode => 'passive',
  fail_mode => 'passive',
  permerror_mode => 'passive',
);
isa_ok($p, 'Mail::MtPolicyd::Plugin::SPF');

test_request('192.168.1.1', 'spf@spf-pass.bofh-noc.de', undef, undef);
test_request('192.168.1.1', 'spf@spf-softfail.bofh-noc.de', undef, undef);
test_request('192.168.1.1', 'spf@spf-fail.bofh-noc.de', undef, undef);
test_request('192.168.1.1', 'spf@spf-permerror-syntax.bofh-noc.de', undef, undef);

$p = Mail::MtPolicyd::Plugin::SPF->new(
  name => 'spf',
  enabled => 'on',
  pass_mode => 'dunno',
  softfail_mode => 'reject',
  fail_mode => 'reject',
  permerror_mode => 'reject',
);
isa_ok($p, 'Mail::MtPolicyd::Plugin::SPF');

test_request('192.168.1.1', 'spf@spf-pass.bofh-noc.de', qr/^dunno/, undef);
test_request('192.168.1.1', 'spf@spf-softfail.bofh-noc.de', qr/^reject/, undef);
test_request('192.168.1.1', 'spf@spf-fail.bofh-noc.de', qr/^reject/, undef);
test_request('192.168.1.1', 'spf@spf-permerror-syntax.bofh-noc.de', qr/^reject/, undef);

