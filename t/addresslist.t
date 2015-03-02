#!perl

use strict;
use warnings;

use Test::More tests => 12;
use Test::MockObject;

use Mail::MtPolicyd::AddressList;

my $list = Mail::MtPolicyd::AddressList->new;
isa_ok( $list, 'Mail::MtPolicyd::AddressList');

ok( $list->is_empty, 'list must be empty' );

$list->add_localhost;
ok( ! $list->is_empty, 'list must contain entries' );
cmp_ok( $list->count, '==', 3, 'list must 3 entries' );

ok( $list->match_string('127.0.0.1'), 'list must match 127.0.0.1' );
ok( $list->match_string('::1'), 'list must match ::1' );

cmp_ok( $list->as_string, 'eq',
    '127.0.0.0/8,0:0:0:0:0:FFFF:7F00:0/104,0:0:0:0:0:0:0:1/128',
    'check as_string output'
);

ok( ! $list->match_string('123.45.67.89'), 'must not match a unknown IPv4!' );
ok( ! $list->match_string('2a01:4f8:d12:242::2'), 'must not match a unknown IPv6!' );

$list->add_string('78.47.220.83');
$list->add_string('2a01:4f8:d12:242::2,fe80::21c:14ff:fe01:c8 103.41.124.100');

cmp_ok( $list->count, '==', 7, 'list must contain 7 entries' );

ok( $list->match_string('78.47.220.83'), 'must match IP 78.47.220.83' );
ok( $list->match_string('103.41.124.100'), 'must match IP 103.41.124.100' );
