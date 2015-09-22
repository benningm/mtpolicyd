package Mail::MtPolicyd::Plugin::SMTPVerify;

use Moose;
use namespace::autoclean;

# VERSION
# ABSTRACT: mtpolicyd plugin for remote SMTP address checks

extends 'Mail::MtPolicyd::Plugin';

with 'Mail::MtPolicyd::Plugin::Role::Scoring';
with 'Mail::MtPolicyd::Plugin::Role::UserConfig' => {
	'uc_attributes' => [ 'enabled' ],
};

use Mail::MtPolicyd::Plugin::Result;

use Net::SMTP::Verify;

=head1 DESCRIPTION

This plugin can be used to do remote SMTP verification of addresses.

=head1 Example

To check if the recipient exists on a internal relay and mailbox is able
to recieve a message of this size:

  <Plugin smtp-rcpt-check>
    module = "SMTPVerify"
    
    host = "mail.company.internal"
    sender_field = "sender"
    recipient_field = "recipient"
    # send SIZE to check quota
    size_field = "size"

    temp_fail_action = "defer %MSG%"
    perm_fail_action = "reject %MSG%"
  </Plugin>

Do some very strict checks on sender address:

  <Plugin sender-sender-check>
    module = "SMTPVerify"

    # use a verifiable address in MAIL FROM:
    sender = "horst@mydomain.tld"
    recipient_field = "sender"
    no_starttls_action = "reject sender address does not support STARTTLS"
    temp_fail_action = "defer sender address failed verification: %MSG%"
    perm_fail_action = "reject sender address does not accept mail: %MSG%"
  </Plugin>

Or do advanced checking of sender address and apply a score:

  <Plugin sender-sender-check>
    module = "SMTPVerify"

    # use a verifiable address in MAIL FROM:
    sender = "horst@mydomain.tld"
    recipient_field = "sender"
    check_tlsa = "on"
    check_openpgp = "on"

    temp_fail_score = "1"
    perm_fail_score = "3"

    has_starttls_score = "-1"
    no_starttls_score = "5"
    has_tlsa_score = "-3"
    has_openpgp_score = "-3"
  </Plugin>

Based on the score you can later apply greylisting or other actions.

=head1 Configuration

=head2 Parameters

The module takes the following parameters:

=over

=item (uc_)enabled (default: on)

Enable/disable this check.

=item host (default: empty)

If defined this host will be used for checks instead of a MX.

=item port (default: 25)

Port to use for connection.

=item check_tlsa (default: off)

Set to 'on' to enable check if an TLSA record for the MX exists.

This requires that your DNS resolver returnes the AD flag for DNSSEC
secured records.

=item check_openpgp (default: off)

Set to 'on' to enable check if an OPENPGPKEY records for the
recipients exists.

=item sender_field (default: recipient)

Field to take the MAIL FROM address from.

=item sender (default: empty)

If set use this fixed sender in MAIL FROM instead of sender_field.

=item recipient_field (default: sender)

Field to take the RCPT TO address from.

=item size_field (default: size)

Field to take the message SIZE from.

=item perm_fail_action (default: empty)

Action to return if the remote server returned an permanent error
for this recipient.

The string "%MSG%" will be replaced by the smtp message:

  perm_fail_action = "reject %MSG%"

=item temp_fail_action (default: empty)

Like perm_fail_action but this message is returned when an temporary
error is returned by the remote smtp server.

  temp_fail_action = "defer %MSG%"

=item perm_fail_score (default: empty)

Score to apply when a permanent error is returned for this recipient.

=item temp_fail_score (default: empty)

Score to apply when a temporary error is returned for this recipient.

=item has_starttls_score (default: emtpy)

=item no_starttls_score (default: emtpy)

Score to apply when the smtp server of the recipient
announces support for STARTTLS extension.

=item has_tlsa_score (default: empty)

=item no_tlsa_score (default: empty)

Score to apply when there is a TLSA or no TLSA record
for the remote SMTP server.

=item has_openpgp_score (default: empty)

=item no_openpgp_score (default: empty)

Score to apply when a OPENPGPKEY record for the recpient
exists or not exists.

=back

=cut

has 'enabled' => ( is => 'rw', isa => 'Str', default => 'on' );

has 'host' => ( is => 'ro', isa => 'Maybe[Str]' );
has 'port' => ( is => 'ro', isa => 'Maybe[Int]' );

has 'check_tlsa' => ( is => 'ro', isa => 'Str', default => 'off' );
has 'check_openpgp' => ( is => 'ro', isa => 'Str', default => 'off' );

with 'Mail::MtPolicyd::Plugin::Role::ConfigurableFields' => {
	'fields' => {
    'size' => {
      isa => 'Str',
      default => 'size',
      value_isa => 'Int',
    },
    'sender' => {
      isa => 'Str',
      default => 'recipient',
      value_isa => 'Str',
    },
    'recipient' => {
      isa => 'Str',
      default => 'sender',
      value_isa => 'Str',
    },
  },
};

