package Mail::MtPolicyd::Plugin::Role::ConfigurableFields;

use strict; # make critic happy
use MooseX::Role::Parameterized;

use Moose::Util::TypeConstraints;

# VERSION
# ABSTRACT: role for plugins using configurable fields

parameter fields => (
        isa      => 'HashRef[HashRef]',
        required => 1,
);

role {
	my $p = shift;

	foreach my $attr ( keys %{$p->fields} ) {
    my $value_isa = $p->fields->{$attr}->{'value_isa'};
    delete $p->fields->{$attr}->{'value_isa'};
		has $attr.'_field' => ( 
			is => 'rw',
			isa => 'Maybe[Str]',
      %{$p->fields->{$attr}},
		);
    method 'get_'.$attr.'_value' => sub {
        my ( $self, $r ) = @_;
        return $self->get_configurable_field_value( $r, $attr,
          $value_isa );
    };
	}
};

sub get_configurable_field_value {
  my ( $self, $r, $name, $type ) = @_;
  my $conf_field = $name.'_field';

  my $request_field = $self->$conf_field;
  if( ! defined $request_field || $request_field eq '' ) {
    $self->log( $r, 'no request field configured in '.$conf_field );
    return;
  }

  my $value = $r->attr( $request_field );
  if( ! defined $value || $value eq '' ) {
    $self->log( $r, 'value of field '.$request_field.
      ' not defined or empty' );
    return;
  }

  if( defined $type ) {
    my $constraint = find_type_constraint( $type );
    my $err = $constraint->validate( $value );
    if( defined $err ) {
      $self->log( $r, 'value of field '.$request_field.
        ' failed validation for '.$type.': '.$err );
      return;
    }
  }

  return $value;
}

1;

