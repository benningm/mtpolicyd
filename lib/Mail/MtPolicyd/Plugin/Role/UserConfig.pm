package Mail::MtPolicyd::Plugin::Role::UserConfig;

use strict; # make critic happy
use MooseX::Role::Parameterized;

# VERSION
# ABSTRACT: role for plugins using per user/request configuration

parameter uc_attributes => (
        isa      => 'ArrayRef',
        required => 1,
);

role {
	my $p = shift;

	foreach my $attribute ( @{$p->uc_attributes} ) {
		has 'uc_'.$attribute => ( 
			is => 'rw',
			isa => 'Maybe[Str]',
		);
	}
};

sub get_uc {
	my ($self, $session, $attr) = @_;
	my $uc_attr = 'uc_'.$attr;
	
	if( ! $self->can($uc_attr) ) {
		die('there is no user config attribute '.$uc_attr.'!');
	}
	if( ! defined $self->$uc_attr ) {
		return $self->$attr;
	}
	my $session_value = $session->{$self->$uc_attr};
	if( ! defined $session_value ) {
		return $self->$attr;
	}
	return $session_value;
}

1;

