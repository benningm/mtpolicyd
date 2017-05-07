package Mail::MtPolicyd::Plugin::Greylist;

use Moose;
use namespace::autoclean;

# VERSION
# ABSTRACT: This plugin implements a greylisting mechanism with an auto whitelist.

extends 'Mail::MtPolicyd::Plugin';
with 'Mail::MtPolicyd::Plugin::Role::Scoring';
with 'Mail::MtPolicyd::Plugin::Role::UserConfig' => {
	'uc_attributes' => [ 'enabled' ],
};

use Mail::MtPolicyd::Plugin::Result;
use Time::Piece;
use Time::Seconds;

=head1 DESCRIPTION

This plugin implements a greylisting mechanism with an auto whitelist.

If a client connects it will return an defer and create a greylisting "ticket"
for the combination of the address of the sender, the senders address and the
recipient address. The ticket will be stored in memcached and will contain the time
when the client was seen for the first time. The ticket will expire after
the max_retry_wait timeout.

The client will be defered until the min_retry_wait timeout has been reached.
Only in the time between the min_retry_wait and max_retry_wait the request will
pass the greylisting test.

When the auto-whitelist is enabled (default) a record for every client which
passes the greylisting test will be stored in the autowl_table.
The table is based on the combination of the sender domain and client_address.
If a client passed the test at least autowl_threshold (default 3) times the greylisting
test will be skipped.
Additional an last_seen timestamp is stored in the record and records which are older
then the autowl_expire_days will expire.

Please note the greylisting is done on a triplet based on the

  client_address + sender + recipient

The auto-white list is based on the

  client_address + sender_domain

=head1 PARAMETERS

=over

=item (uc_)enabled (default: on)

Enable/disable this check.

=item score (default: empty)

Apply an score to this message if it _passed_ the greylisting test. In most cases you want to assign a negative score. (eg. -10)

=item mode (default: passive)

The default is to return no action if the client passed the greylisting test and continue.

You can set this 'accept' or 'dunno' if you want skip further checks.

=item defer_message (default: defer greylisting is active)

This action is returned to the MTA if a message is defered.

If a client retries too fast the time left till min_retry_wait is reach will be appended to the string.

=item min_retry_wait (default: 300 (5m))

A client will have to wait at least for this timeout. (in seconds)

=item max_retry_wait (default: 7200 (2h))

A client must retry to deliver the message before this timeout. (in seconds)

=item use_autowl (default: 1)

Could be used to disable the use of the auto-whitelist.

=item autowl_threshold (default: 3)

How often a client/sender_domain pair must pass the check before it is whitelisted.

=item autowl_expire_days (default: 60)

After how many days an auto-whitelist entry will expire if no client with this client/sender pair is seen.

=item autowl_table (default: autowl)

The name of the table to use.

The database handle specified in the global configuration will be used. (see man mtpolicyd)

=item query_autowl, create_ticket (default: 1)

This options could be used to disable the creation of a new ticket or to query the autowl.

This can be used to catch early retries at the begin of your configuration before more expensive checks are processed.

Example:

  <Plugin greylist>
    module = "Greylist"
    score = -5
    mode = "passive"
    create_ticket = 0
    query_autowl = 0
  </Plugin>
  # ... a lot of RBL checks, etc...
  <Plugin ScoreGreylist>
    module = "ScoreAction"
    threshold = 5
    <Plugin greylist>
      module = "Greylist"
      score = -5
      mode = "passive"
    </Plugin>
  </Plugin>

This will prevent early retries from running thru all checks.

=back

=cut

has 'enabled' => ( is => 'rw', isa => 'Str', default => 'on' );

has 'score' => ( is => 'rw', isa => 'Maybe[Num]' );
has 'mode' => ( is => 'rw', isa => 'Str', default => 'passive');

has 'defer_message' => ( is => 'rw', isa => 'Str', default => 'defer greylisting is active');
has 'append_waittime' => ( is => 'rw', isa => 'Bool', default => 1 );

has 'use_autowl' => ( is => 'rw', isa => 'Bool', default => 1 );
has 'autowl_threshold' => ( is => 'rw', isa => 'Int', default => 3 );

has 'query_autowl' => ( is => 'rw', isa => 'Bool', default => 1 );
has 'create_ticket' => ( is => 'rw', isa => 'Bool', default => 1 );

sub _load_backend {
  my ( $self, $backend ) = @_;
  my $module = $self->$backend->{'module'};
  if( ! defined $module ) {
    die("module must be specified for $backend backend!");
  }
  my $module_full = join('::', 'Mail::MtPolicyd::Plugin::Greylist', $backend, $module);
	my $code = "require ".$module_full.";";
	eval $code; ## no critic (ProhibitStringyEval)
	if($@) {
    die("could not load $backend backend: $@");
  }
  my $instance;
	eval { $instance = $module_full->new(); };
  if($@) {
    die("could not create $backend backend: $@");
  }
  return $instance;
}

