#!perl
 
use strict;
use warnings;

use Test::More;
 
use Test::BDD::Cucumber::Loader;
use Test::BDD::Cucumber::Harness::TestBuilder;
 
my ( $executor, @features ) = Test::BDD::Cucumber::Loader->load(
       't/' );
 
my $harness = Test::BDD::Cucumber::Harness::TestBuilder->new({});
$executor->execute( $_, $harness ) for @features;
done_testing;
