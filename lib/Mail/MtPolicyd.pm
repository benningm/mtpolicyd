package Mail::MtPolicyd;

use strict;
use base qw(Net::Server::PreFork);

# VERSION
# ABSTRACT: a modular policy daemon for postfix

use Data::Dumper;
use Mail::MtPolicyd::Profiler;
use Mail::MtPolicyd::Request;
use Mail::MtPolicyd::VirtualHost;
use Mail::MtPolicyd::SqlConnection;
use DBI;
use Cache::Memcached;
use Time::HiRes qw( usleep tv_interval gettimeofday );
use Getopt::Long;
use Tie::IxHash;
use Config::General qw(ParseConfig);
use IO::Handle;
 
=head1 DESCRIPTION

Mail::MtPolicyd is the Net::Server class of the mtpolicyd daemon.

=head2 SYNOPSIS

  use Mail::MtPolicyd;
  Mail::MtPolicyd->run;

=cut

sub _preload_modules {
	# PRELOAD some modules
	my @modules = (
		'BerkeleyDB',
		'BerkeleyDB::Hash',
		'DBI',
		'DBD::mysql',
		'HTTP::Request::Common',
		'JSON',
		'LWP::UserAgent',
		'Mail::RBL',
		'Moose',
		'Moose::Role',
		'MooseX::Getopt',
		'MooseX::Role::Parameterized',
		'namespace::autoclean',
	);

	foreach my $module (@modules) {
		$module =~ s/::/\//g;
		$module .= '.pm';
		require $module;
	}
}

sub _apply_values_from_config {
	my ( $self, $target, $config ) = ( shift, shift, shift );

	while ( my $key = shift ) {
		if(! defined $config->{$key} ) {
			next;
		}
		$target->{$key} = $config->{$key};
	}

	return;
}

sub _apply_array_from_config {
	my ( $self, $target, $config ) = ( shift, shift, shift );

	while ( my $key = shift ) {
		if(! defined $config->{$key} ) {
			next;
		}
		$target->{$key} = [ split(/\s*,\s*/, $config->{$key}) ];
	}

	return;
}

sub print_usage {
	print "mtpolicyd [-h|--help] [-c|--config=<file>] [-f|--foreground] [-l|--loglevel=<level>] [-d|--dump_vhosts]\n";
	return;
}

sub configure {
	my $self = shift;
	my $server = $self->{'server'};
	my $cmdline;
	
	return if(@_);

    if( ! defined $server->{'config_file'} ) {
   	    $server->{'config_file'} = '/etc/mtpolicyd/mtpolicyd.conf';
    }
	$server->{'background'} = 1;
	$server->{'setsid'} = 1;
	$server->{'no_close_by_child'} = 1;

        # Parse command line params
        %{$cmdline} = ();
        GetOptions(
                        \%{$cmdline},
                        "help|h",
                        "dump_config|d",
                        "config|c:s",
                        "foreground|f",
                        "loglevel|l:i",
        );
        if ($cmdline->{'help'}) {
                $self->print_usage;
                exit 0;
        }
        if (defined($cmdline->{'config'}) && $cmdline->{'config'} ne "") {
                $server->{'config_file'} = $cmdline->{'config'};
        }
	if( ! -f $server->{'config_file'} ) {
		print(STDERR 'configuration file '.$server->{'config_file'}.' does not exist!\n');
		exit 1;
	}

	# DEFAULTS
    if( ! defined $server->{'log_level'} ) {
	    $server->{'log_level'} = 2;
    }
	if( ! defined $server->{'log_file'} && ! $cmdline->{'foreground'} ) {
		$server->{'log_file'} = 'Sys::Syslog';
	}
	$server->{'syslog_ident'} = 'mtpolicyd';
	$server->{'syslog_facility'} = 'mail';

	$server->{'proto'} = 'tcp';
	$server->{'host'} = '127.0.0.1';
    if( ! defined $server->{'port'} ) {
    	$server->{'port'} = [ '127.0.0.1:12345' ];
    }

	$server->{'min_servers'} = 4;
        $server->{'min_spare_servers'} = 4;
        $server->{'max_spare_servers'} = 12;
        $server->{'max_servers'} = 25;
	$server->{'max_requests'} = 1000;

	$self->{'request_timeout'} = 20;

	$self->{'keepalive_timeout'} = 60;
	$self->{'max_keepalive'} = 0;

	$self->{'db_dsn'} = undef;
	$self->{'db_user'} = '';
	$self->{'db_password'} = '';

	$self->{'memcached_servers'} = [ '127.0.0.1:11211' ];
	$self->{'memcached_namespace'} = 'mt-';
	$self->{'memcached_expire'} = 5 * 60;

	# will be incremented in linear steps 50, 100, 150...
	$self->{'session_lock_wait'} = 50; # usec
	$self->{'session_lock_max_retry'} = 50; # times
	$self->{'session_lock_timeout'} = 10; # sec

	$self->{'program_name'} = $0;

	# APPLY values from configuration file
	tie my %config_hash, "Tie::IxHash";
	%config_hash = ParseConfig(
	  -AllowMultiOptions => 'no',
          -ConfigFile => $server->{'config_file'},
          -Tie => "Tie::IxHash"
        );
	my $config = \%config_hash;

	$self->_apply_values_from_config($server, $config, 
		'user', 'group', 'pid_file',
		'log_level', 'log_file', 'syslog_ident', 'syslog_facility',
		'host',
		'min_servers', 'min_spare_servers', 'max_spare_servers',
		'max_servers', 'max_requests',
		'chroot',
	);
	$self->_apply_array_from_config($server, $config, 'port');

	$self->_apply_values_from_config($self, $config, 
		'request_timeout', 'keepalive_timeout', 'max_keepalive',
		'db_dsn', 'db_user', 'db_password',
		'memcached_namespace', 'memcached_expire',
		'session_lock_wait', 'session_lock_max_retry', 'session_lock_timeout',
		'program_name',
	);
	$self->_apply_array_from_config($self, $config, 'memcached_servers');

    # Initialize DB connection before load vhosts
	if( defined $self->{'db_dsn'} && $self->{'db_dsn'} !~ /^\s*$/ ) {
        Mail::MtPolicyd::SqlConnection->initialize(
            dsn => $self->{'db_dsn'},
            user => $self->{'db_user'},
            password => $self->{'db_password'},
        );
	}

	# LOAD VirtualHosts
	if( ! defined $config->{'VirtualHost'} ) {
		print(STDERR 'no virtual hosts configured!\n');
		exit 1;
	}
	my $vhosts = $config->{'VirtualHost'};

	$self->{'virtual_hosts'} = {};
	foreach my $vhost_port (keys %$vhosts) {
		my $vhost = $vhosts->{$vhost_port};
		$self->{'virtual_hosts'}->{$vhost_port} = 
			Mail::MtPolicyd::VirtualHost->new_from_config($vhost_port, $vhost)
	}
    if ($cmdline->{'dump_config'}) {
        print "----- Virtual Hosts -----\n";
        print Dumper( $self->{'virtual_hosts'} );
        exit 0;
    }

	# foreground mode (cmdline)
        if ($cmdline->{'foreground'}) {
		$server->{'background'} = undef;
		$server->{'setsid'} = undef;
        }
	if( $cmdline->{'loglevel'} ) {
		$server->{'log_level'} = $cmdline->{'loglevel'};
	} 


	# change processname in top/ps
	$self->_set_process_stat('master');

	return;
}

