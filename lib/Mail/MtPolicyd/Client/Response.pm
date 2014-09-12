package Mail::MtPolicyd::Client::Response;

use Moose;

# VERSION
# ABSTRACT: a postfix policyd client response class

=head1 DESCRIPTION

Class to handle a policyd response.

=head2 SYNOPSIS

  use Mail::MtPolicyd::Client::Response;
  my $response = Mail::MtPolicyd::Client::Response->new_from_fh( $conn );

  --

  my $response = Mail::MtPolicyd::Client::Response->new(
    action => 'reject',
    attributes => {
      action => 'reject',
    },
  );

  print $response->as_string;

=head2 METHODS

=over

=item new_from_fh( $filehandle )

Constructor which reads a response from the supplied filehandle.

=item as_string

Returns a stringified version of the response.

=back

=head2 ATTRIBUTES

=over

=item action (required)

The action specified in the reponse.

=item attributes

Holds a hash with all key/values of the response.

=back

=cut

has 'action' => ( is => 'ro', isa => 'Str', required => 1 );

has 'attributes' => (
	is => 'ro', isa => 'HashRef[Str]',
	default => sub { {} },
);

sub as_string {
	my $self = shift;

	return join("\n",
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
                my ( $name, $value ) = split('=', $line, 2);
                if( ! defined $value ) {
                        die('error parsing response');
                }
                $attr->{$name} = $value;
        }
        if( ! $complete ) {
                die('could not read response');
        }
	if( ! defined $attr->{'action'} ) {
		die('no action found in response');
	}
        my $obj = $class->new(
		'action' => $attr->{'action'},
                'attributes' => $attr,
                @_
        );
        return $obj;
}

1;

