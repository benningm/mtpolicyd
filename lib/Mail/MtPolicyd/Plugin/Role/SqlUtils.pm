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
    my $self = shift;
	my $dbh = Mail::MtPolicyd::SqlConnection->instance->dbh;

    # TODO

    return;
}

sub execute_sql {
    my ( $self, $sql, @params ) = @_;
	my $dbh = Mail::MtPolicyd::SqlConnection->instance->dbh;
    my $sth = $dbh->prepare( $sql );
    $sth->execute( @params );
    return $sth;
}

1;

