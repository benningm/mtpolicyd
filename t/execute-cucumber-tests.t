#!perl
 
use strict;
use warnings;

use Test::More;

eval {
    require Test::BDD::Cucumber::Loader;
    require Test::BDD::Cucumber::Harness::TestBuilder;
};
if( $@ ) {
        plan skip_all => 'module Test::BDD::Cucumber not installed';
}

my ( $executor, @features ) = Test::BDD::Cucumber::Loader->load(
       't/' );
 
my $harness = Test::BDD::Cucumber::Harness::TestBuilder->new({});
$executor->execute( $_, $harness ) for @features;
done_testing;
