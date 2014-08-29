package Mail::MtPolicyd::Plugin::Fail2Ban;

use Moose;
use namespace::autoclean;

# VERSION
# ABSTRACT: mtpolicyd plugin to block an address with fail2ban

=head1 DESCRIPTION

This plugin can be used to block an ip with iptable thru the fail2ban daemon.

For more information abount fail2ban read:

http://www.fail2ban.org/

This plugin will directly talk to the daemon thru the unix domain socket and
execute an banip command:

  set <JAIL> banip <IP>

=head1 PARAMETERS

=over

=item socket (default: /var/run/fail2ban/fail2ban.sock)

Path to the fail2ban unix socket.

Make sure mtpolicyd is allowed to write to this socket!

=item jail (default: postfix)

The jail in which the ip should be banned.

=back

=head1 EXAMPLE

Execute a ban on all client-ips which send a mail with a score of >=15:

  <Plugin ScoreBan>
    module = "ScoreAction"
    threshold = 15
    <Plugin ban-ip>
      module = "Fail2Ban"
      socket = "/var/run/fail2ban/fail2ban.sock"
      jail = "postfix"
    </Plugin>
  </Plugin>

=head1 FAIL2BAN CONFIGURATION

To allow mtpolicyd to access fail2ban you must make sure fail2ban can write
to the fail2ban unix socket.

  chgrp mtpolicyd /var/run/fail2ban/fail2ban.sock
  chmod g+rwx /var/run/fail2ban/fail2ban.sock

You may want to add this to the fail2ban startup script.

You may want to use the predefined postfix jail.
To activate it create /etc/fail2ban/jail.local and enable the postfix fail by
setting enabled=true.

  [postfix]
  enabled = true

=cut

extends 'Mail::MtPolicyd::Plugin';
with 'Mail::MtPolicyd::Plugin::Role::UserConfig' => {
	'uc_attributes' => [ 'enabled' ],
};

use IO::Socket::UNIX;

has 'enabled' => ( is => 'rw', isa => 'Str', default => 'on' );

has 'socket' => ( is => 'ro', isa => 'Str', default => '/var/run/fail2ban/fail2ban.sock' );
has 'jail' => ( is => 'ro', isa => 'Str', default => 'postfix' );

has '_socket' => ( is => 'ro', isa => 'IO::Socket::UNIX', lazy => 1,
	default => sub {
		my $self = shift;
		my $socket = IO::Socket::UNIX->new(
			Peer => $self->socket,
		) or die "cant connect fail2ban socket: $!";

		return( $socket );
	},
);

sub run {
	my ( $self, $r ) = @_;
	my $ip = $r->attr('client_address');
	my $session = $r->session;

	my $enabled = $self->get_uc( $session, 'enabled' );
	if( $enabled eq 'off' ) {
		return;
	}

	if( ! $r->is_already_done($self->name.'-fail2ban') ) {
		$self->log( $r, 'adding ip '.$ip.' to fail2ban jail '.$self->jail );
		$self->add_fail2ban( $r, $ip );
	}

	return;
}

# The protocol used is based in tickle, an python specific serialization protocol
# this command is captured from the output of:
#  strace -s 1024 -f fail2ban-client set postfix banip 123.123.123.123
# ...
# sendto(3, "\200\2]q\0(U\3setq\1U\7postfixq\2U\5banipq\3U\017123.123.123.123q\4e.<F2B_END_COMMAND>", 71, 0, NU
has '_command_pattern' => (
	is => 'ro', isa => 'Str',
	default => "\200\2]q\0(U\3setq\1U%c%sq\2U\5banipq\3U%c%sq\4e.<F2B_END_COMMAND>",
);

sub add_fail2ban {
	my ( $self, $r, $ip ) = @_;

	$self->_socket->print(
		sprintf($self->_command_pattern,
			length($self->jail),
			$self->jail,
			length($ip),
			$ip
		)
	);

	return;
}

__PACKAGE__->meta->make_immutable;

1;