sub pre_loop_hook {
	my $self = shift;

	$self->_preload_modules;

	return;
}

sub child_init_hook {
	my $self = shift;

	$self->_set_process_stat('virgin child');

    # close parent database connection
    if( Mail::MtPolicyd::SqlConnection->is_initialized ) {
        Mail::MtPolicyd::SqlConnection->disconnect;
    }

	$self->{'memcached'} = Cache::Memcached->new( {
		'servers' => $self->{'memcached_servers'},
		'debug' => 0,
		'namespace' => $self->{'memcached_namespace'},
	} );

	return;
}

sub child_finish_hook {
	my $self = shift;
	$self->_set_process_stat('finish');

	if( Mail::MtPolicyd::SqlConnection->is_initialized ) {
		eval { Mail::MtPolicyd::SqlConnection->instance->disconnect };
	}

	return;
}

sub memcached {
	my $self = shift;
	if( ! defined $self->{'memcached'} ) {
		die('no memcached connection available!');
	}
	return( $self->{'memcached'} );
}

sub acquire_session_lock {
	my ( $self, $instance ) = @_;
	my $lock = 'lock_'.$instance;
	my $wait = $self->{'session_lock_wait'};
	my $max_retry = $self->{'session_lock_max_retry'};
	my $lock_ttl = $self->{'session_lock_timeout'};

	for( my $try = 1 ; $try < $max_retry ; $try++ ) {
		if( $self->{'memcached'}->add($lock, 1, $lock_ttl) ) {
			return; # lock created
		}
		usleep( $wait * $try );
	}

	die('could not acquire lock for session '.$instance);
	return;
}

sub release_session_lock {
	my ( $self, $instance ) = @_;
	my $lock = 'lock_'.$instance;

	$self->{'memcached'}->delete($lock);

	return;
}

sub retrieve_session {
	my ($self, $instance ) = @_;

	if( ! defined $instance ) {
		return;
	}

	$self->acquire_session_lock( $instance );

	if( my $session = $self->{'memcached'}->get($instance) ) {
		return($session);
	}
	
	return( { '_instance' => $instance } );
}

sub store_session {
	my ($self, $session ) = @_;
	my $instance = $session->{'_instance'};
	my $expire = defined $self->{'memcached_expire'} ? $self->{'memcached_expire'} : 300;

	if( ! defined $session || ! defined $instance ) {
		return;
	}
	
	$self->{'memcached'}->set($instance, $session, $expire);

	$self->release_session_lock($instance);

	return;
}

