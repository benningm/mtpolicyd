#!perl

use strict;
use warnings;

use Test::More;
use Test::Memcached;

Given qr/that a mtpolicyd is running with configuration (\S+)/, sub {
  my $mc = Test::Memcached->new
    or die('could not start memcached. (is it installed?)');
  $mc->start;
  my $server = Test::Net::Server->new(
    class => 'Mail::MtPolicyd',
    config_file => $1,
    memcached_port => $mc->option( 'tcp_port' ),
  );
  $server->run;
  S->{'server'} = $server;
  S->{'memcached'} = $mc;
}

