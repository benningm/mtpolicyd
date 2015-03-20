package Mail::MtPolicyd::Plugin::Role::Scoring;

use Moose::Role;

# VERSION
# ABSTRACT: role for plugins using scoring

has 'score_field' => (
	is => 'ro', isa => 'Str', default => 'score',
);

sub _get_score {
	my ( $self, $r ) = @_;
	my $session = $r->session;
	if( defined $session->{$self->score_field} ) {
		return $session->{$self->score_field};
	}
	return 0;
}

sub _set_score {
	my ( $self, $r, $value ) = @_;
	my $session = $r->session;
	return $session->{$self->score_field} = $value;
}

sub _push_score_detail {
	my ( $self, $r, $string ) = @_;
	my $session = $r->session;
	my $field = $self->score_field . '_detail';
	if( ! defined $session->{$field} ) {
		$session->{$field} = $string;
		return;
	}
	$session->{$field} .= ', '.$string;
	return;
}

sub _get_score_detail {
	my ( $self, $r ) = @_;
	my $field = $self->score_field . '_detail';
	return( $r->session->{$field} );
}

sub add_score {
	my ( $self, $r, $key, $value ) = @_;

	my $score = $self->_get_score($r);
	$score += $value;
	$self->_set_score($r, $score);

	$self->_push_score_detail($r, $key.'='.$value);

	return $score;
}

1;

