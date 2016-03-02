package Mail::MtPolicyd::Plugin::Condition;

use Moose;
use namespace::autoclean;

# VERSION
# ABSTRACT: mtpolicyd plugin for conditions based on session values

extends 'Mail::MtPolicyd::Plugin';

with 'Mail::MtPolicyd::Plugin::Role::Scoring';
with 'Mail::MtPolicyd::Plugin::Role::UserConfig' => {
	'uc_attributes' => [ 'score', 'action' ],
};
with 'Mail::MtPolicyd::Plugin::Role::PluginChain';

use Mail::MtPolicyd::Plugin::Result;

=head1 DESCRIPTION

Will return an action, score or execute futher plugins if the specified condition matched.

=head1 PARAMETERS

=over

=item key (required)

The name of the variable to check.

Syntax is

  (<scope>:)?<variable-name>

If no scope is give it defaults to request.

Possible scopes are:

=over

=item session, s

Session variables.

=item request, r

Request attribute variables.

=back

Examples:

  session:user_policy
  s:user_policy

  request:queue_id
  r:queue_id
  queue_id

=back

At least one of the following parameters should be given or your condition will
never match:

=over

=item match (default: empty)

Simple string equal match.

=item re_match (default: empty)

Match content of the session variable against an regex.

=item lt_match (default: empty)

Match if numerical less than.

=item gt_match (default: empty)

Match if numerical greater than.

=item invert (default: 0)

If set to 1 the logic will be inverted.

=back

Finally an action must be specified.

First the score will be applied the the action will be executed
or if specified additional plugins will be executed.

=over

=item action (default: empty)

The action to return when the condition matched.

=item score (default: empty)

The score to add if the condition matched.

=item Plugin (default: empty)

Execute this plugins when the condition matched.

=back

=head1 EXAMPLE: use of postfix policy_context

The policy_context of postfix could be used to trigger checks
in mtpolicyd.

To activate additional checks in mtpolicyd from within postfix use may
use a configuration in postfix main.cf like:

  # check, no additional checks
  check_policy_service inet:localhost:12345
  ...
  # check with additional checks!
  check_policy_service { inet:localhost:12345, policy_context=strict_checks }

In mtpolicyd.conf:

  <Plugin if-strict-checks>
    module = "Condition"
    key = "policy_context"
    match = "strict_checks"

    <Plugin strict-check>
      # ...
    </Plugin>
    # more checks ...
  </Plugin>

The policy_context feature will be available in postfix 3.1 and later.

If you need completely different checks consider using the vhost_by_policy_context
(L<mtpolicyd>) option with different virtual hosts. 

=head1 EXAMPLE: execute postgrey action in postfix

If the session variable "greylisting" is "on" return the postfix action "postgrey":

  <Plugin trigger-greylisting>
    module = "Condition"
    key = "greylisting"
    match = "on"
    action = "postgrey"
  </Plugin>

The variable may be set by a UserConfig module like SqlUserConfig.

The postgrey action in postfix may look like:

  smtpd_restriction_classes = postgrey
  postgrey = check_policy_service inet:127.0.0.1:11023

=cut

has 'key' => ( is => 'rw', isa => 'Str', required => 1 );

has 'score' => ( is => 'rw', isa => 'Maybe[Num]' );
has 'action' => ( is => 'rw', isa => 'Maybe[Str]' );

has 'match' => ( is => 'rw', isa => 'Maybe[Str]' );
has 're_match' => ( is => 'rw', isa => 'Maybe[Str]' );

has 'gt_match' => ( is => 'rw', isa => 'Maybe[Num]' );
has 'lt_match' => ( is => 'rw', isa => 'Maybe[Num]' );

has 'invert' => ( is => 'rw', isa => 'Bool', default => 0 );

sub _match {
	my ( $self, $value ) = @_;

	if( defined $self->match &&
			$value eq $self->match ) {
		return 1;
	}

	my $regex = $self->re_match;
	if( defined $regex && $value =~ m/$regex/ ) {
		return 1;
	}

	if( defined $self->lt_match &&
			$value < $self->lt_match ) {
		return 1;
	}

	if( defined $self->gt_match &&
			$value > $self->gt_match ) {
		return 1;
	}

	return 0;
}

sub run {
	my ( $self, $r ) = @_;
	my $key = $self->key;
	my $session = $r->session;
	
	my $value = $r->get( $key );
	if( ! defined $value ) {
		return;
	}

  my $matched = $self->_match($value);
  if( $self->invert ) {
    $matched = ! $matched;
  }

	if( $matched ) {
		$self->log($r, $key.' matched '.$value);
		my $score = $self->get_uc($session, 'score');
		if( defined $score ) {
			$self->add_score($r, $self->name => $score);
		}
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

