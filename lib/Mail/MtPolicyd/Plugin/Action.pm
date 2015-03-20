package Mail::MtPolicyd::Plugin::Action;

use Moose;
use namespace::autoclean;

# VERSION
# ABSTRACT: mtpolicyd plugin which just returns an action

=head1 DESCRIPTION

This plugin just returns the specified string as action.

=head1 PARAMETERS

=over

=item action (required)

A string with the action to return.

=back

=head1 EXAMPLE

  <Plugin reject-all>
    module = "action"
    # any postfix action will do
    action=reject no reason
  </Plugin>

=cut

extends 'Mail::MtPolicyd::Plugin';

use Mail::MtPolicyd::Plugin::Result;

has 'action' => ( is => 'ro', isa => 'Str', required => 1 );

sub run {
	my ( $self, $r ) = @_;

	return Mail::MtPolicyd::Plugin::Result->new(
		action => $self->action,
		abort => 1,
	);
}

__PACKAGE__->meta->make_immutable;

1;

