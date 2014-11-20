package Mail::MtPolicyd::Plugin::Stress;

use Moose;
use namespace::autoclean;

# VERSION
# ABSTRACT: mtpolicyd plugin for postfix stress mode

extends 'Mail::MtPolicyd::Plugin';

with 'Mail::MtPolicyd::Plugin::Role::UserConfig' => {
	'uc_attributes' => [ 'action' ],
};
with 'Mail::MtPolicyd::Plugin::Role::PluginChain';

use Mail::MtPolicyd::Plugin::Result;

=head1 DESCRIPTION

Will return an action or execute futher plugins if postfix signals stress.

See postfix STRESS_README.

=head1 PARAMETERS

An action must be specified:

=over

=item action (default: empty)

The action to return when under stress.

=item Plugin (default: empty)

Execute this plugins when under stress.

=back

=head1 EXAMPLE: defer clients when under stress

To defer clients under stress:

  <Plugin stress>
    module = "Stress"
    action = "defer please try again later"
  </Plugin>

This will return an defer action and execute no futher tests.

You may want to do some whitelisting for prefered clients before this action.

=cut

has 'action' => ( is => 'rw', isa => 'Maybe[Str]' );

sub run {
	my ( $self, $r ) = @_;

	my $stress = $r->attr('stress');

	if( defined $stress && $stress eq 'yes' ) {
		$self->log($r, 'MTA has stress feature turned on');

		my $action = $self->get_uc($session, 'action');
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

__PACKAGE__->meta->make_immutable;

1;

