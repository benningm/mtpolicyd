#!perl

use strict;
use warnings;

use Test::More;

use Mail::MtPolicyd::Client;
use Mail::MtPolicyd::Client::Request;

When qr/the following request is executed on mtpolicyd:/, sub {
    isa_ok( S->{'server'}, 'Test::Net::Server');
    my $port = S->{'server'}->port;
    my $client = Mail::MtPolicyd::Client->new(
        'host' => 'localhost:'.$port,
    );
    my $attrs = { map { split('=', $_, 2) } split("\n", C->data) };
    my $req = Mail::MtPolicyd::Client::Request->new(
        attributes => $attrs,
    );
    my $response;
    eval {
        $response = $client->request( $req );
    };
    if( $@ ) {
        fail('error while executing query: '.$@
            ."\nLogfile: ".S->{'server'}->tail_log );
        return;
    }
    pass('sent request to policy server');
    S->{'policyd_response'} = $response;
    return;
};

Then qr/mtpolicyd must respond with a action like (.*)/, sub {
    my $regex = $1;
    my $response = S->{'policyd_response'};
    ok( defined $response, 'got a policyd response');
    ok( defined $response->action, 'response action is defined');
    like( $response->action, qr/$regex/, 'action is like '.$1);
    return;
};


