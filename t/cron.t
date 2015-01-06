#!perl 
package Mail::MtPolicyd::Plugin::CronTest;

use Moose;

extends 'Mail::MtPolicyd::Plugin';

sub cron {
    my $self = shift;
    my $server = shift;
    my $str = 'cron has been called with '.join(',', @_);

    $server->{'cron-test-output'} = $str;
    $server->log(3, $str);
    if( grep { $_ eq 'die' } @_ ) {
        die($str);
    }

    return;
}

package main;

use strict;
use warnings;

use Test::More tests => 6;
use Test::Exception;

use Mail::MtPolicyd;
use Mail::MtPolicyd::VirtualHost;

my $policyd = Mail::MtPolicyd->new;
isa_ok($policyd, 'Mail::MtPolicyd');

$policyd->{'virtual_hosts'}->{'main'} =
    Mail::MtPolicyd::VirtualHost->new_from_config(12345, {
        name => 'test-vhost',
        port => 12345,
        Plugin => {
            'cron-test' => {
                name => 'cron-test',
                module => 'CronTest',
                log_level => 0,
            },
        },
    } );
isa_ok($policyd->{'virtual_hosts'}->{'main'}, 'Mail::MtPolicyd::VirtualHost');

lives_ok {
    $policyd->cron('daily','hourly');
} 'cron() expected to live';
cmp_ok( $policyd->{'cron-test-output'}, 'eq', 'cron has been called with daily,hourly',
    'check cron output');

lives_ok {
    $policyd->cron('daily','hourly','die');
} 'exceptions must be catched if cron of plugin fails';

cmp_ok( $policyd->{'cron-test-output'}, 'eq', 'cron has been called with daily,hourly,die',
    'check cron output');
