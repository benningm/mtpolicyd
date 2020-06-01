# NAME

mtpolicyd - the mtpolicyd executable

# VERSION

version 2.04

# DESCRIPTION

mtpolicyd is a policy daemon for postfix access delegation.

It can be configured to accept connections on several ports from a postfix MTA.
For each port a VirtualHost can be configured and for each VirtualHost several
Plugins can be configured.

# NAME

mtpolicyd - a modular policy daemon for postfix

# EXAMPLE

In postfix main.cf:

    smtpd_recipient_restrictions = check_policy_service inet:127.0.0.1:12345

In mtpolicyd.conf:

    # listen on port 12345 (multiple ports can be separated by ',')
    port="127.0.0.1:12345"

    # defined host for this port
    <VirtualHost 12345>
      name=example_vhost
      <Plugin spamhaus_bl>
        module="RBL"
        domain="sbl.spamhaus.org"
        mode=reject
      </Plugin>
    </VirtualHost>

This check will execute a simple RBL lookup against dbl.spamhaus.org.

# COMMANDLINE OPTIONS

    mtpolicyd
      [-h|--help]
      [-c|--config=<file>]
      [-f|--foreground]
      [-l|--loglevel=<level>]
      [-d|--dump_vhosts]

- -h --help

    Show available command line options.

- -c --config=&lt;file> (default: /etc/mtpolicyd/mtpolicyd.conf)

    Specify the path to the configuration file.

- -f --foreground

    Do not fork to background and log to stdout.

- -l --loglevel=&lt;level>

    Overwrite the log level specified in the configuration with the specified level.

- -d --dump\_vhosts

    Parse VirtualHosts configuration, print it to stdout and exit.

# CONFIGURATION FILE

