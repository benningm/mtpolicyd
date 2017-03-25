package Mail::MtPolicyd::Plugin::LdapUserConfig;

use Moose;
use namespace::autoclean;

# VERSION
# ABSTRACT: mtpolicyd plugin for retrieving per user configuration from LDAP

extends 'Mail::MtPolicyd::Plugin';

=head1 DESCRIPTION

This plugin could be used to retrieve session variables/user configuration
from a LDAP server.

=head1 SYNOPSIS

  ldap_host="localhost"
  ldap_binddn="cn=readonly,dc=domain,dc=com"
  ldap_password="secret"

  <Plugin user_config>
    module="LdapUserConfig"
    basedn="ou=users,dc=domain,dc=com"
    filter="(mail=%s)"
    filter_field="sasl_username"
    config_fields="mailMessageLimit,mailSendExternal"
  </Plugin>

=head1 PARAMETERS

The LDAP connection must be configured in the global configuration section
of mtpolicyd. See L<mtpolicyd>.

=over

=item basedn (default: '')

The basedn to use for the search.

=item filter (required)

The filter to use for the search.

The pattern %s will be replaced with the content of filter_field.

=item filter_field (required)

The content of this request field will be used to replace %s in the
filter string.

=item config_fields (required)

A comma separated list of LDAP attributes to retrieve and
copy into the current mtpolicyd session.

=back

=cut

use Mail::MtPolicyd::Plugin::Result;

use Net::LDAP::Util qw( escape_filter_value );

has 'basedn' => ( is => 'rw', isa => 'Str', default => '' );

has 'filter' => ( is => 'rw', isa => 'Str', required => 1 );

with 'Mail::MtPolicyd::Plugin::Role::ConfigurableFields' => {
  'fields' => {
    'filter' => {
      isa => 'Str',
      default => 'sasl_username',
      value_isa => 'Str',
    },
  },
};


has 'config_fields' => ( is => 'rw', isa => 'Str', required => 1 );

has '_config_fields' => (
  is => 'ro', isa => 'ArrayRef[Str]', lazy => 1,
  default => sub {
    my $self = shift;
    return [ split(/\s*,\s*/, $self->config_fields ) ];
  },
);

has 'connection' => ( is => 'ro', isa => 'Str', default => 'ldap' );
has 'connection_type' => ( is => 'ro', isa => 'Str', default => 'Ldap' );

with 'Mail::MtPolicyd::Role::Connection' => {
  name => 'ldap',
  type => 'Ldap',
};

sub retrieve_ldap_entry {
  my ( $self, $r ) = @_;
  my $ldap = $self->_ldap_handle;

  my $value = $self->get_filter_value( $r );
  if( ! defined $value ) {
    $self->log( $r, 'filter_field('.$self->filter_field.') is not defined in request. skipping ldap search.');
    return;
  }
  my $filter = $self->filter;
  my $filter_value = escape_filter_value($value);
  $filter =~ s/%s/$filter_value/g;
  $self->log( $r, 'ldap filter is: '.$filter);

  my $msg;
  eval {
    $msg = $ldap->search(
      base => $self->basedn,
      filter => $filter,
    );
  };
  if( $@ ) {
    $self->log( $r, 'ldap search failed: '.$@ );
    return;
  }
  if( $msg->count != 1 ) {
    $self->log( $r, 'ldap search return '.$msg->count.' entries' );
    return;
  }

  my $entry = $msg->entry( 0 );
  $self->log( $r, 'found in ldap: '.$entry->dn );

  return $entry;
}

sub run {
  my ( $self, $r ) = @_;

  my $entry = $self->retrieve_ldap_entry( $r );
  if( defined $entry ) {
    foreach my $field ( @{$self->_config_fields} ) {
      my ($value) = $entry->get_value( $field );
      if( defined $value && $value ne '' ) {
        $self->log( $r, 'retrieved ldap attribute: '.$field.'='.$value );
        $r->session->{$field} = $value;
      } else {
        $self->log( $r, 'LDAP attribute '.$field.' is empty. skipping.' );
      }
    }
  }

  return;
}

__PACKAGE__->meta->make_immutable;

1;

