package Mail::MtPolicyd::Client::Request;

use Moose;

# VERSION
# ABSTRACT: a postfix policyd client request class

=head1 DESCRIPTION

Class for construction of policyd requests.

=head2 SYNOPSIS

  use Mail::MtPolicyd::Client::Request;

  $request = Mail::MtPolicyd::Client::Request->new(
    'client_address' => '127.0.0.1',
  );

=head2 METHODS

=over

=item as_string

Returns the request in as a string in the policyd request format.

=back

=head2 ATTRIBUTES

=over

=item type (default: smtpd_access_policy)

The type of the request.

=item instance (default: rand() )

The instance ID of the mail processed by the MTA.

=item attributes (default: {} )

A hashref with contains all key/value pairs of the request.

=back

=cut

has 'type' => ( is => 'ro', isa => 'Str', default => 'smtpd_access_policy' );

has 'instance' => ( is => 'ro', isa => 'Str', lazy => 1,
	default => sub {
		return rand;
	},
);

has 'attributes' => (
	is => 'ro', isa => 'HashRef[Str]',
	default => sub { {} },
);

sub as_string {
	my $self = shift;

	return join("\n",
		'request='.$self->type,
		'instance='.$self->instance,
		map { $_.'='.$self->attributes->{$_} } keys %{$self->attributes},
	)."\n\n";
}

sub new_from_fh {
        my ( $class, $fh ) = ( shift, shift );
        my $attr = {};
        my $complete = 0;
        while( my $line = $fh->getline ) {
                $line =~ s/\r?\n$//;
                if( $line eq '') { $complete = 1 ; last; }
                my ( $name, $value ) = split('=', $line);
                if( ! defined $value ) {
                        die('error parsing response');
                }
                $attr->{$name} = $value;
        }
        if( ! $complete ) {
                die('could not read response');
        }
        my $obj = $class->new(
                'attributes' => $attr,
                @_
        );
        return $obj;
}

sub new_proxy_request {
        my ( $class, $r ) = ( shift, shift );
	my %attr = %{$r->attributes};
	delete($attr{'type'});
	delete($attr{'instance'});

        my $obj = $class->new(
                'type' => $r->type,
                'instance' => $r->attr('instance'),
                'attributes' => \%attr,
        );
        return $obj;
}

1;

