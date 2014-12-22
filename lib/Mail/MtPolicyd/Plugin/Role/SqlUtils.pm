package Mail::MtPolicyd::Plugin::Role::SqlUtils;

use strict;
use Moose::Role;

use Mail::MtPolicyd::SqlConnection;

# ABSTRACT: role with support function for plugins using sql
# VERSION

before 'init' => sub {
    my $self = shift;
    if( ! Mail::MtPolicyd::SqlConnection->is_initialized ) {
        die('no sql database initialized, but required for plugin '.$self->name);
    }
    return;
};

sub sql_table_exists {
    my ( $self, $name ) = @_;
	my $dbh = Mail::MtPolicyd::SqlConnection->instance->dbh;
    my $sql = 'SELECT * FROM '.$dbh->quote_identifier($name).' WHERE 1=0;';
    eval { $dbh->do($sql); };
    if( $@ ) {
        return 0;
    }
    return 1;
}

sub create_sql_table {
    my ( $self, $name, $definitions ) = @_;
	my $dbh = Mail::MtPolicyd::SqlConnection->instance->dbh;
    my $table_name = $dbh->quote_identifier($name);
    my $sql;
    my $driver = $dbh->{Driver}->{Name};

    if( defined $definitions->{$driver} ) {
        $sql = $definitions->{$driver};
    } elsif ( defined $definitions->{'*'} ) {
        $sql = $definitions->{'*'};
    } else {
        die('no data definition for table '.$name.'/'.$driver.' found');
    }

    $sql =~ s/%TABLE_NAME%/$table_name/g;
    $dbh->do( $sql );
    return;
}

sub check_sql_tables {
    my ( $self, %tables ) = @_;
    foreach my $table ( keys %tables ) {
        if( ! $self->sql_table_exists( $table ) ) {
            eval { $self->create_sql_table( $table, $tables{$table} ) };
            if( $@ ) {
                die('sql table '.$table.' does not exist and creating it failed: '.$@);
            }
        }
    }
}

sub execute_sql {
    my ( $self, $sql, @params ) = @_;
	my $dbh = Mail::MtPolicyd::SqlConnection->instance->dbh;
    my $sth = $dbh->prepare( $sql );
    $sth->execute( @params );
    return $sth;
}

1;

