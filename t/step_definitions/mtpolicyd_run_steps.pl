#!perl

use strict;
use warnings;

use Test::More;
use Test::Exception;

Given qr/that a mtpolicyd is running with configuration (\S+)/, sub {
  my $server;
  lives_ok {
    $server = Test::Net::Server->new(
      class => 'Mail::MtPolicyd',
      config_file => $1,
    );
  } 'creation of server object muss succeed';
  isa_ok($server, 'Test::Net::Server');
  lives_ok {
    $server->run;
  } 'startup of mtpolicyd test server';
  S->{'server'} = $server;
};

Then qr/the mtpolicyd server must be stopped successfull/, sub {
  my $server = S->{'server'};
  $server->shutdown;
};

