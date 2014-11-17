#!perl

use strict;
use warnings;

use Test::More tests => 5;

use_ok('Mail::MtPolicyd::Profiler');

my $p = Mail::MtPolicyd::Profiler->new;
isa_ok( $p, 'Mail::MtPolicyd::Profiler', 'test constructor');

$p->reset;
isa_ok( $p->root, 'Mail::MtPolicyd::Profiler::Timer', 'root timer must be set');
isa_ok( $p->current, 'Mail::MtPolicyd::Profiler::Timer', 'current timer must be set');

$p->tick('start parsing request');
$p->tick('finished parsing request');

$p->new_timer('start processing plugin chain');

$p->new_timer('plugin 1');
$p->tick('start dns lookup');
$p->tick('finished dns lookup');
$p->stop_current_timer;

$p->new_timer('plugin 2');
$p->tick('nothing todo');
$p->stop_current_timer;

$p->stop_current_timer;

$p->stop_current_timer;

my $string = $p->to_string;
ok($string =~ /start dns lookup/, 'must contain dns lookup');

