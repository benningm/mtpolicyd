package Mail::MtPolicyd::Profiler;

use strict;
use MooseX::Singleton;
use namespace::autoclean;

use Mail::MtPolicyd::Profiler::Timer;
use JSON;

# VERSION
# ABSTRACT: a application level profiler for mtpolicyd

has 'root' => ( is => 'rw', isa => 'Mail::MtPolicyd::Profiler::Timer',
    lazy => 1,
    default => sub {
        Mail::MtPolicyd::Profiler::Timer->new( name => 'main timer' );
    },
);

has 'current' => (
    is => 'rw', isa => 'Mail::MtPolicyd::Profiler::Timer',
    handles => {
        'tick' => 'tick',
    },
    lazy => 1,
    default => sub {
        my $self = shift;
        return $self->root;
    },
);

sub reset {
    my ( $self, $name ) = @_;
    my $timer = Mail::MtPolicyd::Profiler::Timer->new( name => 'main timer' );

    $self->root( $timer );
    $self->current( $timer );

    return;
}

sub new_timer {
    my ( $self, $name ) = @_;
    my $timer = $self->current->new_child( name => $name );
    $self->current( $timer );
    return;
}

sub stop_current_timer {
    my ( $self, $name ) = @_;
    $self->current->stop;
    if( defined $self->current->parent ) {
        $self->current($self->current->parent);
    }
    return;
}

sub to_string {
    my $self = shift;
    return $self->root->to_string;
}

__PACKAGE__->meta->make_immutable;

1;