has 'temp_fail_action' => ( is => 'rw', isa => 'Maybe[Str]' );
has 'temp_fail_score' => ( is => 'rw', isa => 'Maybe[Num]' );
has 'perm_fail_action' => ( is => 'rw', isa => 'Maybe[Str]' );
has 'perm_fail_score' => ( is => 'rw', isa => 'Maybe[Num]' );

has 'has_starttls_score' => ( is => 'rw', isa => 'Maybe[Num]' );
has 'no_starttls_score' => ( is => 'rw', isa => 'Maybe[Num]' );

has 'has_tlsa_score' => ( is => 'rw', isa => 'Maybe[Num]' );
has 'no_tlsa_score' => ( is => 'rw', isa => 'Maybe[Num]' );

has 'has_openpgp_score' => ( is => 'rw', isa => 'Maybe[Num]' );
has 'no_openpgp_score' => ( is => 'rw', isa => 'Maybe[Num]' );

has 'sender' => ( is => 'ro', isa => 'Maybe[Str]' );

# store current request for logging_callback
has '_current_request' => (
  is => 'rw', isa => 'Maybe[Mail::MtPolicyd::Request]'
);

has '_verify' => ( is => 'ro', isa => 'Net::SMTP::Verify', lazy => 1,
  default => sub {
    my $self = shift;
    return Net::SMTP::Verify->new(
      defined $self->host ? ( host => $self->host ) : (),
      defined $self->port ? ( port => $self->port ) : (),
      $self->check_tlsa eq 'on' ? ( tlsa => 1 ) : (),
      $self->check_openpgp eq 'on' ? ( openpgp => 1 ) : (),
      logging_callback => sub {
        my $msg = shift;
        my $r = $self->_current_request;
        if( defined $r ) {
          $self->log( $r, $msg );
        }
        return;
      },
    );
  },
);

sub get_sender {
  my ( $self, $r ) = @_;
  if( defined $self->sender ) {
    return( $self->sender );
  }
  return $self->get_sender_value( $r );
}

sub run {
	my ( $self, $r ) = @_;
  $self->_current_request( $r );
	my $session = $r->session;

	if( $self->get_uc( $session, 'enabled') eq 'off' ) {
		return;
	}
  my $size = $self->get_size_value( $r );
  my $sender = $self->get_sender( $r );
  my $recipient = $self->get_recipient_value( $r );

  if( $r->is_already_done('verify-'.$recipient) ) {
    return;
  }

  my $result = $self->_verify->check(
    $size, $sender, $recipient
  );
  if( ! $result->count ) {
    die('Net::SMTP::Verify returned empty resultset!'); # should not happen
  }
  my ( $rcpt ) = $result->entries;

  $self->_apply_score( $r, $rcpt, 'starttls' );

  if( $self->check_tlsa eq 'on' ) {
    $self->_apply_score( $r, $rcpt, 'tlsa' );
  }
  if( $self->check_openpgp eq 'on' ) {
    $self->_apply_score( $r, $rcpt, 'openpgp' );
  }

  if( $rcpt->is_error ) {
    return $self->_handle_rcpt_error( $r, $rcpt );
  }

  $self->_current_request( undef );
	return;
}

sub _apply_score {
  my ( $self, $r, $rcpt, $name ) = @_;
  my $field = 'has_'.$name;
  my $value = $rcpt->$field;
  if( ! defined $value ) {
    return;
  }

  my $score_field;
  if( $value ) {
    $score_field = 'has_'.$name.'_score';
  } else {
    $score_field = 'no_'.$name.'_score';
  }
  my $score = $self->$score_field;
  if( ! defined $score ) {
    return;
  }

  $self->add_score($r,
    $self->name.'-'.$rcpt->address.'-'.$name => $score );

  return;
}

sub _handle_rcpt_error {
  my ( $self, $r, $rcpt ) = @_;
  my $action;

  if( $rcpt->is_perm_error ) {
    if( defined $self->perm_fail_action ) {
      $action = $self->perm_fail_action;
    }
    if( defined $self->perm_fail_score ) {
		  $self->add_score($r,
        $self->name.'-'.$rcpt->address => $self->perm_fail_score);
    }
  } elsif( $rcpt->is_temp_error ) {
    if( defined $self->temp_fail_action ) {
      $action = $self->temp_fail_action;
    }
    if( defined $self->temp_fail_score ) {
		  $self->add_score($r,
        $self->name.'-'.$rcpt->address => $self->temp_fail_score );
    }
  } else {
    return;
  }

  if( ! defined $action ) {
    return;
  }
  
  my $msg = $rcpt->smtp_message;
  $action =~ s/%MSG%/$msg/;

  return Mail::MtPolicyd::Plugin::Result->new(
    action => $action,
    abort => 1,
  );
}

__PACKAGE__->meta->make_immutable;

1;

