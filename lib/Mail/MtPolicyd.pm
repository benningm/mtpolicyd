package Mail::MtPolicyd;

use strict;
use warnings;
use base qw(Net::Server::PreFork);

# VERSION
# ABSTRACT: a modular policy daemon for postfix

use Data::Dumper;
use Mail::MtPolicyd::Profiler;
use Mail::MtPolicyd::Request;
use Mail::MtPolicyd::VirtualHost;
use Mail::MtPolicyd::ConnectionPool;
use Mail::MtPolicyd::SessionCache;
use DBI;
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
		'DBI',
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
	print "mtpolicyd [-h|--help] [-c|--config=<file>] [-f|--foreground] [-l|--loglevel=<level>] [-d|--dump_vhosts] [-t|--cron=<task1,hourly,daily,...>]\n";
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
            "cron|t:s",
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

	$self->{'vhost_by_policy_context'} = 0;

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
    'vhost_by_policy_context',
		'program_name',
	);

  # initialize connection pool
  Mail::MtPolicyd::ConnectionPool->initialize;
  if( defined $config->{'Connection'} ) {
    Mail::MtPolicyd::ConnectionPool->load_config( $config->{'Connection'} );
  }
  $self->{'session_cache_config'} = $config->{'SessionCache'};

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

    # if running in cron mode execute cronjobs and exit
    if( $cmdline->{'cron'} && $cmdline->{'cron'} !~ /^\s*$/ ) {
        my @tasks = split(/\s*,\s*/, $cmdline->{'cron'});
        $self->cron( @tasks );
        exit 0;
    }

	# change processname in top/ps
	$self->_set_process_stat('master');

	return;
}

sub cron {
    my $self = shift;
    foreach my $vhost ( keys %{$self->{'virtual_hosts'}} ) {
        $self->{'virtual_hosts'}->{$vhost}->cron( $self, @_ );
    }
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

  # recreate connection in child process
  Mail::MtPolicyd::ConnectionPool->reconnect;

  # initialize session cache
  $self->{'session_cache'} = Mail::MtPolicyd::SessionCache->new(
    server => $self,
  );
  if( defined $self->{'session_cache_config'} &&
      ref($self->{'session_cache_config'}) eq 'HASH') {
    $self->{'session_cache'}->load_config( $self->{'session_cache_config'} );
  }

	return;
}

sub child_finish_hook {
	my $self = shift;
	$self->_set_process_stat('finish');

  Mail::MtPolicyd::ConnectionPool->shutdown;
  if( defined $self->{'session_cache'} ) {
    $self->{'session_cache'}->shutdown;
  }

	return;
}

sub get_conn_port {
	my $self = shift;
	my $server = $self->{server};
	my $client = $server->{client};
	my $port;
	my $is_socket = $client && $client->UNIVERSAL::can('NS_proto') &&
           $client->NS_proto eq 'UNIX';

	if( $is_socket ) {
		$port = Net::Server->VERSION >= 2 ? $client->NS_port
			: $client->NS_unix_path;
	} else {
		$port = $self->{'server'}->{'sockport'};
	}
	return($port);
}

sub get_virtual_host {
	my ( $self, $conn_port, $r ) = @_;
  my $vhost;
  my $policy_context = $r->attr('policy_context');

  if( $self->{'vhost_by_policy_context'}
      && defined $policy_context
      && $policy_context ne '' ) {
    foreach my $vhost_port ( keys %{$self->{'virtual_hosts'}} ) {
      $vhost = $self->{'virtual_hosts'}->{$vhost_port};
      if( $policy_context eq $vhost->name ) {
        return( $vhost );
      }
    }
  }

	$vhost = $self->{'virtual_hosts'}->{$conn_port};
	if( ! defined $vhost ) {
		die('no virtual host defined for port '.$conn_port);
	}
	return($vhost);
}

sub _is_loglevel {
	my ( $self, $level ) = @_;
	if( $self->{'server'}->{'log_level'} &&
			$self->{'server'}->{'log_level'} >= $level ) {
		return(1);
	}
	return(0);
}

our %_LOG_ESCAPE_MAP = (
  "\0" => '\0',
  "\r" => '\r',
  "\n" => '\n',
  "\\" => '\\\\',
);

our $_LOG_ESCAPE_MAP_RE = '['.join('',
  map {
    sprintf('\\x%02x', ord($_))
  } keys %_LOG_ESCAPE_MAP
).']';

sub log {
  my ( $self, $level, $msg, @params ) = @_;
  $msg =~ s/($_LOG_ESCAPE_MAP_RE)/
    $_LOG_ESCAPE_MAP{$1} /gse;
  $msg =~ s/([\x01-\x08\x0b-\x0c\x0e-\x1f\x7f])/
    sprintf('\\x%02X', ord($1)) /gse;
  return $self->SUPER::log( $level, $msg, @params );
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
		$s = $self->{'session_cache'}->retrieve_session($instance);
		if( $self->_is_loglevel(4) ) { $self->log(4, 'session: '.Dumper($s)); }
		$r->session($s);

    Mail::MtPolicyd::Profiler->tick('run vhost');
		my $result = $vhost->run($r);

		my $response = $result->as_policyd_response;
		$conn->print($response);
		$conn->flush;

		# convert to ms and round by 0.5/int
		my $elapsed = int(tv_interval( $start_t, [gettimeofday] ) * 100 + 0.5);
    my $matched = defined $result->last_match ? $result->last_match : '';
		$self->log(1, $vhost->name.': instance='.$instance.', type='.$r->type.', t='.$elapsed.'ms, plugin='.$matched.', result='.$result->as_log);
	};
	if ( $@ ) { $error = $@; }

	if( defined $s ) {
		$self->{'session_cache'}->store_session($s);
	}

	if( defined $error ) { die( $error ); }

	return;
}

sub process_request {
	my ( $self, $conn ) = @_;
	my $max_keepalive = $self->{'max_keepalive'};

	my $port = $self->get_conn_port;
	$self->log(4, 'accepted connection on port '.$port );

	for( my $alive_count = 0
			; $max_keepalive == 0 || $alive_count < $max_keepalive 
			; $alive_count++ ) {
		my $r;
		$self->_set_process_stat('waiting request');
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
	  my $vhost = $self->get_virtual_host($port, $r);
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

sub memcached {
  die('the global memcached connection does no longer exist in mtpolicyd >= 2.00');
}

sub get_dbh {
  die('the global dbh handle is no longer available in mtpolicyd >= 2.00');
}

1;

