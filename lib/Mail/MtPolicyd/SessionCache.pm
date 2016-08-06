package Mail::MtPolicyd::SessionCache;

use Moose;

# VERSION
# ABSTRACT: class for handling session cache

use Mail::MtPolicyd::SessionCache::None;

has 'server' => (
	is => 'ro', isa => 'Net::Server', required => 1,
	handles => {
		'log' => 'log',
	}
);

has 'cache' => (
  is => 'rw', isa => 'Mail::MtPolicyd::SessionCache::Base',
  lazy => 1,
  default => sub { Mail::MtPolicyd::SessionCache::None->new },
  handles => [
    'retrieve_session', 'store_session', 'shutdown',
  ],
);

sub load_config {
  my ( $self, $config ) = @_;
	if( ! defined $config->{'module'} ) {
		die('no module defined for SessionCache!');
	}
	my $module = $config->{'module'};
	my $class = 'Mail::MtPolicyd::SessionCache::'.$module;
	my $cache;

  $self->log(1, 'loading SessionCache '.$module);
	my $code = "require ".$class.";";
	eval $code; ## no critic (ProhibitStringyEval)
	if($@) {
    die('could not load SessionCache '.$module.': '.$@);
  }

  $self->log(1, 'initializing SessionCache '.$module);
	eval {
    $cache = $class->new(
      %$config,
    );
    $cache->init();
  };
  if($@) {
    die('could not initialize SessionCache: '.$@);
  }
	$self->cache( $cache );
  return;
}

1;

