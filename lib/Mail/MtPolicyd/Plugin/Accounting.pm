package Mail::MtPolicyd::Plugin::Accounting;

use Moose;
use namespace::autoclean;

# VERSION
# ABSTRACT: mtpolicyd plugin for accounting in sql tables

extends 'Mail::MtPolicyd::Plugin';
with 'Mail::MtPolicyd::Plugin::Role::UserConfig' => {
	'uc_attributes' => [ 'enabled' ],
};
with 'Mail::MtPolicyd::Plugin::Role::SqlUtils';

use Mail::MtPolicyd::Plugin::Result;

use Time::Piece;

=head1 DESCRIPTION

This plugin can be used to do accounting based on request fields.

=head1 SYNOPSIS

  <Plugin acct-clients>
    module = "Accounting"
    # per ip and user
    fields = "client_address,sasl_username"
    # statistics per month
    time_pattern = "%Y-%m"
    table_prefix = "acct_"
  </Plugin>

This will create a table acct_client_address and a table acct_sasl_username.

If a request is recieved containing the field the plugin will update the row
in the fields table. The key is the fields value(ip or username) and the time
string build from the time_pattern.

For each key the following counters are stored:

  * count
  * count_rcpt (count per recipient)
  * size
  * size_rcpt  (size * recipients)

The resulting tables will look like:

  mysql> select * from acct_client_address;
  +----+--------------+---------+-------+------------+--------+-----------+
  | id | key          | time    | count | count_rcpt | size   | size_rcpt |
  +----+--------------+---------+-------+------------+--------+-----------+
  |  1 | 192.168.0.1  | 2014-12 |    11 |         11 | 147081 |    147081 |
  |  2 | 192.168.1.1  | 2014-12 |     1 |          1 |  13371 |     13371 |
  | 12 | 192.168.2.1  | 2014-12 |    10 |        100 | 133710 |   1337100 |
  ...

=head2 PARAMETERS

The module takes the following parameters:

=over

=item (uc_)enabled (default: on)

Enable/disable this check.

=item fields (required)

A comma separated list of fields used for accounting.

For each field a table will be created.

For a list of available fields see postfix documentation:

http://www.postfix.org/SMTPD_POLICY_README.html

=item time_pattern (default: "%Y-%m")

A format string for building the time key used to store counters.

Default is to build counters on a monthly base.

For example use:

  * "%Y-%W" for weekly
  * "%Y-%m-%d" for daily

See "man date" for format string sequences.

=item table_prefix (default: "acct_")

A prefix to add to every table.

The table name will be the prefix + field_name.

=back

=cut

has 'enabled' => ( is => 'rw', isa => 'Str', default => 'on' );

has 'fields' => ( is => 'rw', isa => 'Str', required => 1);
has '_fields' => ( is => 'ro', isa => 'ArrayRef', lazy => 1,
    default => sub {
        my $self = shift;
        return [ split('\s*,\s*', $self->fields) ];
    },
);

has 'time_pattern' => ( is => 'rw', isa => 'Str', default => '%Y-%m');

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

    if( $r->is_already_done( $self->name.'-acct' ) ) {
        $self->log( $r, 'accounting already done for this mail, skipping...');
        return;
	}

    my $metrics = $self->get_request_metrics( $r );

    foreach my $field ( @{$self->_fields} ) {
        my $key = $r->attr($field);
        if( ! defined $key ) {
            $self->log( $r, $field.' not defined in request, skipping...');
            next;
        }
        $self->log( $r, 'updating accounting info for '.$field.' '.$key);
        $self->update_accounting($field, $key, $metrics);
    }

	return;
}

sub init {
    my $self = shift;
    $self->check_sql_tables( %{$self->_table_definitions} );
    return;
}

