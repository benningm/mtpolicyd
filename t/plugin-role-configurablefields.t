#!perl

use strict;
use warnings;

use Test::More tests => 7;
use Test::Exception;
use Test::MockObject;

use Mail::MtPolicyd::Request;

package Mail::MtPolicyd::Plugin::TestConfigurableFields;

use Moose;

extends 'Mail::MtPolicyd::Plugin';
with 'Mail::MtPolicyd::Plugin::Role::ConfigurableFields' => {
  fields => {
    'test_str' => {
      default => 'test value',
      value_isa => 'Str',
    },
    'test_int' => {
      default => 123,
      value_isa => 'Int',
    },
  }
};

package main;

import Mail::MtPolicyd::Plugin::TestConfigurableFields;

my $p = Mail::MtPolicyd::Plugin::TestConfigurableFields->new(
    name => 'configurable-fields-test',
    test_str_field => 'test_str',
    test_int_field => 'test_int',
);
isa_ok($p, 'Mail::MtPolicyd::Plugin::TestConfigurableFields');

lives_ok { $p->init(); } 'initialize plugin';

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
	},
	session => $session,
	server => $server,
	use_caching => 0,
);

isa_ok( $r, 'Mail::MtPolicyd::Request');

ok( ! defined $p->get_test_int_value( $r ), 'must be undefined without request field' );

$r->attributes->{'test_int'} = 123;
cmp_ok( $p->get_test_int_value( $r ), '==', '123', 'must be returned value of request field if present' );

$r->attributes->{'test_int'} = 'hello world';
ok( ! defined $p->get_test_int_value( $r ), 'must be undefined without if type constraint fails' );

$r->attributes->{'test_str'} = 'hello world';
cmp_ok( $p->get_test_str_value( $r ), 'eq', 'hello world', 'must be returned value of request field if present' );

