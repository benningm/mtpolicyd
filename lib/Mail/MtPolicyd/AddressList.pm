package Mail::MtPolicyd::AddressList;

use Moose;
use namespace::autoclean;

# VERSION
# ABSTRACT: a class for IP address lists

use NetAddr::IP;

has '_localhost_addr' => ( is => 'ro', isa => 'ArrayRef[NetAddr::IP]',
    lazy => 1,
    default => sub {
        return [ map { NetAddr::IP->new( $_ ) }
            ( '127.0.0.0/8', '::ffff:127.0.0.0/104', '::1' ) ];
    },
);

=head1 Attributes

=head2 list

Contains an ArrayRef of NetAddr::IP which holds the all entries of this object.

=cut

has 'list' => (
    is => 'ro', isa => 'ArrayRef[NetAddr::IP]', lazy => 1,
    default => sub { [] },
    traits => [ 'Array' ],
    handles => {
        'add' => 'push',
        'is_empty' => 'is_empty',
        'count' => 'count',
    },
);

=head1 Methods

=head2 add

Add a list of NetAddr::IP objects to the list.

=head2 is_empty

Returns a true value when empty.

=head2 count

Returns the number of entries.

=head2 add_localhost

Add localhost addresses to list.

=cut

sub add_localhost {
    my $self = shift;
    $self->add( @{$self->_localhost_addr} );
    return;
}

=head2 add_string

Takes a list of IP address strings.

The strings itself can contain a list of comma/space separated addresses.

Then a list of NetAddr::IP objects is created and pushed to the list.

=cut

sub add_string {
    my ( $self, @strings ) = @_;

    my @addr_strings = map {
        split( /\s*[, ]\s*/, $_ )
    } @strings;
    
    my @addr = map {
        NetAddr::IP->new( $_ );
    } @addr_strings;

    $self->add( @addr );

    return;
}

=head2 match

Returns true if the give NetAddr::IP object matches an entry of the list.

=cut

sub match {
    my ( $self, $addr ) = @_;
    if( grep { $_->contains( $addr ) } @{$self->list} ) {
        return 1;
    }
    return 0;
}

=head2 match_string

Same as match(), but takes an string instead of NetAddr::IP object.

=cut

sub match_string {
    my ( $self, $string ) = @_;
    my $addr = NetAddr::IP->new( $string );
    return( $self->match( $addr ) );
}

=head2 as_string

Returns a comma separated string with all addresses.

=cut

sub as_string {
    my $self = shift;
    return join(',', map { $_->cidr } @{$self->list});
}

__PACKAGE__->meta->make_immutable;

1;

