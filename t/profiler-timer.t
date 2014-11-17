#!perl

use strict;
use warnings;

use Test::More tests => 13;

use_ok('Mail::MtPolicyd::Profiler::Timer');

my $timer = Mail::MtPolicyd::Profiler::Timer->new(name => 'zumsel');
isa_ok( $timer, 'Mail::MtPolicyd::Profiler::Timer', 'constructor with hash params');

$timer = Mail::MtPolicyd::Profiler::Timer->new('zumsel');
isa_ok( $timer, 'Mail::MtPolicyd::Profiler::Timer', 'constructor with single arg');

ok( defined $timer->start_time, 'start time must be defined');
is( ref $timer->start_time, 'ARRAY', 'start time must be ArrayRef');

$timer->tick('event 1');
is( scalar @{$timer->ticks}, 1, 'must contain 1 tick' );

my $tick =  $timer->ticks->[0];
is( ref $tick, 'ARRAY', 'tick must be ArrayRef');
is( scalar @$tick, 2, 'tick must contain 2 elements');

my $subtimer = $timer->new_child( name => 'blablub' );
isa_ok( $subtimer, 'Mail::MtPolicyd::Profiler::Timer', 'create sub timer');

is( scalar @{$timer->ticks}, 3, 'must contain 3 elements' );
my $child =  $timer->ticks->[-1];
cmp_ok($child, '==', $subtimer, 'child must equal returned subtimer');
cmp_ok($child->parent, '==', $timer, 'parent of subtimer must equal timer');

$timer->stop;
is( scalar @{$timer->ticks}, 4, 'must contain 4 elements' );

