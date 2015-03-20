package Mail::MtPolicyd::Client;

use Moose;

# VERSION
# ABSTRACT: a policyd client class

=head1 DESCRIPTION

Client class to query a policyd server.

=head2 SYNOPSIS

  use Mail::MtPolicyd::Client;
  use Mail::MtPolicyd::Client::Request;

  my $client = Mail::MtPolicyd::Client->new(
    host => 'localhost:12345',
    keepalive => 1,
  );

  my $request = Mail::MtPolicyd::Client::Request->new(
    'client_address' => '192.168.0.1',
  );

  my $response = $client->request( $request );
  print $response->as_string;

=head2 METHODS

=over

=item request ( $request )

Will send a Mail::MtPolicyd::Client::Request to the remote host
and return a Mail::MtPolicyd::Client::Response.

=back

=head2 ATTRIBUTES

=over

=item socket_path (default: undef)

Path of a socket of the policyd server.

If defined this socket will be used instead of a tcp connection.

=item host (default: localhost:12345)

Remote address/port of the policyd server.

=item keepalive (default: 0)

Keep connection open for multiple requests.

=back

=cut

use IO::Socket::UNIX;
use IO::Socket::INET;

use Mail::MtPolicyd::Client::Response;

has 'socket_path' => ( is => 'rw', isa => 'Maybe[Str]' );
has 'host' => ( is => 'rw', isa => 'Str', default => 'localhost:12345' );
has 'keepalive' => ( is => 'rw', isa => 'Bool', default => 0 );

has '_fh' => ( is => 'rw', isa => 'Maybe[IO::Handle]' );

sub _connect {
	my $self = shift;
	my $fh;
	if( defined $self->socket_path ) {
		$fh = IO::Socket::UNIX->new(
			Peer => $self->socket_path,
			autoflush => 0,
		) or die('could not connect to socket: '.$!);
	} else {
		$fh = IO::Socket::INET->new(
			PeerAddr => $self->host,
			Proto => 'tcp',
			autoflush => 0,
		) or die('could not connect to host: '.$!);
	}
	$self->_fh( $fh );
}

sub _disconnect {
	my $self = shift;

	$self->_fh->close;
	$self->_fh( undef );
}

sub _is_connected {
	my $self = shift;
	if( defined $self->_fh ) {
		return(1);
	}
	return(0);
}

sub request {
	my ( $self, $request ) = @_;

	if( ! $self->_is_connected ) {
		$self->_connect;
	}

	$self->_fh->print( $request->as_string );
	$self->_fh->flush;

	my $response = Mail::MtPolicyd::Client::Response->new_from_fh( $self->_fh );

	# close connection we're not doing keepalive
	# or if the server already closed connection (server side keepalive off)
	if( ! $self->keepalive || $self->_fh->eof ) {
		$self->_disconnect;
	}

	return $response;
}

1;