has '_single_table_create' => ( is => 'ro', isa => 'HashRef', lazy => 1,
    default => sub { {
        'mysql' => 'CREATE TABLE %TABLE_NAME% (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `key` VARCHAR(255) NOT NULL,
    `time` VARCHAR(255) NOT NULL,
    `count` INT UNSIGNED NOT NULL,
    `count_rcpt` INT UNSIGNED NOT NULL,
    `size` INT UNSIGNED NOT NULL,
    `size_rcpt` INT UNSIGNED NOT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `time_key` (`key`, `time`),
    KEY(`key`),
    KEY(`time`)
  ) ENGINE=MyISAM  DEFAULT CHARSET=latin1',
        'SQLite' => 'CREATE TABLE %TABLE_NAME% (
    `id` INTEGER PRIMARY KEY AUTOINCREMENT,
    `key` VARCHAR(255) NOT NULL,
    `time` VARCHAR(255) NOT NULL,
    `count` INT UNSIGNED NOT NULL,
    `count_rcpt` INT UNSIGNED NOT NULL,
    `size` INT UNSIGNED NOT NULL,
    `size_rcpt` INT UNSIGNED NOT NULL
)',
    } }
);

sub get_table_name {
    my ( $self, $field ) = @_;
    return( $self->table_prefix . $field );
}

has '_table_definitions' => ( is => 'ro', isa => 'HashRef', lazy => 1,
    default => sub {
        my $self = shift;
        my $tables = {};
        foreach my $field ( @{$self->_fields} ) {
            my $table_name = $self->get_table_name($field);
            $tables->{$table_name} = $self->_single_table_create;
        }
        return $tables;
    },
);

sub get_request_metrics {
    my ( $self, $r ) = @_;
    my $recipient_count = $r->attr('recipient_count');
    my $size = $r->attr('size');
    my $metrics = {};
	my $rcpt_cnt = defined $recipient_count ? $recipient_count : 1;
	$metrics->{'size'} = defined $size ? $size : 0;
    $metrics->{'count'} = 1;
    $metrics->{'count_rcpt'} = $rcpt_cnt ? $rcpt_cnt : 1;
    $metrics->{'size_rcpt'} = $rcpt_cnt ? $size * $rcpt_cnt : $size;

    return( $metrics );
}

sub update_accounting {
    my ( $self, $field, $key, $metrics ) = @_;

    eval {
        $self->update_accounting_row($field, $key, $metrics);
    };
    if( $@ =~ /^accounting row does not exist/ ) {
        $self->insert_accounting_row($field, $key, $metrics);
    } elsif( $@ ) {
        die( $@ );
    }

    return;
}

sub insert_accounting_row {
    my ( $self, $field, $key, $metrics ) = @_;
    my $dbh = Mail::MtPolicyd::SqlConnection->instance->dbh;
    my $table_name = $dbh->quote_identifier( $self->get_table_name($field) );
    my $values = {
        'key' => $key,
        'time' => $self->get_timekey,
        %$metrics,
    };
    my $col_str = join(', ', map {
        $dbh->quote_identifier($_)
    } keys %$values);
    my $values_str = join(', ', map {
        $dbh->quote($_)
    } values %$values);

    my $sql = "INSERT INTO $table_name ($col_str) VALUES ($values_str)";
    $self->execute_sql($sql);

    return;
}

sub update_accounting_row {
    my ( $self, $field, $key, $metrics ) = @_;
    my $dbh = Mail::MtPolicyd::SqlConnection->instance->dbh;
    my $table_name = $dbh->quote_identifier( $self->get_table_name($field) );
    my $where = {
        'key' => $key,
        'time' => $self->get_timekey,
    };

    my $values_str = join(', ', map {
        $dbh->quote_identifier($_).'='.
            $dbh->quote_identifier($_).'+'.$dbh->quote($metrics->{$_})
    } keys %$metrics);
    my $where_str = join(' AND ', map {
        $dbh->quote_identifier($_).'='.$dbh->quote($where->{$_})
    } keys %$where );

    my $sql = "UPDATE $table_name SET $values_str WHERE $where_str";
    my $rows = $dbh->do($sql);
    if( $rows == 0 ) {
        die('accounting row does not exist');
    }

    return;
}

__PACKAGE__->meta->make_immutable;

1;

