#!perl

use strict;
use warnings;

package Test::Net::Server;

use Test::More;
use File::Temp;
use IO::File;
use POSIX;
use File::ReadBackwards;
use Template;

use Moose;

has 'class' => ( is => 'ro', isa => 'Str', required => 1 );
has 'config_file' => ( is => 'ro', isa => 'Str', required => 1 );
has 'log_level' => ( is => 'ro', isa => 'Int', default => 4 );

has 'tmpdir' => ( is => 'ro', isa => 'File::Temp::Dir', lazy => 1,
    default => sub { File::Temp->newdir },
);

has 'tmp_config_file' => ( is => 'ro', isa => 'Str', lazy => 1,
    default => sub {
        my $self = shift;
        return $self->tmpdir.'/mtpolicyd.conf';
    },
);

has 'pid_file' => ( is => 'ro', isa => 'Str', lazy => 1,
    default => sub {
        my $self = shift;
        return( $self->tmpdir.'/pid');
    }
);

has 'log_file' => ( is => 'ro', isa => 'Str', lazy => 1,
    default => sub {
        my $self = shift;
        return( $self->tmpdir.'/log');
    }
);

has 'port' => ( is => 'ro', isa => 'Int', lazy => 1,
    default => sub {
        # may work for now
        return( 50000 + int(rand(10000)) );
    },
);

sub pid {
    my $self = shift;

    if( ! -e  $self->pid_file ) {
        return;
    }
    my $file = IO::File->new( $self->pid_file, 'r');
    if( ! defined $file ) {
        die( 'could not open pid_file '.$self->pid_file.': '.$!);
    }
    my $pid = $file->getline;
    chomp( $pid );
    $file->close;

    if( ! defined $pid ) {
        return;
    }
    return( $pid );
}

has 'timeout' => ( is => 'ro', isa => 'Int', default => 10 );

sub wait_for_logfile {
    my $self = shift;
    my $retry = 0;
    while( ! -e $self->log_file ) {
        if( $retry >= $self->timeout ) {
            die('timeout while waiting for log_file to appear!');
        }
        sleep(1);
        $retry++;
    }
    return;
}

has 'lastlog' => ( is => 'ro', isa => 'ArrayRef', lazy => 1,
    default => sub {[]},
);

sub wait_for_logmessage {
    my $self = shift;
    my $regex = shift;
    my $log = IO::File->new( $self->log_file, 'r');
    if( ! defined $log ) {
        die('could not open logfile '.$self->log_file.': '.$!);
    }
    my $retry = 0;
    for(;;) {
        while( my $line = $log->getline ) {
            chomp( $line );
            push( @{$self->lastlog}, $line );
            if( $line =~ /$regex/ ) {
                return $line;
            }
        }
        if( $retry >= $self->timeout ) {
            die('timeout waiting for log message like '.$regex);
        }
        sleep(1);
        $retry++;
    }
    return;
}

sub tail_log {
    my $self = shift;
    my @lines;
    my $num_lines = 5;
    if( @_ ) {
        $num_lines = shift;
    }
    my $file = File::ReadBackwards->new( $self->log_file ) or
        die "can't read 'log_file' $!" ;
    while( @lines < $num_lines ) {
        my $line = $file->getline;
        if( ! defined $line ) {
            last;
        }
        chomp( $line );
        push( @lines, $line );
    }
    return( join("\n", reverse @lines) );
}

sub generate_config {
    my $self = shift;
    my $template = Template->new();

    $template->process( $self->config_file, {
            port => $self->port,
        }, $self->tmp_config_file )
        || die "error processing config: ".$template->error(), "\n";

    return;
}

sub run {
    my $self = shift;
    my $class = $self->class;

    $self->generate_config;
    
    eval "require $class";

    my $server = "$class"->new(
        config_file => $self->tmp_config_file,
        log_file => $self->log_file,
        pid_file => $self->pid_file,
        port => $self->port,
        user => getuid(),
        group => getgid(),
        log_level => $self->log_level,
    );
    if( fork == 0 ) {
        $server->run;
    }
    pass('started server '.$self->class.' on port '.$self->port);

    eval { $self->wait_for_logfile; };
    if( $@ ) {
        fail( $@ );
        return;
    }
    eval { $self->wait_for_logmessage('^Parent ready'); };
    if( $@ ) {
        fail( $@."\nLogfile:\n".join("\n", @{$self->lastlog} ) );
        return;
    }

    pass('server is ready');
    return;
}

sub DESTROY {
    my $self = shift;
    my $pid = $self->pid;
    if( defined $pid ) {
        kill( 'QUIT', $pid );
        pass('sent SIGQUIT to server with pid '.$pid);
    }
}

1;
