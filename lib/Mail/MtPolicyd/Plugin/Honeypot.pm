package Mail::MtPolicyd::Plugin::Honeypot;

use Moose;
use namespace::autoclean;

# VERSION
# ABSTRACT: mtpolicyd plugin for creating an honeypot

extends 'Mail::MtPolicyd::Plugin';
with 'Mail::MtPolicyd::Plugin::Role::Scoring';
with 'Mail::MtPolicyd::Plugin::Role::UserConfig' => {
	'uc_attributes' => [ 'enabled' ],
};
with 'Mail::MtPolicyd::Plugin::Role::PluginChain';

use Mail::MtPolicyd::Plugin::Result;

=head1 DESCRIPTION

The Honeypot plugin creates an honeypot to trap IPs sending to unused recipient addresses.

The plugin requires that you define unused recipient addresses as honeypots.
These addresses can be specified by the recipients and recipients_re parameters.

Each time an IP tries to send an mail to one of these honeypots the message will be
reject if mode is 'reject' and an scoring is applied.
The IP is also added to a temporary IP blacklist till an timeout is reached (parameter expire).
All IPs on this blacklist will also be rejected if mode is 'reject' and scoring is applied.

=head1 EXAMPLE

  <Plugin honeypot>
    module = "Honeypot"
    recipients = "bob@company.com,joe@company.com"
    recipients_re = "^(tic|tric|trac)@(gmail|googlemail)\.de$"
  </Plugin>

=head1 PARAMETERS

=over

=item (uc_)enabled (default: on)

Enable/disable this check.

=item score (default: empty)

Apply an score to this message if it is send to an honeypot address or it has been
added to the honeypot before by sending an mail to an honeypot.

=item mode (default: reject)

The default is to return an reject.

Change to 'passive' if you just want scoring.

=item recipients (default: '')

A comma separated list of recipients to use as honeypots.

=item recipients_re (default: '')

A comma separated list of regular expression to match against the
recipient to use them as honeypots.

=item reject_message (default: 'trapped by honeypod')

A string to return with the reject action.

=item expire (default: 7200 (2h))

Time in seconds till the client_ip is removed from the honeypot.

=item Plugin (default: empty)

Execute this plugins when the condition matched.

=back

=cut

has 'enabled' => ( is => 'rw', isa => 'Str', default => 'on' );

has 'score' => ( is => 'rw', isa => 'Maybe[Num]' );
has 'mode' => ( is => 'rw', isa => 'Str', default => 'reject');

has 'recipients' => ( is => 'rw', isa => 'Str', default => '' );
has 'recipients_re' => ( is => 'rw', isa => 'Str', default => '' );

has _recipients => ( is => 'ro', isa => 'ArrayRef', lazy => 1,
	default => sub {
		my $self = shift;
		return  [ split(/\s*,\s*/, $self->recipients) ];
	},
);

has _recipients_re => ( is => 'ro', isa => 'ArrayRef', lazy => 1,
	default => sub {
		my $self = shift;
		return  [ split(/\s*,\s*/, $self->recipients_re) ];
	},
);

has 'reject_message' => ( is => 'rw', isa => 'Str', default => 'trapped by honeypod' );

has 'expire' => ( is => 'rw', isa => 'Int', default => 60*60*2 );

sub run {
	my ( $self, $r ) = @_;
	my $ip = $r->attr('client_address');
	my $recipient = $r->attr('recipient');
	my $session = $r->session;

	my $enabled = $self->get_uc( $session, 'enabled' );
	if( $enabled eq 'off' ) {
		return;
	}

	if( $self->is_in_honeypot( $r, $ip ) ) {
		return $self->trapped_action;
	}
	if( $self->is_honeypot_recipient( $recipient ) ) {
		$self->add_to_honeypot( $r, $ip );
		return $self->trapped_action;
	}

	return;
}

sub trapped_action {
	my ( $self, $r ) = @_;

	if( $self->mode eq 'reject' ) {
		return( Mail::MtPolicyd::Plugin::Result->new(
			action => 'reject '.$self->reject_message,
			abort => 1,
		) );
	}
	if( defined $self->score && ! $r->is_already_done($self->name.'-score') ) {
		$self->add_score($r, $self->name => $self->score);
	}
	if( defined $self->chain ) {
		my $chain_result = $self->chain->run( $r );
		return( @{$chain_result->plugin_results} );
	}
	return;
}

sub is_honeypot_recipient {
	my ( $self, $recipient ) = @_;

	if( $self->is_in_recipients( $recipient )
			|| $self->is_in_recipients_re( $recipient ) ) {
		return(1);
	}

	return(0);
}

sub is_in_recipients {
	my ( $self, $recipient ) = @_;

	if( grep { $_ eq $recipient } @{$self->_recipients} ) {
		return(1);
	}

	return(0);
}

sub is_in_recipients_re {
	my ( $self, $recipient ) = @_;

	if( grep { $recipient =~ /$_/  } @{$self->_recipients_re} ) {
		return(1);
	}

	return(0);
}

sub is_in_honeypot {
	my ( $self, $r, $ip ) = @_;
	my $key = join(",", $self->name, $ip );
	if( my $ticket = $r->server->memcached->get( $key ) ) {
		return( 1 );
	}
	return;
}

sub add_to_honeypot {
	my ( $self, $r, $ip ) = @_;
	my $key = join(",", $self->name, $ip );
	$r->server->memcached->set( $key, '1', $self->expire );
	return;
}

__PACKAGE__->meta->make_immutable;

1;

