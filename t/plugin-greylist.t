#!perl

use strict;
use warnings;

use Test::More;
use Test::Exception;
use Test::MockObject;

use Mail::MtPolicyd::Request;
use Mail::MtPolicyd::ConnectionPool;
use Mail::MtPolicyd::Plugin::Greylist;

use Cache::Memcached;
use DBI;

plan tests => 73;

Mail::MtPolicyd::ConnectionPool->load_connection( 'memcached', {
  module => 'Memcached',
  servers => 'memcached:11211',
} );
my $memcached = Mail::MtPolicyd::ConnectionPool->get_handle('memcached');
isa_ok( $memcached, 'Cache::Memcached' );

my $p = Mail::MtPolicyd::Plugin::Greylist->new(
	name => 'greylist-test',
  autowl_threshold => 5,
);
isa_ok($p, 'Mail::MtPolicyd::Plugin::Greylist');

# build a fake database with an in-memory SQLite DB
Mail::MtPolicyd::ConnectionPool->load_connection( 'db', {
  module => 'Sql',
  dsn => 'dbi:SQLite::memory:',
  user => '',
  password => '',
} );

lives_ok {
    $p->init();
} 'plugin initialization';

my $session = {
	'_instance' => 'abcd1234',
};

# fake a Server object
my $server = Test::MockObject->new;
$server->set_isa('Net::Server');
$server->mock( 'log',
    sub { my ( $self, $level, $message ) = @_; print '# LOG('.$level.'): '.$message."\n" } );

sub test_one_greylisting_circle {
    my ( $sender, $client_address, $recipient, $r, $count ) = @_;
    my $sender_domain = $p->_extract_sender_domain( $sender );


    my $result;
    lives_ok { $result = $p->run($r); } 'execute request';
    isa_ok( $result, 'Mail::MtPolicyd::Plugin::Result', 'must return a result' );
    like( $result->action, qr/^defer greylisting is active$/, 'must return a greylist defer');

    # second time it must show a delay
    lives_ok { $result = $p->run($r); } 'execute request';
    isa_ok( $result, 'Mail::MtPolicyd::Plugin::Result', 'must return a result' );
    like( $result->action, qr/^defer greylisting is active \(\d+s left\)$/, 'must return a greylist defer with delay');

    # now do a timewarp
    my $key = join(',', $sender, $client_address, $recipient);
    ok($memcached->decr($key, 301), 'manipulate greylisting ticket');

    lives_ok { $result = $p->run($r); } 'execute request';
    ok( ! defined $result, 'greylisting no longer active' );

    # now we should have a autowl entry
    my $seen;
    lives_ok {
      $seen = $p->_awl->get( $sender_domain, $client_address );
    } 'retrieve autowl row';
    if( defined $count ) {
      cmp_ok( $seen, 'eq', $count, 'autowl count must be '.$count);
    } else {
      ok( ! defined $seen, 'must be no autowl present');
    }
}

my $sender = 'newsender@domain'.int(rand(1000000)).'.de';
my $client_address = '192.168.0.0';
my $recipient = 'newrcpt@mydomain.de';

my $r = Mail::MtPolicyd::Request->new(
    attributes => {
        'instance' => 'abcd1234',
        'client_address' => $client_address,
        'sender' => $sender,
        'recipient' => $recipient,
    },
    session => $session,
    server => $server,
    use_caching => 0,
);
isa_ok( $r, 'Mail::MtPolicyd::Request');

foreach my $count (1..5) {
  test_one_greylisting_circle( $sender, $client_address, $recipient, $r, $count );
}

# now autowl_threshold must be reached
my $result;
lives_ok { $result = $p->run($r); } 'execute request';
ok( ! defined $result, 'greylisting no longer active' );

# now manipulate autowl to expire all records
lives_ok {
  Mail::MtPolicyd::ConnectionPool->get_handle('db')->do(
   'UPDATE autowl SET last_seen=1;'
  );
} 'manipulate autowl, expire';

# greylisting should be active again
test_one_greylisting_circle( $sender, $client_address, $recipient, $r, undef );