has 'AWL' => ( is => 'rw', isa => 'HashRef',
  default => sub { {
    module => 'Sql',
  } },
);
has '_awl' => (
  is => 'ro',
  isa => 'Mail::MtPolicyd::Plugin::Greylist::AWL::Base',
  lazy => 1,
  default => sub {
    my $self = shift;
    return $self->_load_backend('AWL');
  },
);

has 'Ticket' => ( is => 'rw', isa => 'HashRef',
  default => sub { {
    module => 'Memcached',
  } },
);
has '_ticket' => (
  is => 'ro',
  isa => 'Mail::MtPolicyd::Plugin::Greylist::Ticket::Base',
  lazy => 1,
  default => sub {
    my $self = shift;
    return $self->_load_backend('Ticket');
  },
);

sub init {
  my $self = shift;
  $self->_awl->init;
  $self->_ticket->init;
  return;
}

sub run {
	my ( $self, $r ) = @_;
	my $ip = $r->attr('client_address');
	my $sender = $r->attr('sender');
	my $recipient = $r->attr('recipient');
	my @triplet = ($sender, $ip, $recipient);
	my $session = $r->session;

	my $enabled = $self->get_uc( $session, 'enabled' );
	if( $enabled eq 'off' ) {
		return;
	}

	if( $self->use_autowl && $self->query_autowl ) {
		my ( $is_autowl ) = $r->do_cached('greylist-is_autowl', sub {
			$self->is_autowl( $r, @triplet );
		} );
		if( $is_autowl ) {
			$self->log($r, 'client on greylist autowl');
			return $self->success( $r );
		}
	}

	my ( $ticket ) = $r->do_cached('greylist-ticket', sub { $self->_ticket->get($r, @triplet) } );
	if( defined $ticket ) {
		if( $self->_ticket->is_valid( $ticket ) ) {
			$self->log($r, join(',', @triplet).' has a valid greylisting ticket');
			if( $self->use_autowl && ! $r->is_already_done('greylist-autowl-add') ) {
				$self->add_autowl( $r, @triplet );
			}
			$self->_ticket->remove( $r, @triplet );
			return $self->success( $r );
		}
		$self->log($r, join(',', @triplet).' has a invalid greylisting ticket. wait again');
		return( $self->defer( $ticket ) );
	}

	if( $self->create_ticket ) {
		$self->log($r, 'creating new greylisting ticket');
		$self->_ticket->create($r, @triplet);
		return( $self->defer );
	}
	return;
}

sub defer {
	my ( $self, $ticket ) = @_;
	my $message = $self->defer_message;
	if( defined $ticket && $self->append_waittime ) {
		$message .= ' ('.( $ticket - time ).'s left)'
	}
	return( Mail::MtPolicyd::Plugin::Result->new(
		action => $message,
		abort => 1,
	) );
}

sub success {
	my ( $self, $r ) = @_;
	if( defined $self->score && ! $r->is_already_done('greylist-score') ) {
		$self->add_score($r, $self->name => $self->score);
	}
	if( $self->mode eq 'accept' || $self->mode eq 'dunno' ) {
		return( Mail::MtPolicyd::Plugin::Result->new(
			action => $self->mode,
			abort => 1,
		) );
	}
	return;
}

sub _extract_sender_domain {
	my ( $self, $sender ) = @_;
	my $sender_domain;

	if( $sender =~ /@/ ) {
		( $sender_domain ) = $sender =~ /@([^@]+)$/;
	} else { # fallback to just the sender?
		$sender_domain = $sender;
	}

	return($sender_domain);
}

sub is_autowl {
	my ( $self, $r, $sender, $client_ip ) = @_;
	my $sender_domain = $self->_extract_sender_domain( $sender );

	my $count = $r->do_cached('greylist-autowl-count', sub {
		$self->_awl->get( $sender_domain, $client_ip );
	} );

	if( ! defined $count ) {
		$self->log($r, 'client is not on autowl');
		return(0);
	}

	if( $count < $self->autowl_threshold ) {
		$self->log($r, 'client has not yet reached autowl_threshold');
		return(0);
	}

	$self->log($r, 'client has valid autowl. updating database');
	$self->_awl->incr( $sender_domain, $client_ip );
	return(1);
}

sub add_autowl {
	my ( $self, $r, $sender, $client_ip ) = @_;
	my $sender_domain = $self->_extract_sender_domain( $sender );

	my $count = $r->do_cached('greylist-autowl-count', sub {
		$self->_awl->get( $sender_domain, $client_ip );
	} );

	if( defined $count ) {
		$self->log($r, 'client already on autowl, just incrementing count');
		$self->_awl->incr( $sender_domain, $client_ip );
		return;
	}

	$self->log($r, 'creating initial autowl entry');
	$self->_awl->create( $sender_domain, $client_ip );
	return;
}

sub cron {
    my $self = shift;
    my $server = shift;

    if( grep { $_ eq 'hourly' } @_ ) {
        $server->log(3, 'expiring greylist autowl...');
        $self->_awl->expire( $self->autowl_expire_days );
        $server->log(3, 'expiring greylist tickets...');
        $self->_ticket->expire;
    }

    return;
}

__PACKAGE__->meta->make_immutable;

1;

