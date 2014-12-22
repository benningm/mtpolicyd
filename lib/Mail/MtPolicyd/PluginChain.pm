package Mail::MtPolicyd::PluginChain;

use Moose;
use namespace::autoclean;

# VERSION
# ABSTRACT: class for a VirtualHost instance

use Mail::MtPolicyd::Profiler;
use Mail::MtPolicyd::Result;

has 'plugins' => (
	is => 'ro',
	isa => 'ArrayRef[Mail::MtPolicyd::Plugin]',
	default => sub { [] },
	traits => [ 'Array' ],
	handles => {
		'add_plugin' => 'push',
	}
);

has 'plugin_prefix' => (
	is => 'ro', isa => 'Str', default => 'Mail::MtPolicyd::Plugin::',
);

has 'vhost_name' => ( is => 'rw', isa => 'Maybe[Str]' );

sub run {
	my ( $self, $r ) = @_;
	my $result = Mail::MtPolicyd::Result->new;

	foreach my $plugin ( @{$self->plugins} ) {
		my $abort = 0;
        Mail::MtPolicyd::Profiler->new_timer('plugin '.$plugin->name);
        my @plugin_results;
        eval { @plugin_results = $plugin->run($r); };
        my $e = $@;
        if( $e ) {
            my $msg = 'plugin '.$plugin->name.' failed: '.$e;
            if( ! defined $plugin->on_error || $plugin->on_error ne 'continue' ) {
                die($msg);
            }
            $r->log(0, $msg);
        }
        Mail::MtPolicyd::Profiler->stop_current_timer;
		foreach my $plugin_result ( @plugin_results ) {
			$result->add_plugin_result($plugin_result);
			if( $plugin_result->abort ) {
				$abort = 1;
			}
		}
		if( $abort ) { last; }
	}

	return $result;
}

sub load_plugin {
	my ( $self, $plugin_name, $params ) = @_;
	if( ! defined $params->{'module'} ) {
		die('no module defined for plugin '.$plugin_name.'!');
	}
	my $module = $params->{'module'};
	my $plugin_class = $self->plugin_prefix.$module;
	my $plugin;

	my $code = "require ".$plugin_class.";";
	eval $code; ## no critic (ProhibitStringyEval)
	if($@) {
        die('could not load module '.$module.' for plugin '.$plugin_name.': '.$@);
    }

	eval {
        $plugin = $plugin_class->new(
            name => $plugin_name,
            vhost_name => $self->vhost_name,
            %$params,
        );
        $plugin->init();
    };
    if($@) {
        die('could not initialize plugin '.$plugin_name.': '.$@);
    }
	$self->add_plugin($plugin);
	return;
}

sub new_from_config {
	my ( $class, $vhost_name, $config ) = @_;

	my $self = $class->new( vhost_name => $vhost_name );

	if( ! defined $config ) {
		return( $self );
	}

	if( ref($config) ne 'HASH' ) {
		die('config must be an hashref!');
	}

	foreach my $plugin_name ( keys %{$config} ) {
		$self->load_plugin($plugin_name,
			$config->{$plugin_name} );
	}

	return $self;
}

__PACKAGE__->meta->make_immutable;

1;

