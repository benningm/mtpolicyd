#!perl

use strict;
use warnings;

use Test::More tests => 5;
use Test::MockObject;
use Mail::MtPolicyd::ConnectionPool;
use Test::Memcached;
use Test::RedisDB;
use Test::Exception;
use String::Random;
use Test::Deep;

use_ok('Mail::MtPolicyd::SessionCache');

my $server = Test::MockObject->new;
$server->set_isa('Net::Server');
$server->mock( 'log',
    sub { my ( $self, $level, $message ) = @_; print '# LOG('.$level.'): '.$message."\n" } );

my $cache = Mail::MtPolicyd::SessionCache->new(
  server => $server,
);
isa_ok( $cache, 'Mail::MtPolicyd::SessionCache', 'initialize session cache');

sub cache_basics_ok {
  my ( $cache ) = @_;
  my $instance = 'abcd1234';

  isa_ok( $cache->server, 'Net::Server');
  isa_ok( $cache->cache, 'Mail::MtPolicyd::SessionCache::Base');

  can_ok( $cache,
    'retrieve_session',
    'store_session',
    'shutdown',
    'load_config',
  );

  lives_ok {
    $cache->store_session( {
      _instance => $instance,
      test => 'bla',
    } );
  } 'call store_session must succeed';

  lives_ok {
    $cache->retrieve_session( $instance );
  } 'call retrieve_session must succeed';
}

sub cache_store_retrieve_ok {
  my ( $cache ) = @_;
  my $rand = String::Random->new;

  foreach (1..10) {
    my $instance = $rand->randpattern('ssssssss');
    my $session;
    my $session_retrieved;
    lives_ok {
      $session = $cache->retrieve_session( $instance );
    } 'must be able to retrieve a session';
    $session->{'data'} = $rand->randpattern('CCCCCCCCCC');
    lives_ok {
      $cache->store_session( $session );
    } 'must be able to store the session';
    lives_ok {
      $session_retrieved = $cache->retrieve_session( $instance );
    } 'must be able to retrieve the session again';
    cmp_deeply( $session, $session_retrieved, 'stored and retrieved session must match');
  }
}

sub cache_locking_ok {
  my ( $cache ) = @_;
  my $rand = String::Random->new;
  my $instance = $rand->randpattern('ssssssss');
  my $session;

  lives_ok {
    $session = $cache->retrieve_session( $instance );
  } 'must be able to retrieve a session';
  throws_ok {
    $session = $cache->retrieve_session( $instance );
  } qr/could not acquire lock for session/, 'session must be locked';
}

subtest 'test session cache None', sub {
  cache_basics_ok( $cache );
};

subtest 'test session cache Memcached', sub {
  diag('trying to start mock memcached...');
  my $mc_server = Test::Memcached->new
    or plan skip_all => 'could not start memcached (not installed?), skipping test...';
  $mc_server->start;

  Mail::MtPolicyd::ConnectionPool->load_connection( 'memcached', {
    module => 'Memcached',
    servers => '127.0.0.1:'.$mc_server->option('tcp_port'),
  } );

  lives_ok {
    $cache->load_config( {
      module => 'Memcached',
      memcached => 'memcached',
    } );
  } 'load session cache memcached config';

  cache_basics_ok( $cache );
  cache_store_retrieve_ok( $cache );
  cache_locking_ok( $cache );

  $mc_server->stop;
};

subtest 'test session cache Redis', sub {
  diag('trying to start mock redis...');
  my $redis = Test::RedisDB->new
    or plan skip_all => 'could not start redis (not installed?), skipping test...';

  Mail::MtPolicyd::ConnectionPool->load_connection( 'redis', {
    module => 'Redis',
    server => '127.0.0.1:'.$redis->port,
  } );

  lives_ok {
    $cache->load_config( {
      module => 'Redis',
      redis => 'redis',
    } );
  } 'load session cache redis config';

  cache_basics_ok( $cache );
  cache_store_retrieve_ok( $cache );
  cache_locking_ok( $cache );

  $redis->stop;
};

