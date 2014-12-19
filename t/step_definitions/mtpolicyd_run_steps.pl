#!perl

use strict;
use warnings;

use Test::More;

Given qr/that a mtpolicyd is running with configuration (\S+)/, sub {
    my $server = Test::Net::Server->new(
        class => 'Mail::MtPolicyd',
        config_file => $1,
    );
    $server->run;
    S->{'server'} = $server;
}

