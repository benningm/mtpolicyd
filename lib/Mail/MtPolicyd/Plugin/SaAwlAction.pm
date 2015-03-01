package Mail::MtPolicyd::Plugin::SaAwlAction;

use Moose;
use namespace::autoclean;

# VERSION
# ABSTRACT: mtpolicyd plugin for checking spamassassin AWL reputation

=head1 DESCRIPTION

This plugin will execute an action or score based on a previous lookup
done with SaAwlLookup plugin.

=head1 PARAMETERS

=over

=item result_from (required)

Take the AWL information from the result of this plugin.

The plugin in must be executed before this plugin.

=item (uc_)enabled (default: on)

Enable/disable this plugin.

=item (uc_)mode (default: reject)

If set to 'passive' no action will be returned.

=item reject_message (default: 'sender address/ip has bad reputation')

Could be used to specify an custom reject message.

=item score (default: empty)

A score to apply to the message.

=item score_factor (default: empty)

A factor to apply the SA score to the message.

Do not configure a score if you want to use the factor.

=item threshold (default: 5)

At this threshold the action or score will be applied.

=item match (default: gt)

The default is to match values greater("gt") than the threshold.

When configured with 'lt' AWL scores less than the threshold will
be matched.

=back

=head1 EXAMPLE

Check that AWL is active in your SA/amavis configuration:

  loadplugin Mail::SpamAssassin::Plugin::AWL
  use_auto_whitelist 1

Make sure that mtpolicyd has permissions to read the auto-whitelist db:

  $ usermod -G amavis mtpolicyd
  $ chmod g+rx /var/lib/amavis/.spamassassin
  $ chmod g+r /var/lib/amavis/.spamassassin/auto-whitelist

Make sure it stays like this when its recreated in your SA local.cf:

  auto_whitelist_file_mode 0770

Net::Server does not automatically set supplementary groups.
You have to do that in mtpolicyd.conf:

  group="mtpolicyd amavis"

Permissions may be different on your system.

To check that mtpolicyd can access the file try:

  $ sudo -u mtpolicyd -- head -n0 /var/lib/amavis/.spamassassin/auto-whitelist

Now use it in mtpolicyd.conf:

  <Plugin amavis-reputation>
    module = "SaAwlLookup"
    db_file = "/var/lib/amavis/.spamassassin/auto-whitelist"
  </Plugin>

For whitelisting you may configure it like:

  <Plugin awl-whitelist>
    module = "SaAwlAction"
    result_from = "amavis-reputation"
    mode = "accept"
    match = "lt"
    threshold = "0"
  </Plugin>

Or apply a score based for bad AWL reputation (score > 5):

  <Plugin awl-score-bad>
    module = "SaAwlAction"
    result_from = "amavis-reputation"
    mode = "passive"
    match = "gt"
    threshold = 6
    score = 5
  </Plugin>

Or apply the score value from AWL with an factor:

  <Plugin awl-score-bad>
    module = "SaAwlAction"
    result_from = "amavis-reputation"
    mode = "passive"
    match = "gt"
    threshold = 5
    score_factor = 0.5
  </Plugin>

If the score in AWL is >5 it will apply the score with an factor of 0.5.
When the score in AWL is 8 it will apply a score of 4.

Or just reject all mail with a bad reputation:

  <Plugin awl-reject>
    module = "SaAwlAction"
    result_from = "amavis-reputation"
    mode = "reject"
    match = "gt"
    threshold = 5
    reject_message = "bye bye..."
  </Plugin>

=cut

extends 'Mail::MtPolicyd::Plugin';
with 'Mail::MtPolicyd::Plugin::Role::Scoring';
with 'Mail::MtPolicyd::Plugin::Role::UserConfig' => {
	'uc_attributes' => [ 'enabled', 'mode' ],
};

use Mail::MtPolicyd::Plugin::Result;

has 'result_from' => ( is => 'rw', isa => 'Str', required => 1 );
has 'enabled' => ( is => 'rw', isa => 'Str', default => 'on' );
has 'mode' => ( is => 'rw', isa => 'Str', default => 'reject' );

has 'reject_message' => (
	is => 'ro', isa => 'Str', default => 'sender address/ip has bad reputation',
);

has 'score' => ( is => 'rw', isa => 'Maybe[Num]' );
has 'score_factor' => ( is => 'rw', isa => 'Maybe[Num]' );

has 'min_count' => ( is => 'rw', isa => 'Int', default => 10 );

has 'threshold' => ( is => 'rw', isa => 'Num', default => 5 );
has 'match' => ( is => 'rw', isa => 'Str', default => 'gt');

sub matches {
    my ( $self, $score ) = @_;

    if( $self->match eq 'gt' && $score >= $self->threshold ) {
        return 1;
    } elsif ( $self->match eq 'lt' && $score <= $self->threshold ) {
        return 1;
    }

    return 0;
}

sub run {
	my ( $self, $r ) = @_;
	my $addr = $r->attr('sender');
	my $ip = $r->attr('client_address');
	my $session = $r->session;

	my $enabled = $self->get_uc( $session, 'enabled' );
	if( $enabled eq 'off' ) {
		return;
	}

	my $result_key = 'sa-awl-'.$self->result_from.'-result';
	if( ! defined $session->{$result_key} ) {
		$self->log( $r, 'no SaAwlLookup result for '.$self->result_from.' found!');
		return;
	}
	my ( $count, $score ) = @{$session->{$result_key}};
	if( ! defined $count || ! defined $score) {
		return; # there was no entry in AWL
	}
    
    if( $count < $self->min_count ) {
	    $self->log( $r, 'sender awl reputation below min_count' );
    }

    if( ! $self->matches( $score ) ) {
        return;
    }

	$self->log( $r, 'matched SA AWL threshold action '.$self->name );
	if( ! $r->is_already_done('sa-awl-'.$self->name.'-score') ) {
        if( $self->score ) {
		    $self->add_score($r, $self->name => $self->score);
        } elsif( $self->score_factor ) {
		    $self->add_score($r, $self->name => $score * $self->score_factor);
        }
	}

	my $mode = $self->get_uc( $session, 'mode' );
	if( $mode eq 'reject' ) {
		return Mail::MtPolicyd::Plugin::Result->new(
			action => $self->_get_reject_action( $addr, $ip, $score ),
			abort => 1,
		);
	}
	if( $mode eq 'accept' || $mode eq 'dunno' ) {
		return Mail::MtPolicyd::Plugin::Result->new_dunno;
	}

	return;
}

sub _get_reject_action {
	my ( $self, $sender, $ip, $score ) = @_;
	my $message = $self->reject_message;
	$message =~ s/%IP%/$ip/;
	$message =~ s/%SENDER%/$sender/;
	$message =~ s/%SCORE%/$score/;
	return('reject '.$message);
}

__PACKAGE__->meta->make_immutable;

1;