sub get_virtual_host {
	my $self = shift;
	my $server = $self->{server};
	my $client = $server->{client};
	my $vhost_port;
	my $is_socket = $client && $client->UNIVERSAL::can('NS_proto') &&
           $client->NS_proto eq 'UNIX';

	if( $is_socket ) {
		$vhost_port = Net::Server->VERSION >= 2 ? $client->NS_port
			: $client->NS_unix_path;
	} else {
		$vhost_port = $self->{'server'}->{'sockport'};
	}
	my $vhost = $self->{'virtual_hosts'}->{$vhost_port};
	if( ! defined $vhost ) {
		die('no virtual host defined for port '.$vhost_port);
	}
	return($vhost);
}

sub get_dbh {
	my $self = shift;
	if( ! Mail::MtPolicyd::SqlConnection->is_initialized ) {
		die('no database connection available (no configured?)');
	}
	return( Mail::MtPolicyd::SqlConnection->instance->dbh );
}

sub _is_loglevel {
	my ( $self, $level ) = @_;
	if( $self->{'server'}->{'log_level'} &&
			$self->{'server'}->{'log_level'} >= $level ) {
		return(1);
	}
	return(0);
}

sub _process_one_request {
	my ( $self, $conn, $vhost, $r ) = @_;
	my $port = $vhost->port;
	my $s;
	my $error;

	eval {
		my $start_t = [gettimeofday];
		local $SIG{'ALRM'} = sub { die "Request timeout!" };
		my $timeout = $self->{'request_timeout'};
		alarm($timeout);

		if( $self->_is_loglevel(4) ) { $self->log(4, 'request: '.$r->dump_attr); }
		my $instance = $r->attr('instance');

        Mail::MtPolicyd::Profiler->tick('retrieve session');
		$s = $self->retrieve_session($instance);
		if( $self->_is_loglevel(4) ) { $self->log(4, 'session: '.Dumper($s)); }
		$r->session($s);

        Mail::MtPolicyd::Profiler->tick('run vhost');
		my $result = $vhost->run($r);

		my $response = $result->as_policyd_response;
		$conn->print($response);
		$conn->flush;

		# convert to ms and round by 0.5/int
		my $elapsed = int(tv_interval( $start_t, [gettimeofday] ) * 100 + 0.5);
		$self->log(1, $vhost->name.': instance='.$instance.', type='.$r->type.', t='.$elapsed.'ms, result='.$result->as_log);
	};
	if ( $@ ) { $error = $@; }

	if( defined $s ) {
		$self->store_session($s);
	}

	if( defined $error ) { die( $error ); }

	return;
}

sub process_request {
	my ( $self, $conn ) = @_;
	my $max_keepalive = $self->{'max_keepalive'};

	my $vhost = $self->get_virtual_host;
	my $port = $vhost->port;
	$self->log(4, 'accepted connection on port '.$port );

	for( my $alive_count = 0
			; $max_keepalive == 0 || $alive_count < $max_keepalive 
			; $alive_count++ ) {
		my $r;
		$self->_set_process_stat($vhost->name.', waiting request');
        Mail::MtPolicyd::Profiler->reset;
		eval {
			local $SIG{'ALRM'} = sub { die "Keepalive connection timeout" };
			my $timeout = $self->{'keepalive_timeout'};
			alarm($timeout);
            Mail::MtPolicyd::Profiler->tick('parsing request');
			$r = Mail::MtPolicyd::Request->new_from_fh( $conn, 'server' => $self );
		};
		if ( $@ =~ /Keepalive connection timeout/ ) {
			$self->log(3, '['.$port.']: keepalive timeout: closing connection');
			last;
		} elsif($@ =~ /connection closed by peer/) {
			$self->log(3, '['.$port.']: connection closed by peer');
			last;
		} elsif($@) {
			$self->log(0, '['.$port.']: error while reading request: '.$@);
			last;
		
		}
        Mail::MtPolicyd::Profiler->tick('processing request');
		$self->_set_process_stat($vhost->name.', processing request');
		eval { 
			$self->_process_one_request( $conn, $vhost, $r );
		};
		if ( $@ =~ /Request timeout!/ ) {
			$self->log(1, '['.$port.']: request timed out');
			last;
		} elsif($@) {
			$self->log(0, 'error while processing request: '.$@);
			last;
		}
        Mail::MtPolicyd::Profiler->stop_current_timer;
	    if( $self->_is_loglevel(4) ) {
            $self->log(4, Mail::MtPolicyd::Profiler->to_string);
        }
	}

	$self->log(3, '['.$port.']: closing connection');
	$self->_set_process_stat('idle');

	return;
}

sub _set_process_stat {
	my ( $self, $stat ) = @_;
	$0 = $self->{'program_name'}.' ('.$stat.')'
};

1;

