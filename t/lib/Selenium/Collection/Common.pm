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

sub delete_domain {
    my ($self, $name) = @_;
    return unless $name;

    diag('Go to domains page');
    $self->driver->find_element('//*[@id="main-nav"]/li[5]/a')->click();
    $self->driver->find_element('//*[@id="main-nav"]/li[5]/ul/li[6]/a')->click();

    diag('Try to delete a domain');
    $self->driver->fill_element('//*[@id="Domain_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($d->find_element_by_css('#Domain_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $self->driver->fill_element('//*[@id="Domain_table_filter"]/label/input', 'xpath', $name);
    ok($self->driver->wait_for_text('//*[@id="Domain_table"]/tbody/tr[1]/td[3]', $name), "Domain found");
    $self->driver->move_action(element => $self->driver->find_element('//*[@id="Domain_table"]/tbody/tr[1]/td[3]'));
    $self->driver->find_element('//*[@id="Domain_table"]/tbody/tr[1]/td[4]/div/a[1]')->click();
    $self->driver->find_element('//*[@id="dataConfirmOK"]')->click();
}
1;
