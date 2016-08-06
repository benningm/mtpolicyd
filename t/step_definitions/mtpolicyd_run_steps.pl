#!perl

use strict;
use warnings;

use Test::More;
use Test::Memcached;
use Test::Exception;

Given qr/that a mtpolicyd is running with configuration (\S+)/, sub {
  my $mc;
  lives_ok {
    $mc = Test::Memcached->new;
  } 'initialization of Test::Memcached object';
  if( ! defined $mc ) {
    fail('could not start memcached. (is it installed?)');
    return;
  }
  isa_ok($mc, 'Test::Memcached');
  lives_ok {
    $mc->start;
  } 'startup of memcached';
  my $server;
  lives_ok {
    $server = Test::Net::Server->new(
      class => 'Mail::MtPolicyd',
      config_file => $1,
      memcached_port => $mc->option( 'tcp_port' ),
    );
  } 'creation of server object muss succeed';
  isa_ok($server, 'Test::Net::Server');
  lives_ok {
    $server->run;
  } 'startup of mtpolicyd test server';
  S->{'server'} = $server;
  S->{'memcached'} = $mc;
};

Then qr/the mtpolicyd server must be stopped successfull/, sub {
  my $server = S->{'server'};
  $server->shutdown;
};

