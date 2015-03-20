package Mail::MtPolicyd::Plugin::Quota;

use Moose;
use namespace::autoclean;

# VERSION
# ABSTRACT: mtpolicyd plugin for accounting in sql tables

extends 'Mail::MtPolicyd::Plugin';
with 'Mail::MtPolicyd::Plugin::Role::UserConfig' => {
	'uc_attributes' => [
        'enabled', 'field', 'threshold', 'action', 'metric'
    ],
};
with 'Mail::MtPolicyd::Plugin::Role::SqlUtils';
with 'Mail::MtPolicyd::Plugin::Role::PluginChain';

use Mail::MtPolicyd::Plugin::Result;
use Time::Piece;

=head1 DESCRIPTION

This plugin can be used to do accounting based on request fields.

=head1 Example

  <Plugin quota-clients>
    module = "Quota"
    table_prefix = "acct_"

    # per month
    time_pattern = "%Y-%m"
    # per ip
    field = "client_address"
    # allow 1000 mails
    metric = "count"
    threshold = 1000
    action = "defer you exceeded your monthly limit, please insert coin"
  </Plugin>

=head1 Configuration

=head2 Parameters

The module takes the following parameters:

=over

=item (uc_)enabled (default: on)

Enable/disable this check.

=item (uc_)field (required)

The field used for accounting/quota.

=item (uc_)metric (required)

The metric on which the quota should be based.

The Accounting module stores the following metrics:

=over

=item count

Number of mails recivied.

=item count_rcpt

Number of mails recivied multiplied with number of recipients.

=item size

Size of mails recivied.

=item size_rcpt

Size of mails recivied multiplied with number of recipients.

=back

=item time_pattern (default: "%Y-%m")

A format string for building the time key used to store counters.

Default is to build counters on a monthly base.

For example use:

  * "%Y-%W" for weekly
  * "%Y-%m-%d" for daily

See "man date" for format string sequences.

You must use the same time_pattern as used in for the Accounting module.

=item threshold (required)

The quota limit.

=item action (default: defer smtp traffic quota has been exceeded)

The action to return when the quota limit has been reached.

=item table_prefix (default: "acct_")

A prefix to add to every table.

The table name will be the prefix + field_name.

=back

=cut

has 'enabled' => ( is => 'rw', isa => 'Str', default => 'on' );

has 'field' => ( is => 'rw', isa => 'Str', required => 1);
has 'metric' => ( is => 'rw', isa => 'Str', required => 1);
has 'time_pattern' => ( is => 'rw', isa => 'Str', default => '%Y-%m');
has 'threshold' => ( is => 'rw', isa => 'Int', required => 1);
has 'action' => ( is => 'rw', isa => 'Str', default => 'defer smtp traffic quota has been exceeded');

sub get_timekey {
    my $self = shift;
    return Time::Piece->new->strftime( $self->time_pattern );
}

has 'table_prefix' => ( is => 'rw', isa => 'Str', default => 'acct_');

sub run {
	my ( $self, $r ) = @_;
	my $session = $r->session;

	if( $self->get_uc( $session, 'enabled') eq 'off' ) {
		return;
	}
    my $field = $self->get_uc( $session, 'field');
    my $metric = $self->get_uc( $session, 'metric');
    my $action = $self->get_uc( $session, 'action');
    my $threshold = $self->get_uc( $session, 'threshold');

    my $key = $r->attr( $field );
    if( ! defined $key || $key =~ /^\s*$/ ) {
        $self->log( $r, 'field '.$field.' is empty in request. skipping quota check.');
        return;
    }

    my $count = $self->get_accounting_count( $r,
        $field, $metric, $key );

    if( $count >= $threshold ) {
		if( defined $action ) {
			return Mail::MtPolicyd::Plugin::Result->new(
				action => $action,
				abort => 1,
			);
		}
		if( defined $self->chain ) {
			my $chain_result = $self->chain->run( $r );
			return( @{$chain_result->plugin_results} );
		}
    }

	return;
}


sub get_table_name {
    my ( $self, $field ) = @_;
    return( $self->table_prefix . $field );
}

sub get_accounting_count {
    my ( $self, $r, $field, $metric, $key ) = @_;
    my $dbh = Mail::MtPolicyd::SqlConnection->instance->dbh;
    my $where = {
        'key' => $key,
        'time' => $self->get_timekey,
    };
    my $table_name = $dbh->quote_identifier( $self->get_table_name($field) );
    my $where_str = join(' AND ', map {
        $dbh->quote_identifier($_).'='.$dbh->quote($where->{$_})
    } keys %$where );
    my $column_name = $dbh->quote_identifier( $metric );
    my $sql = "SELECT $column_name FROM $table_name WHERE $where_str";

    my $count = $dbh->selectrow_array($sql);

    if( defined $count && $count =~ /^\d+$/ ) {
        return $count;
    }
    return;
}

__PACKAGE__->meta->make_immutable;

1;

