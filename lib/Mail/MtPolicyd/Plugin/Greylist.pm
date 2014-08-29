package Mail::MtPolicyd::Plugin::Greylist;

use Moose;
use namespace::autoclean;

# VERSION
# ABSTRACT: mtpolicyd plugin for checking the client-address against an RBL

extends 'Mail::MtPolicyd::Plugin';
with 'Mail::MtPolicyd::Plugin::Role::Scoring';
with 'Mail::MtPolicyd::Plugin::Role::UserConfig' => {
	'uc_attributes' => [ 'enabled' ],
};

use Mail::MtPolicyd::Plugin::Result;
use Time::Piece::MySQL;
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

This can be used to catch early retries at the begin of your configuration before more expensive checks a processes.

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

has 'min_retry_wait' => ( is => 'rw', isa => 'Int', default => 60*5 );
has 'max_retry_wait' => ( is => 'rw', isa => 'Int', default => 60*60*2 );

has 'use_autowl' => ( is => 'rw', isa => 'Bool', default => 1 );
has 'autowl_threshold' => ( is => 'rw', isa => 'Int', default => 3 );
has 'autowl_expire_days' => ( is => 'rw', isa => 'Int', default => 60 );

has 'autowl_table' => ( is => 'rw', isa => 'Str', default => 'autowl' );

has 'query_autowl' => ( is => 'rw', isa => 'Bool', default => 1 );
has 'create_ticket' => ( is => 'rw', isa => 'Bool', default => 1 );

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

	my ( $ticket ) = $r->do_cached('greylist-ticket', sub { $self->get_ticket($r, @triplet) } );
	if( defined $ticket ) {
		if( $self->is_valid_ticket( $ticket ) ) {
			$self->log($r, join(',', @triplet).' has a valid greylisting ticket');
			if( $self->use_autowl && ! $r->is_already_done('greylist-autowl-add') ) {
				$self->add_autowl( $r, @triplet );
			}
			$self->remove_ticket( $r, @triplet );
			return $self->success( $r );
		}
		$self->log($r, join(',', @triplet).' has a invalid greylisting ticket. wait again');
		return( $self->defer( $ticket ) );
	}

	if( $self->create_ticket ) {
		$self->log($r, 'creating new greylisting ticket');
		$self->do_create_ticket($r, @triplet);
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

	my ( $row ) = $r->do_cached('greylist-autowl-row', sub {
		$self->get_autowl_row( $r, $sender_domain, $client_ip );
	} );

	if( ! defined $row ) {
		$self->log($r, 'client is not on autowl');
		return(0);
	}

	my $last_seen = Time::Piece->from_mysql_datetime($row->{'last_seen'});
	my $expires = Time::Piece->new + ( ONE_DAY * $self->autowl_expire_days );
	if( $last_seen > $expires ) {
		$self->log($r, 'removing expired autowl row');
		$self->remove_autowl_row( $r, $sender_domain, $client_ip );
		return(0);
	}

	if( $row->{'count'} < $self->autowl_threshold ) {
		$self->log($r, 'client has not yet reached autowl_threshold');
		return(0);
	}

	$self->log($r, 'client has valid autowl row. updating row');
	$self->incr_autowl_row( $r, $sender_domain, $client_ip );
	return(1);
}

sub add_autowl {
	my ( $self, $r, $sender, $client_ip ) = @_;
	my $sender_domain = $self->_extract_sender_domain( $sender );

	my ( $row ) = $r->do_cached('greylist-autowl-row', sub {
		$self->get_autowl_row( $r, $sender_domain, $client_ip );
	} );

	if( defined $row ) {
		$self->log($r, 'client already on autowl, just incrementing count');
		$self->incr_autowl_row( $r, $sender_domain, $client_ip );
		return;
	}

	$self->log($r, 'creating initial autowl entry');
	$self->create_autowl_row( $r, $sender_domain, $client_ip );
	return;
}

sub execute_sql {
	my ( $self, $r, $sql, @params ) = @_;
	my $dbh = $r->server->get_dbh;
	my $sth = $dbh->prepare( $sql );
	$sth->execute( @params );
	return $sth;
}

=head1 AUTOWL TABLE CREATE SQL SCRIPT

The following statement could be used to create the autowl table within a Maria/MySQL database:

  CREATE TABLE `autowl` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `sender_domain` VARCHAR(255) NOT NULL,
    `client_ip` VARCHAR(39) NOT NULL,
    `count` INT UNSIGNED NOT NULL,
    `last_seen` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `domain_ip` (`client_ip`, `sender_domain`),
    KEY(`client_ip`),
    KEY(`sender_domain`)
  ) ENGINE=MyISAM  DEFAULT CHARSET=latin1

=cut

sub get_autowl_row {
	my ( $self, $r, $sender_domain, $client_ip ) = @_;
	my $sql = sprintf("SELECT * FROM %s WHERE sender_domain=? AND client_ip=?",
       		$self->autowl_table );
	return $self->execute_sql($r, $sql, $sender_domain, $client_ip)->fetchrow_hashref;
}

sub create_autowl_row {
	my ( $self, $r, $sender_domain, $client_ip ) = @_;
	my $sql = sprintf("INSERT INTO %s VALUES(NULL, ?, ?, 1, NULL)",
       		$self->autowl_table );
	$self->execute_sql($r, $sql, $sender_domain, $client_ip);
	return;
}

sub incr_autowl_row {
	my ( $self, $r, $sender_domain, $client_ip ) = @_;
	my $sql = sprintf("UPDATE %s SET count=count+1 WHERE sender_domain=? AND client_ip=?",
       		$self->autowl_table );
	$self->execute_sql($r, $sql, $sender_domain, $client_ip);
	return;
}
sub remove_autowl_row {
	my ( $self, $r, $sender_domain, $client_ip ) = @_;
	my $sql = sprintf("DELETE FROM %s WHERE sender_domain=? AND client_ip=?",
       		$self->autowl_table );
	$self->execute_sql($r, $sql, $sender_domain, $client_ip);
	return;
}

sub get_ticket {
	my ( $self, $r, $sender, $ip, $rcpt ) = @_;
	my $key = join(",", $sender, $ip, $rcpt );
	if( my $ticket = $r->server->memcached->get( $key ) ) {
		return( $ticket );
	}
	return;
}

sub is_valid_ticket {
	my ( $self, $ticket ) = @_;
	if( time > $ticket ) {
		return 1;
	}
	return 0;
}

sub remove_ticket {
	my ( $self, $r, $sender, $ip, $rcpt ) = @_;
	my $key = join(",", $sender, $ip, $rcpt );
	$r->server->memcached->delete( $key );
	return;
}

sub do_create_ticket {
	my ( $self, $r, $sender, $ip, $rcpt ) = @_;
	my $ticket = time + $self->min_retry_wait;
	my $key = join(",", $sender, $ip, $rcpt );
	$r->server->memcached->set( $key, $ticket, $self->max_retry_wait );
	return;
}

__PACKAGE__->meta->make_immutable;

1;