The configuration file is implementend with [Config::General](https://metacpan.org/pod/Config%3A%3AGeneral) which allows apache style
configuration files.

mtpolicyd accepts global configuration parameters in the style:

    key=value

Comments begin with '#'.

VirtualHosts must be configured with VirtualHost sections:

    <VirtualHost <portnumber>>
      name=<name of the vhost>
    </VirtualHost>

Each VirtualHost should contain at least on Plugin.

    <VirtualHost <portnumber>>
      name=<name of the vhost>
      <Plugin <name of check> >
        module = "<name of plugin>"
        # plugin options
        key=value
      </Plugin>
    </VirtualHost>

For individual plugin configuration options see the man page of the plugin:

    Mail::MtPolicyd::Plugin::<name of plugin>

## GLOBAL CONFIGURATION OPTIONS

- user

    user id to run as

- group

    group id to run as

- pid\_file

    location of the pid file

- log\_level

    Verbosity of logging: 0=>'err', 1=>'warning', 2=>'notice', 3=>'info', 4=>'debug'

- host

    ip address to bind to.

- port

    comma separated list of ports to listen on.

- min\_servers (default: 4)

    The minimum number of client processes to start.

- min\_spare\_servers (default: 4)

    The minimum number of client processes that should hanging around idle
    and wait for new connections.

    If the number of free processes is below this threshold mtpolicyd will start
    to create new child processes.

- max\_spare\_servers (default: 12)

    The maximum number of idle processes.

    If the number of idle processes is over this threshold mtpolicyd will start
    to shutdown child processes.

- max\_servers (default: 25)

    The absolute maximum number of child processes to start.

- max\_requests (default: 1000)
- max\_keepalive (default: 0)

    Number of requests after that mtpolicyd closes the connection
    or no limit if set to zero.

    Should be the same value as smtpd\_policy\_service\_reuse\_count\_limit (postfix >2.12)
    in postfix/smtpd configuration.

- vhost\_by\_policy\_context (default: 0)

    Select VirtualHost by 'policy\_context' request field.

    The policy\_context will be matched against the 'name' field of the VirtualHost.

    For example in postfix main.cf use advanced syntax:

        check_policy_service { inet:localhost:12345, policy_context=reputation }
        ...
        check_policy_service { inet:localhost:12345, policy_context=accounting }

    In mtpolicyd.conf:

        port="127.0.0.1:12345" # only 1 port
        vhost_by_policy_context=1
        <VirtualHost 12345>
          name=reputation
          ... plugins ...
        </VirtualHost>

        <VirtualHost 12345>
          name=accounting
          ... plugins ...
        </VirtualHost>

    The policy\_context feature will be available in postfix 3.1 and later.

    If you just need small differentiations consider using the [Mail::MtPolicyd::Plugin::Condition](https://metacpan.org/pod/Mail%3A%3AMtPolicyd%3A%3APlugin%3A%3ACondition)
    plugin to match against plugin\_context field.

- request\_timeout

    Maximum total time for one request.

# CONFIGURE CONNECTIONS

mtpolicyd has a global per process connection pool.

Connections could be registered within the connection pool using a <Connection>
block within the configuration. You must at least specify the name of the connection
and the module for the connection type.

    <Connection [name of connection]>
      module = "[connection type]"
      # ... addditional parameters
    </Connection>

Connection modules may require additional parameters.

Currently supported connection modules:

- Sql

    Perl DBI based connections for SQL databases.

    [Mail::MtPolicyd::Connection::Sql](https://metacpan.org/pod/Mail%3A%3AMtPolicyd%3A%3AConnection%3A%3ASql)

- Memcached

    Connection to a memcached server/cluster.

    [Mail::MtPolicyd::Connection::Memcached](https://metacpan.org/pod/Mail%3A%3AMtPolicyd%3A%3AConnection%3A%3AMemcached)

- Ldap

    Connection to an LDAP directory server.

    [Mail::MtPolicyd::Connection::Ldap](https://metacpan.org/pod/Mail%3A%3AMtPolicyd%3A%3AConnection%3A%3ALdap)

# SESSION MANAGEMENT

mtpolicyd implements session managemend to cache data across
different checks for requests with the same instance id.

mtpolicy is able to generate a session for each mail passed to it and store it within the
session cache.
The attached session information will be available to all following plugins across
child processes, virtual hosts and ports.

Plugins will use this session information to cache lookup etc. across multiple requests
for the same mail. Postfix will send a query for each recipient and for each configured
check\_policy\_service call.

To enable the SessionCache specify a <SessionCache> block within your configuration:

    <SessionCache>
      module = "Memcached"
      expire = "300"
      lock_wait=50
      lock_max_retry=50
      lock_timeout=10
    </SessionCache>

The example requires that a connection of type "Memcached" and the name
"memcached" is configured within the connection pool.
For details read [Mail::MtPolicyd::SessionCache::Memcached](https://metacpan.org/pod/Mail%3A%3AMtPolicyd%3A%3ASessionCache%3A%3AMemcached).

As of version 2.00 it is possible to implement different session caches.

Currently there are 2 session cache modules:

- [Mail::MtPolicyd::SessionCache::Memcached](https://metacpan.org/pod/Mail%3A%3AMtPolicyd%3A%3ASessionCache%3A%3AMemcached)
- [Mail::MtPolicyd::SessionCache::Redis](https://metacpan.org/pod/Mail%3A%3AMtPolicyd%3A%3ASessionCache%3A%3ARedis)

# PROCESSING OF REQUEST

The policy daemon will process all plugins in the order they appear in the configuration file.
It will stop as soon as a plugin returns an action and will return this action to the MTA.

# SCORING

Most plugins can be configured to not return an action if the performed check matched.

For example the RBL module could be set to passive mode and instead a score could be applied
to the request:

    <Plugin spamhaus>
      module = "RBL"
      mode = "passive"
      domain="zen.spamhaus.org"
      score=5
    </Plugin>

Check the documentation of the plugin for certain score/mode parameters.
Plugin may provide more than one mode/score parameters if the do several checks.

Now if you configure more than one RBL check the score will add up.
Later an action can be taken based on the score.
The ScoreAction plugin will return an action based on the score
and the AddScoreHeader plugin will prepend the score as a header to the mail:

    <Plugin ScoreReject>
      module = "ScoreAction"
      threshold = 15
      action = "reject sender ip %IP% is blocked (score=%SCORE%%SCORE_DETAIL%)"
    </Plugin>
    <Plugin ScoreTag>
      module = "AddScoreHeader"
      spam_score=5
    </Plugin>

# UPGRADING

## FROM 1.x to 2.x

With mtpolicyd 2.x configuration of connections and session cache has been changed.

### Database Connections

In mtpolicyd 2.00 the connections defined globaly in the configuration file
have been replaced by a dynamic connection pool.

The global options db\_\* ldap\_\* and memcached\_\* have been removed.

Instead connections are registered within a connection pool.

You can define them using <Connection> blocks:

    <Connection myconn>
      module = "<adapter>"
      # parameter = "value"
      # ...
    </Connection>

In mtpolicyd 1.x:

    db_dsn=DBI:mysql:mtpolicyd
    db_user=mtpolicyd
    db_password=secret

In mtpolicyd 2.x:

    <Connection db>
       dsn = "DBI:mysql:mtpolicyd"
       user = "mtpolicyd"
       password = "secret"
    </Connection>

All SQL modules will by default use the connection registered as "db".

See modules in Mail::MtPolicyd::Connection::\* for available connection adapters.

### Session Cache

Starting with mtpolicyd 2.x it is possible to use other session caches then memcached.

The global session\_\* parameters have been removed.

Instead the session cache is defined by a <SessionCache> block:

    <SessionCache>
      module = "<module>"
      # parameter = "value"
      # ...
    </SessionCache>

A memcached session cache in mtpolicyd v1.x:

    memcached_servers="127.0.0.1:11211"

    session_lock_wait=50
    session_lock_max_retry=50
    session_lock_timeout=10

In mtpolicyd 2.x:

    <Connection memcached>
      servers = "127.0.0.1:11211"
    </Connection>

    <SessionCache>
      module = "Memcached"
      # defaults to connection "memcached"
      # memcached = "memcached"
      lock_wait = "50"
      lock_max_retry = "50"
      lock_timeout = "10"
    </SessionCache>

If no <SessionCache> is defined it will default to the
dummy session cache module "None".

See modules in Mail::MtPolicyd::SessionCache::\* for available session
cache modules.

# AUTHOR

Markus Benning <ich@markusbenning.de>

# COPYRIGHT AND LICENSE

This software is Copyright (c) 2014 by Markus Benning <ich@markusbenning.de>.

This is free software, licensed under:

    The GNU General Public License, Version 2, June 1991
