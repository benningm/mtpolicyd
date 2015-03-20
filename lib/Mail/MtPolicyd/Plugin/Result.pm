package Mail::MtPolicyd::Plugin::Result;

use Moose;
use namespace::autoclean;

# VERSION
# ABSTRACT: result returned by a plugin

has 'action' => ( is => 'rw', isa => 'Maybe[Str]' );
has 'abort' => ( is => 'rw', isa => 'Bool', default => 0 );

sub new_dunno {
	my $class = shift;
		
	my $obj = $class->new(
		action => 'dunno',
		abort => 1,
	);
	return($obj);
}

sub new_header {
	my ( $class, $header, $value ) = @_;
		
	my $obj = $class->new(
		action => 'PREPEND '.$header.': '.$value,
		abort => 1,
	);
	return($obj);
}

sub new_header_once {
	my ( $class, $is_done, $header, $value ) = @_;

	if( $is_done ) {
		return $class->new_dunno;
	}
	return $class->new_header($header, $value);
}

__PACKAGE__->meta->make_immutable;

1;

