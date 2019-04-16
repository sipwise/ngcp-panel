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
    $self->driver->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $self->driver->find_element("Domains", 'link_text')->click();

    diag('Try to add a domain');
    $self->driver->find_element('//*[@id="content"]/div/div[1]/span[2]/a')->click();
    ok($self->driver->wait_for_text('//*[@id="reselleridtable"]/tbody/tr[1]/td[2]', 'default'), "Default reseller and creation site are avalible");
    $self->driver->find_element('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input')->click(); #select default reseller
    $self->driver->find_element('//*[@id="domain"]')->send_keys($name);
    $self->driver->find_element('//*[@id="save"]')->click();
}

sub delete_domain {
    my ($self, $name, $cancel) = @_;
    return unless $name;

    diag('Go to domains page');
    $self->driver->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $self->driver->find_element("Domains", 'link_text')->click();

    diag('Try to delete a domain');
    $self->driver->fill_element('//*[@id="Domain_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($self->driver->find_element_by_css('#Domain_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $self->driver->fill_element('//*[@id="Domain_table_filter"]/label/input', 'xpath', $name);
    ok($self->driver->wait_for_text('//*[@id="Domain_table"]/tbody/tr[1]/td[3]', $name), "Domain found");
    $self->driver->move_action(element => $self->driver->find_element('//*[@id="Domain_table"]'));
    $self->driver->move_action(element => $self->driver->find_element('//*[@id="Domain_table"]/tbody/tr[1]/td[3]'));
    $self->driver->find_element('//*[@id="Domain_table"]/tbody/tr[1]/td[4]/div/a[1]')->click();
    if($cancel){
        popup_confirm_cancel($self, 'We are NOT going to delete this domain');
    } else {
        popup_confirm_ok($self, 'We are going to delete this domain');
    };
}

sub create_reseller {
    my ($self, $name, $resellerid) = @_;
    return unless $name && $resellerid;

    diag('Go to reseller page');
    $self->driver->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $self->driver->find_element('Resellers', 'link_text')->click();

    diag('Try to create a reseller');
    $self->driver->find_element('Create Reseller', 'link_text')->click();
    $self->driver->fill_element('//*[@id="contractidtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($self->driver->find_element_by_css('#contractidtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $self->driver->fill_element('//*[@id="contractidtable_filter"]/label/input', 'xpath', $resellerid);
    ok($self->driver->wait_for_text('//*[@id="contractidtable"]/tbody/tr/td[3]', $resellerid), "Default Contact found");
    $self->driver->select_if_unselected('//*[@id="contractidtable"]/tbody/tr/td[5]/input');
    $self->driver->fill_element('//*[@id="name"]', 'xpath', $name);
    $self->driver->find_element('//*[@id="save"]')->click();
}

sub create_reseller_contract {
    my ($self, $resellerid) = @_;
    return unless $resellerid;

    diag('Go to Reseller and Peering Contracts page');
    $self->driver->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $self->driver->find_element('Reseller and Peering Contracts', 'link_text')->click();

    diag('Try to create a reseller contract');
    $self->driver->find_element('Create Reseller Contract', 'link_text')->click();
    if(!$self->driver->find_element('//*[@id="contactidtable"]/tbody/tr[1]/td[4]')->get_text() eq 'default-system@default.invalid') {
        $self->driver->fill_element('//*[@id="contactidtable_filter"]/label/input', 'xpath', 'default-system@default.invalid');
        ok($self->driver->wait_for_text('//*[@id="contactidtable"]/tbody/tr[1]/td[4]', 'default-system@default.invalid'), "Default Contact found");
        $self->driver->select_if_unselected('//*[@id="contactidtable"]/tbody/tr[1]/td[5]/input');
    } else {
        ok($self->driver->select_if_unselected('//*[@id="contactidtable"]/tbody/tr[1]/td[5]/input'), "Default Contact found");
    };
    $self->driver->scroll_to_element($self->driver->find_element('//*[@id="external_id"]'));

    $self->driver->fill_element('//*[@id="billing_profileidtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($self->driver->find_element_by_css('#billing_profileidtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $self->driver->fill_element('//*[@id="billing_profileidtable_filter"]/label/input', 'xpath', 'Default Billing Profile');
    ok($self->driver->wait_for_text('//*[@id="billing_profileidtable"]/tbody/tr/td[3]', 'Default Billing Profile'), "Default Billing Profile found");
    $self->driver->select_if_unselected('//*[@id="billing_profileidtable"]/tbody/tr[1]/td[4]/input');

    $self->driver->fill_element('//*[@id="external_id"]', 'xpath', $resellerid);
    $self->driver->find_element('//*[@id="save"]')->click();
}


sub delete_reseller {
    my ($self, $name, $cancel) = @_;
    return unless $name;

    diag('Go to reseller page');
    $self->driver->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $self->driver->find_element('Resellers', 'link_text')->click();
    $self->driver->fill_element('//*[@id="Resellers_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($self->driver->find_element_by_css('#Resellers_table tr > td.dataTables_empty'), 'Garbage text was not found');
    $self->driver->fill_element('//*[@id="Resellers_table_filter"]/label/input', 'xpath', $name);
    ok($self->driver->wait_for_text('//*[@id="Resellers_table"]/tbody/tr[1]/td[3]', $name), 'Entry found');
    $self->driver->move_action(element => $self->driver->find_element('//*[@id="Resellers_table"]'));
    $self->driver->move_action(element => $self->driver->find_element('//*[@id="Resellers_table"]/tbody/tr[1]/td[3]'));
    $self->driver->find_element('//*[@id="Resellers_table"]/tbody/tr[1]/td[5]/div/a[2]')->click();
    if($cancel){
        popup_confirm_cancel($self, 'We are NOT going to delete this reseller');
    } else {
        popup_confirm_ok($self, 'We are going to delete this reseller');
    };
}

sub delete_reseller_contract {
    my ($self, $resellerid, $cancel) = @_;
    return unless $resellerid;

    diag('Go to Reseller and Peering Contracts page');
    $self->driver->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $self->driver->find_element('Reseller and Peering Contracts', 'link_text')->click();
    $self->driver->fill_element('//*[@id="contract_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($self->driver->find_element_by_css('#contract_table tr > td.dataTables_empty'), 'Garbage text was not found');
    $self->driver->fill_element('//*[@id="contract_table_filter"]/label/input', 'xpath', $resellerid);
    ok($self->driver->wait_for_text('//*[@id="contract_table"]/tbody/tr/td[2]', $resellerid), 'Entry found');
    $self->driver->move_action(element => $self->driver->find_element('//*[@id="contract_table"]'));
    $self->driver->move_action(element => $self->driver->find_element('//*[@id="contract_table"]/tbody/tr[1]/td[3]'));
    $self->driver->find_element('//*[@id="contract_table"]/tbody/tr[1]/td[7]/div/a[2]')->click();
    if($cancel){
        popup_confirm_cancel($self, 'We are NOT going to delete this reseller contract');
    } else {
        popup_confirm_ok($self, 'We are going to delete this reseller contract');
    };
}

sub popup_confirm_ok {
    my($self, $message) = @_;

    diag($message);
    $self->driver->find_element('//*[@id="dataConfirmOK"]')->click();
}

sub popup_confirm_cancel {
    my($self, $message) = @_;

    diag($message);
    $self->driver->find_element('//*[@id="dataConfirmCancel"]')->click();
}
1;