#!perl

use strict;
use warnings;

use Test::More;
use Test::Exception;
use Test::MockObject;

use Mail::MtPolicyd::Request;
use Mail::MtPolicyd::SqlConnection;
use Mail::MtPolicyd::Plugin::Greylist;

use Cache::Memcached;
use DBI;

my $memcached = Cache::Memcached->new(
    servers => [ '127.0.0.1:11211' ],
    namespace => 'mt-test-',
    debug => 0,
);

if( ! $memcached->set('test-memcached', 'test', 1) ) {
        plan skip_all => 'no memcached at 127.0.0.1:11211 available, skipping test';
}

plan tests => 79;

isa_ok($memcached, 'Cache::Memcached');

my $p = Mail::MtPolicyd::Plugin::Greylist->new(
	name => 'greylist-test',
    autowl_threshold => 5,
);
isa_ok($p, 'Mail::MtPolicyd::Plugin::Greylist');

# build a fake database with an in-memory SQLite DB
Mail::MtPolicyd::SqlConnection->initialize(
    dsn => 'dbi:SQLite::memory:',
    user => '',
    password => '',
);

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

$server->mock( 'memcached', sub { return $memcached; } );

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

    # now we should have a autowl row
    my $row;
    lives_ok {
        $row = $p->get_autowl_row( $sender_domain, $client_address );
    } 'retrieve autowl row';
    ok( ref($row) eq 'HASH', 'row is an hash reference');
    cmp_ok( $row->{'count'}, 'eq', $count, 'autowl count must be '.$count);
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
    Mail::MtPolicyd::SqlConnection->dbh->do(
        'UPDATE autowl SET last_seen=1;'
    );
} 'manipulate autowl, expire';

# greylisting should be active again
test_one_greylisting_circle( $sender, $client_address, $recipient, $r, 1 );

