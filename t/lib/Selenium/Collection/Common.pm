package Selenium::Collection::Common;

use warnings;
use strict;

use Test::More import => [qw(diag ok is)];

sub create_domain {
    my ($self, $name) = @_;
    return unless $self && $name;

    diag('Go to domains page');
    $self->find_element('//*[@id="main-nav"]/li[5]/a')->click();
    $self->find_element('//*[@id="main-nav"]/li[5]/ul/li[6]/a')->click();

    diag('Try to add a domain');
    $self->find_element('//*[@id="content"]/div/div[1]/span[2]/a')->click();
    ok(1, "Domain website seems to exist");
    $self->find_element('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input')->click(); #select default reseller
    $self->find_element('//*[@id="domain"]')->send_keys($name);
    $self->find_element('//*[@id="save"]')->click();
    ok(2, "Create field shows and works");
}
1;
