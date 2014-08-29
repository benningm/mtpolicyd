#!perl

package Mail::MtPolicyd::Plugin::Test::Scoring;

use Moose;

extends 'Mail::MtPolicyd::Plugin';
with 'Mail::MtPolicyd::Plugin::Role::Scoring';

package main;

use strict;
use warnings;

use Test::More tests => 21;
use Test::Exception;
use Test::MockObject;

use Mail::MtPolicyd::Request;
import Mail::MtPolicyd::Plugin::Test::Scoring;

use Mail::MtPolicyd::Plugin::ScoreAction;
use Mail::MtPolicyd::Plugin::AddScoreHeader;

my $plugin = Mail::MtPolicyd::Plugin::Test::Scoring->new( name => 'score-test' );
isa_ok($plugin, 'Mail::MtPolicyd::Plugin::Test::Scoring');

my $session = {
	'_instance' => 'abcd1234',
};

# fake a Server object
my $server = Test::MockObject->new;
$server->set_isa('Net::Server');
$server->mock( 'log',
    sub { my ( $self, $level, $message ) = @_; print '# LOG('.$level.'): '.$message."\n" } );

my $r = Mail::MtPolicyd::Request->new(
	attributes => {
		'instance' => 'abcd1234',
		'client_address' => '127.0.0.1',
	},
	session => $session,
	server => $server,
);

isa_ok( $r, 'Mail::MtPolicyd::Request');

# add some scores with our dummy scoring plugin
lives_ok { $plugin->add_score( $r, 'ZUMSEL' => 5 ); } 'call ->add_score()';
is( $r->session->{'score'}, 5, 'score must be 5');
is( $r->session->{'score_detail'}, 'ZUMSEL=5', 'check score_detail');

lives_ok { $plugin->add_score( $r, 'BLA' => 2.5 ); } 'call ->add_score()';
is( $r->session->{'score'}, 7.5, 'score must be 7.5');
is( $r->session->{'score_detail'}, 'ZUMSEL=5, BLA=2.5', 'check score_detail');

# Test ScoreAction Plugin

my $action = Mail::MtPolicyd::Plugin::ScoreAction->new(
	name => 'score-action',
	threshold => 10,
	action => 'reject sender ip %IP% is blocked (score=%SCORE%%SCORE_DETAIL%)',
);
isa_ok($action, 'Mail::MtPolicyd::Plugin::ScoreAction');

my $result;
lives_ok { $result = $action->run($r); } 'execute request';
is( $result, undef, 'should not match' );

lives_ok { $plugin->add_score( $r, 'BLUB' => 2.5 ); } 'call ->add_score()';
is( $r->session->{'score'}, 10, 'score must be 10');
is( $r->session->{'score_detail'}, 'ZUMSEL=5, BLA=2.5, BLUB=2.5', 'check score_detail');

lives_ok { $result = $action->run($r); } 'execute request';
isa_ok( $result, 'Mail::MtPolicyd::Plugin::Result', 'now it should match' );
is($result->action, 'reject sender ip 127.0.0.1 is blocked (score=10, ZUMSEL=5, BLA=2.5, BLUB=2.5)', 'action must be reject');

# Test AddScoreHeader plugin

my $header = Mail::MtPolicyd::Plugin::AddScoreHeader->new( name => 'score-header' );
isa_ok($header, 'Mail::MtPolicyd::Plugin::AddScoreHeader');
lives_ok { $result = $header->run($r); } 'execute request';
isa_ok( $result, 'Mail::MtPolicyd::Plugin::Result', 'should return a Result' );
is($result->action, 'PREPEND X-MtScore: YES score=10 [ZUMSEL=5, BLA=2.5, BLUB=2.5]', 'should prepend a detailed header');


