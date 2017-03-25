package Mail::MtPolicyd::Plugin::RegexList;

use Moose;
use namespace::autoclean;

# VERSION
# ABSTRACT: mtpolicyd plugin for regex matching

extends 'Mail::MtPolicyd::Plugin';
with 'Mail::MtPolicyd::Plugin::Role::Scoring';
with 'Mail::MtPolicyd::Plugin::Role::UserConfig' => {
	'uc_attributes' => [ 'enabled', 'score', 'action' ],
};
with 'Mail::MtPolicyd::Plugin::Role::PluginChain';

use Mail::MtPolicyd::Plugin::Result;
use File::Slurp;

=head1 SYNOPSIS

  <Plugin regex-whitelist>
    module = "RegexList"
    key = "request:client_name"
    regex = "^mail-[a-z][a-z]0-f[0-9]*\.google\.com$"
    regex = "\.bofh-noc\.de$"
    # file = "/etc/mtpolicyd/regex-whitelist.txt"
    action = "accept"
  </Plugin>

=head1 DESCRIPTION

This plugin matches a value against a list of regular expressions
and executes an action if it matched.

=head2 PARAMETERS

The module takes the following parameters:

=over

=item (uc_)enabled (default: "on")

Could be set to 'off' to deactivate check. Could be used to activate/deactivate check per user.

=item key (default: "request:client_address")

Field to query.

=item invert (default: 0)

If set to 1 the logic will be inverted.

=item regex (default: empty)

One or more regular expressions

=item file (default: empty)

A file to load regular expressions from.

One regex per line. Empty lines and lines starting with # will be ignored.

=back

By default the plugin will do nothing. One of the following actions should be specified:

=over

=item action (default: empty)

If given this action will be returned to the MTA if the SQL query matched.

=item score (default: empty)

If given this score will be applied to the session.

=item Plugin (default: empty)

Execute this plugins when the condition matched.

=back

=cut

has 'enabled' => ( is => 'rw', isa => 'Str', default => 'on' );

has 'key' => ( is => 'rw', isa => 'Str', required => 1 );

has 'invert' => ( is => 'rw', isa => 'Bool', default => 0 );
has 'score' => ( is => 'rw', isa => 'Maybe[Num]' );
has 'action' => ( is => 'rw', isa => 'Maybe[Str]' );

around BUILDARGS => sub {
  my $orig  = shift;
  my $class = shift;
  my %params = @_;

  if ( defined $params{'regex'} ) {
    if( ! ref($params{'regex'}) ) {
      $params{'regex'} = [ $params{'regex'} ];
    }
  }
  return $class->$orig(%params);
};

has 'regex' => ( is => 'rw', isa => 'ArrayRef[Str]', default => sub { [] });

has 'file' => ( is => 'rw', isa => 'Maybe[Str]' );

has '_file_regex_list' => (
  is => 'ro', isa => 'ArrayRef', lazy => 1,
  default => sub {
    my $self = shift;
    if( ! defined $self->file ) {
      return [];
    }
    my @regexes;
    foreach my $line ( read_file($self->file) ) {
      chomp $line;
      if( $line =~ /^\s*$/ ) {
        next;
      }
      if( $line =~ /^\s*#/ ) {
        next;
      }
      push( @regexes, $line );
    }
    return \@regexes;
  },
);

has '_regex_list' => (
  is => 'ro', isa => 'ArrayRef', lazy => 1,
  default => sub {
    my $self = shift;
    return [ @{$self->regex}, @{$self->_file_regex_list} ]
  },
);

sub _match_regex_list {
  my ( $self, $r, $value ) = @_;

  foreach my $regex_str ( @{$self->_regex_list} ) {
    my $regex = eval { qr/$regex_str/ };
    if( $@ ) {
      $self->log($r, "invalid regex $regex: $@");
      next;
    }
    if( $value =~ /$regex/ ) {
      return $regex_str;
    }
  }

  return;
}

sub run {
	my ( $self, $r ) = @_;
	my $value = $r->get( $self->key );
	my $session = $r->session;

	if( $self->get_uc( $session, 'enabled') eq 'off' ) {
		return;
	}

	if( ! defined $value) {
		$self->log($r, 'no attribute \''.$self->key.'\' in request');
		return;
	}

	my ( $regex ) = $r->do_cached( $self->name.'-result',
			sub { $self->_match_regex_list($r, $value) } );

	if( ( ! $self->invert && defined $regex )
      || ( $self->invert && ! defined $regex ) ) {
		$self->log($r, $self->key.'='.$value.' matched '.$self->name);
    my $score = $self->get_uc( $session, 'score');
		if( defined $score
				&& ! $r->is_already_done($self->name.'-score') ) {
			$self->add_score($r, $self->name => $score);
		}
    # apply action
    my $action = $self->get_uc( $session, 'action');
		if( defined $action ) {
			return Mail::MtPolicyd::Plugin::Result->new(
				action => $action,
				abort => 1,
			);
		}
    # or cascade
		if( defined $self->chain ) {
			my $chain_result = $self->chain->run( $r );
			return( @{$chain_result->plugin_results} );
		}
	}

	return;
}

__PACKAGE__->meta->make_immutable;

1;

