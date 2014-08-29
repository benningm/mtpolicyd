package Mail::MtPolicyd::Plugin::SetField;

use Moose;
use namespace::autoclean;

# VERSION
# ABSTRACT: mtpolicyd plugin which just sets and key=value in the session

=head1 DESCRIPTION

This plugin can be used to set key/values within the session.

=head1 EXAMPLE

  <Plugin set-scanned>
    module = "SetField"
    key=mail-is-scanned
    value=1
  </Plugin>

=cut

extends 'Mail::MtPolicyd::Plugin';

use Mail::MtPolicyd::Plugin::Result;

has 'key' => ( is => 'rw', isa => 'Str', required => 1 );
has 'value' => ( is => 'rw', isa => 'Str', required => 1 );

sub run {
	my ( $self, $r ) = @_;
	$r->session->{$self->key} = $self->value;
	return;
}

__PACKAGE__->meta->make_immutable;

1;

