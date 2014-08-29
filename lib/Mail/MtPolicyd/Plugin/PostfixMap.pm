package Mail::MtPolicyd::Plugin::PostfixMap;

use Moose;
use namespace::autoclean;

# VERSION
# ABSTRACT: mtpolicyd plugin for accessing a postfix access map

extends 'Mail::MtPolicyd::Plugin';
with 'Mail::MtPolicyd::Plugin::Role::Scoring';
with 'Mail::MtPolicyd::Plugin::Role::UserConfig' => {
	'uc_attributes' => [ 'enabled' ],
};

use Mail::MtPolicyd::Plugin::Result;

use BerkeleyDB;
use BerkeleyDB::Hash;

=head1 SYNOPSIS

  <Plugin whitelist>
    module="PostfixMap"
    db_file="/etc/postfix/whitelist.db"
    match_action=dunno
  </Plugin>

  <Plugin blacklist>
    moduel="PostfixMap"
    db_file="/etc/postfix/whitelist.db"
    match_action="reject you are blacklisted!"
  </Plugin>

=head1 DESCRIPTION

Plugin checks the client_address against a postfix hash table.

It will only check if the IP address matches the list.
'OK' or a numerical value will be interpreted as a 'true' value.
All other actions or values will be treaded as 'false'.

=head1 EXAMPLE TABLE

/etc/postfix/whitelist:

  123.123.123.123 OK
  123.123.122 OK
  123.12 OK
  fe80::250:56ff:fe85:56f5 OK
  fe80::250:56ff:fe83 OK

generate whitelist.db:

  $ postmap whitelist

=head2 PARAMETERS

The module takes the following parameters:

=over

=item (uc_)enabled (default: "on")

Could be set to 'off' to deactivate check. Could be used to activate/deactivate check per user.

=back

By default the plugin will do nothing. One of the following actions should be specified:

=over

=item match_action (default: empty)

If given this action will be returned to the MTA if the SQL query matched.

=item not_match_action (default: empty)

If given this action will be returned to the MTA if the SQL query DID NOT matched.

=item score (default: empty)

If given this score will be applied to the session.

=back

=cut

has 'enabled' => ( is => 'rw', isa => 'Str', default => 'on' );

has 'db_file' => ( is => 'rw', isa => 'Str', required => 1 );
has _map => (
	is => 'ro', isa => 'HashRef', lazy => 1,
	default => sub {
		my $self = shift;
		my %map;
		my $db = tie %map, 'BerkeleyDB::Hash',
			-Filename => $self->db_file,
			-Flags => DB_RDONLY
		or die "Cannot open ".$self->db_file.": $!\n" ;
		$db->filter_fetch_key  ( sub { s/\0$//    } ) ;
		$db->filter_store_key  ( sub { $_ .= "\0" } ) ;
		$db->filter_fetch_value( sub { s/\0$//    } ) ;
		$db->filter_store_value( sub { $_ .= "\0" } ) ;
		return(\%map);
	},
);

has 'score' => ( is => 'rw', isa => 'Maybe[Num]' );
has 'match_action' => ( is => 'rw', isa => 'Maybe[Str]' );
has 'not_match_action' => ( is => 'rw', isa => 'Maybe[Str]' );

sub _match_ipv4 {
	my ( $self, $ip ) = @_;
	my @octs = split('\.', $ip);

	while( @octs ) {
		my $key = join('.', @octs);
		my $value = $self->_map->{$key};
		if( defined $value ) {
			return( $key, $value );
		}
		pop(@octs);
	}

	return;
}

sub _match_ipv6 {
	my ( $self, $ip ) = @_;

	for(;;) {
		my $value = $self->_map->{$ip};
		if( $value ) {
			return( $ip, $value );
		}
		if( $ip !~ m/:/) {
			last;
		}
		# remove last part
		$ip =~ s/:+[^:]+$//;
	}

	return;
}

sub _query_db {
	my ( $self, $ip ) = @_;
	my ( $key, $value );
	if( $ip =~ m/^\d+\.\d+\.\d+\.\d+$/) {
		( $key, $value ) = $self->_match_ipv4( $ip );
	} elsif( $ip =~ m/^[:0-9a-f]+$/) {
		( $key, $value ) = $self->_match_ipv6( $ip );
	} else {
		die('ip is neither a valid ipv4 nor ipv6 address.');
	}

	if( ! defined $value ) {
		return;
	}

	if( $value eq 'OK' || $value =~ m/^\d+$/) {
		return( 1, $key, $value );
	}
	
	return(0, $key, $value);
}

sub run {
	my ( $self, $r ) = @_;
	my $ip = $r->attr('client_address');
	my $session = $r->session;
	my $config;

	if( $self->get_uc( $session, 'enabled') eq 'off' ) {
		return;
	}

	if( ! defined $ip) {
		$self->log($r, 'no attribute \'client_address\' in request');
		return;
	}

	my ( $match, $key, $value ) = $r->do_cached( $self->name.'-result',
			sub { $self->_query_db($ip) } );
	if( $match ) {
		$self->log($r, 'client_address '.$ip.' matched '.$self->name.' ('.
			$key.' '.$value.')' );
		if( defined $self->score
				&& ! $r->is_already_done($self->name.'-score') ) {
			$self->add_score($r, $self->name => $self->score);
		}
		if( defined $self->match_action ) {
			return Mail::MtPolicyd::Plugin::Result->new(
				action => $self->match_action,
				abort => 1,
			);
		}
	} else {
		$self->log($r, 'client_address '.$ip.' did not match '.$self->name);
		if( defined $self->not_match_action ) {
			return Mail::MtPolicyd::Plugin::Result->new(
				action => $self->not_match_action,
				abort => 1,
			);
		}
	}

	return;
}

__PACKAGE__->meta->make_immutable;

1;

