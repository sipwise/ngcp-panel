package Selenium::Collection::Common;

use warnings;
use strict;
use TryCatch;
use Moo;

use Test::More import => [qw(diag ok is)];

extends 'Selenium::Firefox';

sub create_domain {
    my ($driver, $name) = @_;
    return unless $name;
    diag('Logging in');
    $driver->login_ok();

    diag('Go to domains page');
    $driver->find_element('//*[@id="main-nav"]/li[5]/a')->click();
    $driver->find_element('//*[@id="main-nav"]/li[5]/ul/li[6]/a')->click();

    diag('Try to add a domain');
    $driver->find_element('//*[@id="content"]/div/div[1]/span[2]/a')->click();
    ok(1, "Domain website seems to exist");
    $driver->find_element('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input')->click(); #select default reseller
    $driver->find_element('//*[@id="domain"]')->send_keys($name);
    $driver->find_element('//*[@id="save"]')->click();
    ok(2, "Create field shows and works");
}
1;
