package Mail::MtPolicyd::Plugin::ScoreAction;

use Moose;
use namespace::autoclean;

# VERSION
# ABSTRACT: mtpolicyd plugin for running an action based on the score

extends 'Mail::MtPolicyd::Plugin';
with 'Mail::MtPolicyd::Plugin::Role::Scoring';
with 'Mail::MtPolicyd::Plugin::Role::UserConfig' => {
	'uc_attributes' => [ 'threshold' ],
};
with 'Mail::MtPolicyd::Plugin::Role::PluginChain';

=head1 DESCRIPTION

Returns a action based on the score.

=head1 PARAMETERS

=over

=item threshold (required)

If the score is higher than this value the action will be executed.

=item match (default: gt)

If it should match if the score if >= or <= the threshold.

Possible values: gt, lt

=item uc_threshold (default: undef)

If set the value for threshold will be fetched from this
user-config value if defined.

=item score_field (default: score)

Specifies the name of the field the score is stored in.
Could be set if you need multiple scores.

=item action (default: empty)

The action to be executed.

The following patterns in the string will be replaced:

  %IP%, %SCORE%, %SCORE_DETAIL%

=item Plugin (default: empty)

Execute this plugins when the condition matched.

=back

=head1 EXAMPLE

Reject everything with a score >= 15. and do greylisting for the remaining request with a score >=5.

  <Plugin ScoreReject>
    module = "ScoreAction"
    threshold = 15
    action = "reject sender ip %IP% is blocked (score=%SCORE%%SCORE_DETAIL%)"
  </Plugin>
  <Plugin ScoreGreylist>
    module = "ScoreAction"
    threshold = 5
    <Plugin greylist>
      module = "Greylist"
      score = -5
      mode = "passive"
    </Plugin>
  </Plugin>

=cut


use Mail::MtPolicyd::Plugin::Result;

has 'threshold' => ( is => 'ro', isa => 'Num', required => 1 );
has 'match' => ( is => 'rw', isa => 'Str', default => 'gt' );
has 'action' => ( is => 'ro', isa => 'Maybe[Str]' );

sub run {
	my ( $self, $r ) = @_;
	my $score = $self->_get_score($r);
	my $score_detail = $self->_get_score_detail($r);
	my $threshold = $self->get_uc( $r->session, 'threshold' );
	if( $self->match eq 'gt' && $score < $threshold ) {
		return;
	} elsif( $self->match eq 'lt' && $score > $threshold ) {
		return;
	} elsif( $self->match !~ m/^[lg]t$/) {
		die('unknown value for parameter match.');
	}

	my $action = $self->action;
	if( defined $action ) {
		my $ip = $r->attr('client_address');
		if( defined $ip ) {
			$action =~ s/%IP%/$ip/;
		} else {
			$action =~ s/%IP%/unknown/;
		}

		$action =~ s/%SCORE%/$score/;
		if( defined $score_detail ) {
			$action =~ s/%SCORE_DETAIL%/, $score_detail/;
		} else {
			$action =~ s/%SCORE_DETAIL%//;
		}

		return Mail::MtPolicyd::Plugin::Result->new(
			action => $action,
			abort => 1,
		);
	}

	if( defined $self->chain ) {
		my $chain_result = $self->chain->run( $r );
		return( @{$chain_result->plugin_results} );
	}

	return;
}

__PACKAGE__->meta->make_immutable;

1;

