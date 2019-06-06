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
    $self->driver->find_element('Create Domain', 'link_text')->click();
    ok($self->driver->wait_for_text('//*[@id="reselleridtable"]/tbody/tr[1]/td[2]', 'default'), "Default reseller and creation site are avalible");
    $self->driver->select_if_unselected('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input'); #select default reseller
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
    $self->driver->move_action(element => $self->driver->find_element('//*[@id="Domain_table"]/tbody/tr[1]//td//div//a[contains(text(),"Delete")]'));
    $self->driver->find_element('//*[@id="Domain_table"]/tbody/tr[1]//td//div//a[contains(text(),"Delete")]')->click();
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
    ok($self->driver->find_element_by_css('#contractidtable tr > td.dataTables_empty'), 'Garbage text was not found');
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
    $self->driver->fill_element('//*[@id="contactidtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($self->driver->find_element_by_css('#contactidtable tr > td.dataTables_empty'), 'Garbage text was not found');
    $self->driver->fill_element('//*[@id="contactidtable_filter"]/label/input', 'xpath', 'default-system@default.invalid');
    ok($self->driver->wait_for_text('//*[@id="contactidtable"]/tbody/tr[1]/td[4]', 'default-system@default.invalid'), "Default Contact found");
    $self->driver->select_if_unselected('//*[@id="contactidtable"]/tbody/tr[1]/td[5]/input');
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

    diag('Trying to delete a reseller');
    $self->driver->fill_element('//*[@id="Resellers_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($self->driver->find_element_by_css('#Resellers_table tr > td.dataTables_empty'), 'Garbage text was not found');
    $self->driver->fill_element('//*[@id="Resellers_table_filter"]/label/input', 'xpath', $name);
    ok($self->driver->wait_for_text('//*[@id="Resellers_table"]/tbody/tr[1]/td[3]', $name), 'Entry found');
    $self->driver->move_action(element => $self->driver->find_element('//*[@id="Resellers_table"]'));
    $self->driver->move_action(element => $self->driver->find_element('//*[@id="Resellers_table"]/tbody/tr[1]//td//div//a[contains(text(),"Terminate")]'));
    $self->driver->find_element('//*[@id="Resellers_table"]/tbody/tr[1]//td//div//a[contains(text(),"Terminate")]')->click();
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

    diag('Trying to delete reseller contract');
    $self->driver->fill_element('//*[@id="contract_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($self->driver->find_element_by_css('#contract_table tr > td.dataTables_empty'), 'Garbage text was not found');
    $self->driver->fill_element('//*[@id="contract_table_filter"]/label/input', 'xpath', $resellerid);
    ok($self->driver->wait_for_text('//*[@id="contract_table"]/tbody/tr/td[2]', $resellerid), 'Entry found');
    $self->driver->move_action(element => $self->driver->find_element('//*[@id="contract_table"]'));
    $self->driver->move_action(element => $self->driver->find_element('//*[@id="contract_table"]/tbody/tr[1]//td//div//a[contains(text(),"Terminate")]'));
    $self->driver->find_element('//*[@id="contract_table"]/tbody/tr[1]//td//div//a[contains(text(),"Terminate")]')->click();
    if($cancel){
        popup_confirm_cancel($self, 'We are NOT going to delete this reseller contract');
    } else {
        popup_confirm_ok($self, 'We are going to delete this reseller contract');
    };
}

sub create_rw_ruleset {
    my($self, $resellername, $rulesetname) = @_;

    diag('Go to Rewrite Rule Sets page');
    $self->driver->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $self->driver->find_element('Rewrite Rule Sets', 'link_text')->click();

    diag('Trying to create a Rewrite Rule Set');
    $self->driver->find_element('Create Rewrite Rule Set', 'link_text')->click();
    $self->driver->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($self->driver->find_element_by_css('#reselleridtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $self->driver->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', $resellername);
    ok($self->driver->wait_for_text('//*[@id="reselleridtable"]/tbody/tr[1]/td[2]', $resellername), 'Reseller was found');
    $self->driver->select_if_unselected('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input');
    $self->driver->fill_element('//*[@id="name"]', 'xpath', $rulesetname);
    $self->driver->fill_element('//*[@id="description"]', 'xpath', 'For testing purposes');
    $self->driver->find_element('//*[@id="save"]')->click();
}

sub delete_rw_ruleset {
    my($self, $rulesetname) = @_;

    diag('Go to Rewrite Rule Sets page');
    $self->driver->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $self->driver->find_element('Rewrite Rule Sets', 'link_text')->click();

    diag('Trying to delete the Rewrite Rule Set');
    $self->driver->fill_element('//*[@id="rewrite_rule_set_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($self->driver->find_element_by_css('#rewrite_rule_set_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $self->driver->fill_element('//*[@id="rewrite_rule_set_table_filter"]/label/input', 'xpath', $rulesetname);
    ok($self->driver->wait_for_text('//*[@id="rewrite_rule_set_table"]/tbody/tr[1]/td[3]', $rulesetname), 'Ruleset was found');
    $self->driver->move_action(element => $self->driver->find_element('//*[@id="rewrite_rule_set_table"]/tbody/tr[1]//td//div//a[contains(text(), "Delete")]'));
    $self->driver->find_element('//*[@id="rewrite_rule_set_table"]/tbody/tr[1]//td//div//a[contains(text(), "Delete")]')->click();
    $self->driver->find_element('//*[@id="dataConfirmOK"]')->click();
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