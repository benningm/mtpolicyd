package Mail::MtPolicyd::Plugin::DBL;

use Moose;
use namespace::autoclean;

# VERSION
# ABSTRACT: mtpolicyd plugin for checking helo,sender domain,rdns against an DBL

extends 'Mail::MtPolicyd::Plugin';
with 'Mail::MtPolicyd::Plugin::Role::Scoring';
with 'Mail::MtPolicyd::Plugin::Role::UserConfig' => {
	'uc_attributes' => [ 'enabled', 'sender_mode', 'helo_name_mode',
		'reverse_client_name_mode' ],
};

use Mail::MtPolicyd::Plugin::Result;

use Mail::RBL;

=head1 DESCRIPTION

Will check the sender, helo and reverse_client_name against an domain black list.

=head1 PARAMETERS

=over

=item domain (required)

The domain of the blacklist to query.

=item enabled (default: on)

Set to 'off' to disable plugin.

Possible values: on,off

=item uc_enabled (default: empty)

If specified the give variable within the session will overwrite the value of 'enabled' if set.

=item (uc_)sender_mode (default: reject), (uc_)helo_name_mode (default: passive), (uc_)reverse_client_name_mode (default: reject)

Should the plugin return an reject if the check matches (reject) or
just add an score (passive).

Possible values: reject, passive

=item sender_score (default: 5)

=item helo_name_score (default: 1)

=item reverse_client_name_score (default: 2.5)

Add the given score if check matched.

=item score_field (default: score)

Name of the session variable the score is stored in.
Could be used if multiple scores are needed.

=back

=head1 EXAMPLE

Only the sender and the reverse_client_name check will cause an
action to be executed (mode).
The helo check will only add an score.

  <Plugin sh_dbl>
    module = "RBL"
    #enabled = "on"
    uc_enabled = "spamhaus"
    domain="dbl.spamhaus.org"

    # do not reject based on helo
    #helo_name_mode=passive
    #helo_name_score=1
    #sender_mode=reject
    #sender_score=5
    #reverse_client_name_mode=reject
    #reverse_client_name_score=2.5
  </Plugin>

=cut

has 'domain' => ( is => 'rw', isa => 'Str', required => 1 );

has 'enabled' => ( is => 'rw', isa => 'Str', default => 'on' );

has 'sender_mode' => ( is => 'rw', isa => 'Str', default => 'reject' );
has 'sender_score' => ( is => 'rw', isa => 'Maybe[Num]', default => 5 );

has 'reverse_client_name_mode' => ( is => 'rw', isa => 'Str', default => 'reject' );
has 'reverse_client_name_score' => ( is => 'rw', isa => 'Maybe[Num]', default => 2.5 );

has 'helo_name_mode' => ( is => 'rw', isa => 'Str', default => 'passive' );
has 'helo_name_score' => ( is => 'rw', isa => 'Maybe[Num]', default => 1 );

has 'reject_message' => ( is => 'rw', isa => 'Str',
	default => '%CHECK% rejected (%HOSTNAME%%INFO%)' );

has '_rbl' => (
	is => 'ro', isa => 'Mail::RBL', lazy => 1,
	default => sub {
		my $self = shift;
		Mail::RBL->new($self->domain)
	},
);

sub run {
	my ( $self, $r ) = @_;
	my $session = $r->session;

	my $enabled = $self->get_uc( $session, 'enabled' );
	if( $enabled eq 'off' ) {
		return;
	}

	foreach my $check ( 'sender', 'reverse_client_name', 'helo_name') {
		my $hostname = $self->_get_hostname($r, $check);
		if( ! defined $hostname ) {
			next;
		}

		my ( $ip_result, $info ) = $r->do_cached( $self->name.'-'.$check.'-result',
			sub { $self->_rbl->check_rhsbl( $hostname ) } );
		if( ! defined $ip_result ) {
			$self->log($r, 'domain '.$hostname.' not on '.$self->domain.' blacklist');
			next;
		}

		$self->log($r, 'domain '.$hostname.' is on '.$self->domain.' blacklist ('.$info.')');

		my $score_attr = $check.'_score';
		if( defined $self->$score_attr &&
				! $r->is_already_done($self->name.'-'.$check.'-score') ) {
			$self->add_score($r, $self->name.'-'.$check => $self->$score_attr );
		}

		my $mode = $self->get_uc( $session, $check.'_mode' );
		if( $mode eq 'reject' ) {
			return Mail::MtPolicyd::Plugin::Result->new(
				action => $self->_get_reject_action($check, $hostname, $info),
				abort => 1,
			);
		}
	}

	return;
}

sub _get_hostname {
	my ( $self, $r, $field ) = @_;
	my $value = $r->attr($field);
	if( ! defined $value ) {
		die($field.' not defined in request!');
	}
	# skip unknown and empty fields
	if( $value eq 'unknown' || $value eq '' ) {
		return;
	}
	# skip ip addresses
	if( $value =~ m/^\d+\.\d+\.\d+\.\d+$/) {
		return;
	}
	# skip ip6 addresses
	if( $value =~ m/:/) {
		return;
	}
	# skip unqualified hostnames
	if( $value !~ m/\./) {
		return;
	}

	if( $field eq 'sender') {
		$value =~ s/^[^@]*@//;
	}
	return($value);
}

sub _get_reject_action {
	my ( $self, $check, $hostname, $info ) = @_;
	my $msg = $self->reject_message;	
	$msg =~ s/%CHECK%/$check/;
	$msg =~ s/%HOSTNAME%/$hostname/;
	if( defined $info ) {
		$msg =~ s/%INFO%/, $info/;
	} else {
		$msg =~ s/%INFO%//;
	}

	return 'reject '.$msg;
}

__PACKAGE__->meta->make_immutable;

1;

