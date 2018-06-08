#!perl

use strict;
use warnings;

use Test::More tests => 19;
use Test::Exception;
use Test::Deep;

use_ok('Mail::MtPolicyd::Connection::Ldap');

my $ldap;
lives_ok {
  $ldap = Mail::MtPolicyd::Connection::Ldap->new(
    name => 'ldap',
    host => 'openldap',
    port => 389,
    starttls => 0,
  );
} 'create ldap connection';
isa_ok($ldap, 'Mail::MtPolicyd::Connection::Ldap');

ok(!$ldap->is_connected, 'connection not established');

lives_ok {
  $ldap->handle;
} "retrieve connection";
ok($ldap->is_connected, 'connection established');
isa_ok($ldap->handle, 'Net::LDAP');
my $old_handle = $ldap->handle;

lives_ok {
  $ldap->reconnect;
} "reconnect connection";
ok(!$ldap->is_connected, 'connection not established');

lives_ok {
  $ldap->handle;
} "retrieve connection";
isa_ok($ldap->handle, 'Net::LDAP');
ok($ldap->is_connected, 'connection established');
cmp_ok($old_handle, '!=', $ldap->handle, 'a new handle has been created');

lives_ok {
  $ldap->shutdown;
} "close connection";
ok(!$ldap->is_connected, 'connection not established');

lives_ok {
  $ldap->handle;
} "retrieve connection";
isa_ok($ldap->handle, 'Net::LDAP');
ok($ldap->is_connected, 'connection established');

diag('trying to sabotage connection by closing underlying socket...');
$ldap->handle->socket->close;

lives_ok {
  $ldap->handle->bind;
} "connection must be reestablished";


