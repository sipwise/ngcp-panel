package Selenium::Collection::Common;

use warnings;
use strict;
use Moo;

use Test::More import => [qw(diag ok is)];

has 'driver' => (
    is => 'ro'
);

sub create_domain {
    my ($self, $name) = @_;
    return unless $name;

    diag('Go to domains page');
    $self->driver->find_element('//*[@id="main-nav"]/li[5]/a')->click();
    $self->driver->find_element('//*[@id="main-nav"]/li[5]/ul/li[6]/a')->click();

    diag('Try to add a domain');
    $self->driver->find_element('//*[@id="content"]/div/div[1]/span[2]/a')->click();
    ok($self->driver->wait_for_text('//*[@id="reselleridtable"]/tbody/tr[1]/td[2]', 'default'), "Default reseller and creation site are avalible");
    $self->driver->find_element('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input')->click(); #select default reseller
    $self->driver->find_element('//*[@id="domain"]')->send_keys($name);
    $self->driver->find_element('//*[@id="save"]')->click();
}
1;
