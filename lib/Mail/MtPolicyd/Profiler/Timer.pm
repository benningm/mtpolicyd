package Mail::MtPolicyd::Profiler::Timer;

use Moose;
use namespace::autoclean;

# VERSION
# ABSTRACT: a profiler for the mtpolicyd

use Time::HiRes 'gettimeofday', 'tv_interval';

has 'name' => ( is => 'rw', isa => 'Str', required => 1 );

has 'start_time' => ( is => 'rw', isa => 'ArrayRef',
    default => sub { [gettimeofday()] },
);

has 'ticks' => ( is => 'ro', isa => 'ArrayRef', lazy => 1,
    default => sub { [] },
);

has 'parent' => ( is => 'ro', isa => 'Maybe[Mail::MtPolicyd::Profiler::Timer]' );

around BUILDARGS => sub {
        my $orig  = shift;
        my $class = shift;

        if ( @_ == 1 && !ref $_[0] ) {
                return $class->$orig( name => $_[0] );
        } else {
                return $class->$orig(@_);
        }
};

sub tick {
    my ( $self, $msg ) = @_;
    my $now = [gettimeofday()];
    my $delay = tv_interval($self->start_time, $now);
    push( @{$self->ticks}, [ $delay, $msg ] );
    return;
}

sub stop {
    my $self = shift;
    $self->tick('timer stopped');
}

sub new_child {
    my $self = shift;
    my $timer = __PACKAGE__->new(
        parent => $self,
        @_
    );
    $self->tick('started timer '.$timer->name);
    push( @{$self->ticks}, $timer );
    return( $timer );
}

sub to_string {
    my $self = shift;
    my $str = '';
    foreach my $tick ( @{$self->ticks} ) {
        if( ref $tick eq 'ARRAY' ) {
            $str .= sprintf("%0f %s\n", @$tick );
        } elsif( ref $tick eq 'Mail::MtPolicyd::Profiler::Timer' ) {
            my $substr = $tick->to_string;
            $substr =~ s/^/  /msg;
            $str .= $substr;
        }
    }
    return( $str );
}

__PACKAGE__->meta->make_immutable;

1;

