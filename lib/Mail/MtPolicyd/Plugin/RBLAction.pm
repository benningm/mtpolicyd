package Mail::MtPolicyd::Plugin::RBLAction;

use Moose;
use namespace::autoclean;

# VERSION
# ABSTRACT: mtpolicyd plugin for checking the client-address against an RBL

=head1 DESCRIPTION

This plugin can be used when a more complex evaluation of an RBL result is needed that just match/not-match.

With this plugin you can take the same actions as with the RBL plugin, but it can match the result with a regular expression. This allows to take action based on the category in combined blacklists.

=cut

extends 'Mail::MtPolicyd::Plugin';
with 'Mail::MtPolicyd::Plugin::Role::Scoring';
with 'Mail::MtPolicyd::Plugin::Role::UserConfig' => {
	'uc_attributes' => [ 'enabled' ],
};

use Mail::MtPolicyd::Plugin::Result;

use Mail::RBL;

=head1 PARAMETERS

=over

=item result_from (required)

Use the query result of this RBL check.

=item (uc_)enabled (default: on)

Enable/disable this check.

=item mode (default: reject)

=over

=item reject

Reject the message. (reject)

=item accept

Stop processing an accept this message. (dunno)

=item passive

Only apply the score if one is given.

=back

=item re_match (required)

An regular expression to check the RBL result.

=item reject_message (default: delivery from %IP% rejected %INFO%)

A pattern for the reject message if mode is set to 'reject'.

=item score (default: empty)

Apply this score if the check matched.

=back

=head1 EXAMPLE

  <Plugin spamhaus-rbl>
    module = "RBL"
    mode = "passive"
    domain="zen.spamhaus.org"
  </Plugin>
  <Plugin spamhaus-rbl-sbl>
    module = "RBLAction"
    result_from = "spamhaus-rbl"
    mode = "passive"
    re_match = "^127\.0\.0\.[23]$"
    score = 5
  </Plugin>
  <Plugin spamhaus-rbl-xbl>
    module = "RBLAction"
    result_from = "spamhaus-rbl"
    mode = "passive"
    re_match = "^127\.0\.0\.[4-7]$"
    score = 5
  </Plugin>
  <Plugin spamhaus-rbl-pbl>
    module = "RBLAction"
    result_from = "spamhaus-rbl"
    mode = "passive"
    re_match = "^127\.0\.0\.1[01]$"
    score = 3
  </Plugin>
  
=cut

has 'result_from' => ( is => 'rw', isa => 'Str', required => 1 );
has 'enabled' => ( is => 'rw', isa => 'Str', default => 'on' );
has 'mode' => ( is => 'rw', isa => 'Str', default => 'reject' );

has 're_match' => ( is => 'rw', isa => 'Str', required => 1 );

has 'reject_message' => (
	is => 'ro', isa => 'Str', default => 'delivery from %IP% rejected %INFO%',
);

has 'score' => ( is => 'rw', isa => 'Maybe[Num]' );

sub run {
	my ( $self, $r ) = @_;
	my $ip = $r->attr('client_address');
	my $session = $r->session;

	my $enabled = $self->get_uc( $session, 'enabled' );
	if( $enabled eq 'off' ) {
		return;
	}

	my $result_key = 'rbl-'.$self->result_from.'-result';
	if( ! defined $session->{$result_key} || ref( $session->{$result_key} ) ne 'ARRAY' ) {
		$self->log( $r, 'no RBL check result for '.$self->name.' found!');
		return;
	}
	my ( $ip_result, $info ) = @{$session->{$result_key}};

	if( ! defined $ip_result ) {
		return;
	}

	my $regex = $self->re_match;
	if( $ip_result->addr !~ m/$regex/ ) {
		$self->log( $r, $ip_result->addr.' did not match regex '.$regex);
		return;
	}

	$self->log( $r, $ip_result->addr.' match regex '.$regex);
	if( defined $self->score && ! $r->is_already_done('rbl-'.$self->name.'-score') ) {
		$self->add_score($r, $self->name => $self->score);
	}

	if( $self->mode eq 'reject' ) {
		return Mail::MtPolicyd::Plugin::Result->new(
			action => $self->_get_reject_action($ip, $info),
			abort => 1,
		);
	}
	if( $self->mode eq 'accept' ) {
		return Mail::MtPolicyd::Plugin::Result->new_dunno;
	}

	return;
}

sub _get_reject_action {
	my ( $self, $ip, $info ) = @_;
	my $message = $self->reject_message;
	$message =~ s/%IP%/$ip/;
	if( defined $info && $info ne '' ) {
		$message =~ s/%INFO%/($info)/;
	} else {
		$message =~ s/%INFO%//;
	}
	return('reject '.$message);
}

__PACKAGE__->meta->make_immutable;

1;

