#!perl

requires 'perl', '5.8.5';

requires 'BerkeleyDB';
requires 'BerkeleyDB::Hash';
requires 'Cache::Memcached';
requires 'Redis';
requires 'Config::General';
requires 'DBI';
requires 'Data::Dumper';
requires 'File::Slurp';
requires 'Geo::IP';
requires 'Getopt::Long';
requires 'HTTP::Request::Common';
requires 'IO::Handle';
requires 'IO::Socket::INET';
requires 'IO::Socket::UNIX';
requires 'JSON';
requires 'LWP::UserAgent';
requires 'Mail::RBL';
requires 'Mail::SPF';
requires 'Moose';
requires 'Moose::Role';
requires 'Moose::Util::TypeConstraints';
requires 'MooseX::Getopt';
requires 'MooseX::Role::Parameterized';
requires 'MooseX::Singleton';
requires 'Net::DNS::Resolver';
requires 'Net::LDAP';
requires 'Net::LDAP::Util';
requires 'Net::SMTP::Verify';
requires 'Net::Server::PreFork';
requires 'NetAddr::IP';
requires 'Tie::IxHash';
requires 'Time::HiRes';
requires 'Time::Piece';
requires 'Time::Seconds';
requires 'namespace::autoclean';
requires 'strict';
requires 'Storable';

on 'test' => sub {
  requires 'DBD::SQLite';
  requires 'File::Find';
  requires 'File::ReadBackwards';
  requires 'File::Temp';
  requires 'IO::File';
  requires 'Template';
  requires 'Test::BDD::Cucumber::Harness::TestBuilder';
  requires 'Test::BDD::Cucumber::Loader';
  requires 'Test::Exception';
  requires 'Test::RedisDB';
  requires 'Test::Mock::Net::Server::Mail';
  requires 'Test::Net::LDAP::Mock';
  requires 'Test::MockObject';
  requires 'Test::More';
  requires 'Test::Pod';
  requires 'String::Random';
  requires 'Test::Deep';
};

on 'develop' => sub {
  requires 'ExtUtils::MakeMaker';
  requires 'Dist::Zilla::Plugin::MetaProvides::Package';
  requires 'Dist::Zilla::Plugin::Prereqs::FromCPANfile';
  requires 'Dist::Zilla::Plugin::ChangelogFromGit';
  requires 'Dist::Zilla::Plugin::ChangelogFromGit::Debian';
  requires 'Dist::Zilla::Plugin::FileFinder::ByName';
  requires 'Dist::Zilla::Plugin::Git::NextVersion';
  requires 'Dist::Zilla::Plugin::MetaJSON';
  requires 'Dist::Zilla::Plugin::MetaResources';
  requires 'Dist::Zilla::Plugin::OurPkgVersion';
  requires 'Dist::Zilla::Plugin::PodSyntaxTests';
  requires 'Dist::Zilla::Plugin::PodWeaver';
  requires 'Dist::Zilla::Plugin::Prereqs';
  requires 'Dist::Zilla::Plugin::PruneFiles';
  requires 'Dist::Zilla::Plugin::Template::Tiny';
  requires 'Dist::Zilla::Plugin::Test::Perl::Critic';
  requires 'Dist::Zilla::Plugin::TravisYML';
  requires 'Dist::Zilla::PluginBundle::Basic';
  requires 'Dist::Zilla::PluginBundle::Git';
};

feature 'mysql' => sub {
  recommends 'DBD::mysql';
}
