#!perl

use strict;
use warnings;

use Test::More tests => 5;
use Test::Exception;
use Test::MockObject;

use Mail::MtPolicyd::ConnectionPool;
use Mail::MtPolicyd::Request;
use Mail::MtPolicyd::Plugin::LdapUserConfig;

use DBI;

my $p = Mail::MtPolicyd::Plugin::LdapUserConfig->new(
	name => 'ldapuserconfig-test',
	basedn => 'ou=users,dc=domain,dc=com',
  filter => '(mail=%s)',
  filter_field => 'sasl_username',
  config_fields => 'gn,sn,mailMessageLimit',
);

isa_ok($p, 'Mail::MtPolicyd::Plugin::LdapUserConfig');

my $session = {
	'_instance' => 'abcd1234',
};

# build a moch LdapConnection
Mail::MtPolicyd::ConnectionPool->load_connection('ldap', {
  module => 'Ldap',
  host => 'dummy',
  port => 389,
  binddn => 'cn=readonly,dc=domain,dc=com',
  password => 'secret',
  starttls => 1,
  connection_class => 'Test::Net::LDAP::Mock',
} );
my $ldap = Mail::MtPolicyd::ConnectionPool->get_handle('ldap');
$ldap->add('uid=max,ou=users,dc=domain,dc=com', attrs => [
  uid => 'max',
  gn => 'Max',
  sn => 'Mustermann',
  mail => 'max.mustermann@domain.com',
  mailMessageLimit => 2000,
]);

# fake a Server object
my $server = Test::MockObject->new;
$server->set_isa('Net::Server');
$server->mock( 'log',
    sub { my ( $self, $level, $message ) = @_; print '# LOG('.$level.'): '.$message."\n" } );

my $r = Mail::MtPolicyd::Request->new(
	attributes => {
		'instance' => 'abcd1234',
		'sasl_username' => 'max.mustermann@domain.com',
	},
	session => $session,
	server => $server,
);

isa_ok( $r, 'Mail::MtPolicyd::Request');

my $result;

lives_ok { $result = $p->run($r); } 'execute request';
is( $result, undef, 'should not return a result' );

cmp_ok( $session->{'mailMessageLimit'}, '==', 2000, 'mailMessageLimit must be set');

