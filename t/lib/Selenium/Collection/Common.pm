package Selenium::Collection::Common;

use warnings;
use strict;
use Moo;

use Test::More import => [qw(diag ok is)];

has 'driver' => (
    is => 'ro'
);

sub login_ok {
    my ($self, $login, $pwd) = @_;
    $login = 'administrator' unless $login;
    $pwd = 'administrator' unless $pwd;

    diag("Loading login page (logout first)");
    my $uri = $ENV{CATALYST_SERVER} || 'http://localhost:3000';
    $self->driver->get("$uri/logout"); # make sure we are logged out
    $self->driver->get("$uri/login");

    diag("Do Admin Login");
    ok($self->driver->find_text("Admin Sign In"), "Text Admin Sign In found");
    is($self->driver->get_title, '', 'No Tab Title was set');
    $self->driver->find_element('#username', 'css')->send_keys($login);
    $self->driver->find_element('#password', 'css')->send_keys($pwd);
    $self->driver->find_element('#submit', 'css')->click();

    diag("Checking Admin interface");
    is($self->driver->get_title, 'Dashboard', 'Tab Title is correct');
    is($self->driver->find_element('//*[@id="masthead"]//h2')->get_text(), "Dashboard", 'We are in the Dashboard. Login Successful');
}

sub create_domain {
    my ($self, $name, $reseller) = @_;
    return unless $name;

    $reseller = 'default' unless $reseller;
    diag('Go to domains page');
    $self->driver->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $self->driver->find_element("Domains", 'link_text')->click();

    diag('Try to add a domain');
    $self->driver->find_element('Create Domain', 'link_text')->click();
    $self->driver->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($self->driver->find_element_by_css('#reselleridtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $self->driver->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', $reseller);
    ok($self->driver->wait_for_text('//*[@id="reselleridtable"]/tbody/tr[1]/td[2]', $reseller), "Reseller and creation site are avalible");
    $self->driver->select_if_unselected('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input');
    $self->driver->find_element('//*[@id="domain"]')->send_keys($name);
    $self->driver->find_element('//*[@id="save"]')->click();
    ok($self->driver->find_element_by_xpath('//*[@id="content"]//div[contains(text(), "Domain successfully created")]'), "Label 'Domain successfully created' was shown");
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
    $self->driver->move_and_click('//*[@id="Domain_table"]/tbody/tr[1]//td//div//a[contains(text(),"Delete")]', 'xpath', '//*[@id="Domain_table"]');
    if($cancel){
        popup_confirm_cancel($self, 'We are NOT going to delete this domain');
    } else {
        popup_confirm_ok($self, 'We are going to delete this domain');
        ok($self->driver->find_element_by_xpath('//*[@id="content"]//div[contains(text(), "Domain successfully deleted!")]'), "Label 'Domain successfully deleted!' was shown");
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
    ok($self->driver->find_element_by_xpath('//*[@id="content"]//div[contains(text(), "Reseller successfully created.")]'), "Label 'Reseller successfully created.' was shown");
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
    ok($self->driver->find_element_by_xpath('//*[@id="content"]//div[contains(text(), "successfully created")]'), "Label 'Contract successfully created' was shown");
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
    $self->driver->move_and_click('//*[@id="Resellers_table"]/tbody/tr[1]//td//div//a[contains(text(),"Terminate")]', 'xpath', '//*[@id="Resellers_table"]');
    if($cancel){
        popup_confirm_cancel($self, 'We are NOT going to delete this reseller');
    } else {
        popup_confirm_ok($self, 'We are going to delete this reseller');
        ok($self->driver->find_element_by_xpath('//*[@id="content"]//div[contains(text(), "Successfully terminated reseller")]'), "Label 'Successfully terminated reseller' was shown");
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
    $self->driver->move_and_click('//*[@id="contract_table"]/tbody/tr[1]//td//div//a[contains(text(),"Terminate")]', 'xpath', '//*[@id="contract_table"]');
    if($cancel){
        popup_confirm_cancel($self, 'We are NOT going to delete this reseller contract');
    } else {
        popup_confirm_ok($self, 'We are going to delete this reseller contract');
        ok($self->driver->find_element_by_xpath('//*[@id="content"]//div[contains(text(), "Contract successfully terminated")]'), "Label 'Contract successfully terminated' was shown");
    };
}

sub create_rw_ruleset {
    my($self, $rulesetname, $resellername) = @_;
    return unless $rulesetname && $resellername;

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
    ok($self->driver->find_element_by_xpath('//*[@id="content"]//div[contains(text(), "Rewrite rule set successfully created")]'), "Label 'Rewrite rule set successfully created' was shown");
}

sub delete_rw_ruleset {
    my($self, $rulesetname, $cancel) = @_;
    return unless $rulesetname;

    diag('Go to Rewrite Rule Sets page');
    $self->driver->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $self->driver->find_element('Rewrite Rule Sets', 'link_text')->click();

    diag('Trying to delete the Rewrite Rule Set');
    $self->driver->fill_element('//*[@id="rewrite_rule_set_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($self->driver->find_element_by_css('#rewrite_rule_set_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $self->driver->fill_element('//*[@id="rewrite_rule_set_table_filter"]/label/input', 'xpath', $rulesetname);
    ok($self->driver->wait_for_text('//*[@id="rewrite_rule_set_table"]/tbody/tr[1]/td[3]', $rulesetname), 'Ruleset was found');
    $self->driver->move_and_click('//*[@id="rewrite_rule_set_table"]/tbody/tr[1]//td//div//a[contains(text(), "Delete")]', 'xpath', '//*[@id="rewrite_rule_set_table"]');
    if($cancel){
        popup_confirm_cancel($self, 'We are NOT going to delete this ruleset');
    } else {
        popup_confirm_ok($self, 'We are going to delete this ruleset');
        ok($self->driver->find_element_by_xpath('//*[@id="content"]//div[contains(text(), "Rewrite rule set successfully deleted")]'), "Label 'Rewrite rule set successfully deleted' was shown");
    };
}

sub create_customer {
    my($self, $customerid, $contactmail, $billingname, $pbx) = @_;
    return unless $customerid && $contactmail && $billingname;

    diag("Go to Customers page");
    $self->driver->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $self->driver->find_element("Customers", 'link_text')->click();

    diag("Trying to create a Customer");
    $self->driver->find_element('Create Customer', 'link_text')->click();
    $self->driver->fill_element('#contactidtable_filter input', 'css', 'thisshouldnotexist');
    $self->driver->find_element('#contactidtable tr > td.dataTables_empty', 'css');
    $self->driver->fill_element('#contactidtable_filter input', 'css', $contactmail);
    $self->driver->select_if_unselected('//table[@id="contactidtable"]/tbody/tr[1]/td//input[@type="checkbox"]');
    $self->driver->fill_element('#billing_profileidtable_filter input', 'css', 'thisshouldnotexist');
    $self->driver->find_element('#billing_profileidtable tr > td.dataTables_empty', 'css');
    $self->driver->fill_element('#billing_profileidtable_filter input', 'css', $billingname);
    $self->driver->select_if_unselected('//table[@id="billing_profileidtable"]/tbody/tr[1]/td//input[@type="checkbox"]');
    $self->driver->scroll_to_id('external_id');
    $self->driver->fill_element('#external_id', 'css', $customerid);
    if($pbx) {
        diag("Creating customer for PBX testing");
        $self->driver->select_if_unselected('//table[@id="productidtable"]/tbody/tr[1]/td[contains(text(),"Basic SIP Account")]/..//input[@type="checkbox"]');
    }
    $self->driver->find_element('#save', 'css')->click();
    ok($self->driver->find_element_by_xpath('//*[@id="content"]//div[contains(text(), "successfully created")]'), "Label 'Customer successfully created' was shown");
}

sub delete_customer {
    my($self, $customerid, $cancel) = @_;
    return unless $customerid;

    diag("Go to Customers page");
    $self->driver->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $self->driver->find_element("Customers", 'link_text')->click();

    diag("Trying to delete a Customer");
    $self->driver->fill_element('#Customer_table_filter input', 'css', 'thisshouldnotexist');
    ok($self->driver->find_element_by_css('#Customer_table tr > td.dataTables_empty'), 'Garbage text was not found');
    $self->driver->fill_element('#Customer_table_filter input', 'css', $customerid);
    ok($self->driver->wait_for_text('//*[@id="Customer_table"]/tbody/tr[1]/td[2]', $customerid), 'Found customer');
    $self->driver->move_and_click('//*[@id="Customer_table"]/tbody/tr[1]//td//div//a[contains(text(),"Terminate")]', 'xpath', '//*[@id="Customer_table"]');
    if($cancel){
        popup_confirm_cancel($self, 'We are NOT going to terminate this customer');
    } else {
        popup_confirm_ok($self, 'We are going to terminate this customer');
        ok($self->driver->find_element_by_xpath('//*[@id="content"]//div[contains(text(), "Customer successfully terminated")]'), "Label 'Customer successfully terminated' was shown");
    };
}

sub create_contact {
    my($self, $contactmail, $reseller) = @_;
    return unless $contactmail && $reseller;

    diag("Go to Contacts page");
    $self->driver->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $self->driver->find_element("Contacts", 'link_text')->click();

    diag("Trying to Create a new Contact");
    $self->driver->find_element("Create Contact", 'link_text')->click();
    $self->driver->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($self->driver->find_element_by_css('#reselleridtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $self->driver->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', $reseller);
    ok($self->driver->wait_for_text('//*[@id="reselleridtable"]/tbody/tr[1]/td[2]', $reseller), 'Reseller was found');
    $self->driver->select_if_unselected('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input');
    $self->driver->fill_element('//*[@id="firstname"]', 'xpath', 'Test');
    $self->driver->fill_element('//*[@id="lastname"]', 'xpath', 'User');
    $self->driver->fill_element('//*[@id="email"]', 'xpath', $contactmail);
    $self->driver->fill_element('//*[@id="company"]', 'xpath', 'SIPWISE');
    $self->driver->find_element('//*[@id="save"]')->click();
    ok($self->driver->find_element_by_xpath('//*[@id="content"]//div[contains(text(), "Contact successfully created")]'), "Label 'Contact successfully created' was shown");
}

sub delete_contact {
    my($self, $contactmail, $cancel) = @_;
    return unless $contactmail;

    diag("Go to Contacts page");
    $self->driver->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $self->driver->find_element("Contacts", 'link_text')->click();

    diag("Trying to Delete the Contact");
    $self->driver->fill_element('//*[@id="contact_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($self->driver->find_element_by_css('#contact_table tr > td.dataTables_empty'), "Garbage text was not found");
    $self->driver->fill_element('//*[@id="contact_table_filter"]/label/input', 'xpath', $contactmail);
    ok($self->driver->wait_for_text('//*[@id="contact_table"]/tbody/tr[1]/td[6]', $contactmail), 'Found contact');
    $self->driver->move_and_click('//*[@id="contact_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="contact_table_filter"]//input');
    if($cancel){
        popup_confirm_cancel($self, 'We are NOT going to terminate this contact');
    } else {
        popup_confirm_ok($self, 'We are going to terminate this contact');
        ok($self->driver->find_element_by_xpath('//*[@id="content"]//div[contains(text(), "Contact successfully terminated")]'), "Label 'Contact successfully terminated' was shown");
    };
}

sub create_billing_profile {
    my($self, $billingname, $resellername) = @_;
    return unless $billingname && $resellername;

    diag("Go to Billing page");
    $self->driver->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $self->driver->find_element("Billing", 'link_text')->click();

    diag("Create a billing profile");
    $self->driver->find_element('Create Billing Profile', 'link_text')->click();
    $self->driver->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($self->driver->find_element_by_css('#reselleridtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $self->driver->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', $resellername);
    ok($self->driver->wait_for_text('//*[@id="reselleridtable"]/tbody/tr[1]/td[2]', $resellername), 'Reseller was found');
    $self->driver->select_if_unselected('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input');
    $self->driver->fill_element('#name', 'css', $billingname);
    $self->driver->fill_element('[name=handle]', 'css', $billingname);
    $self->driver->find_element('//select[@id="fraud_interval_lock"]/option[contains(text(),"foreign calls")]')->click();
    $self->driver->find_element('//div[contains(@class,"modal")]//input[@type="submit"]')->click();
    ok($self->driver->find_element_by_xpath('//*[@id="content"]//div[contains(text(), "Billing profile successfully created")]'), "Label 'Billing profile successfully created' was shown");
}

sub delete_billing_profile {
    my($self, $billingname, $cancel) = @_;
    return unless $billingname;

    diag("Terminate our Billing Profile");
    $self->driver->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $self->driver->find_element("Billing", 'link_text')->click();
    $self->driver->fill_element('#billing_profile_table_filter label input', 'css', 'thisshouldnotexist');
    ok($self->driver->find_element_by_css('#billing_profile_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $self->driver->fill_element('#billing_profile_table_filter label input', 'css', $billingname);
    ok($self->driver->wait_for_text('//*[@id="billing_profile_table"]/tbody/tr/td[2]', $billingname), 'Billing profile was found');
    $self->driver->move_and_click('//*[@id="billing_profile_table"]/tbody/tr[1]//td//div//a[contains(text(), "Terminate")]', 'xpath', '//*[@id="billing_profile_table_filter"]//input');
    if($cancel){
        popup_confirm_cancel($self, 'We are NOT going to terminate this billing profile');
    } else {
        popup_confirm_ok($self, 'We are going to terminate this billing profile');
        ok($self->driver->find_element_by_xpath('//*[@id="content"]//div[contains(text(), "Billing profile successfully terminated")]'), "Label 'Billing profile successfully terminated' was shown");
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

sub crash_handler {
    my($self, $filename) = @_;
    my $jenkins = $ENV{JENKINS};
    is("tests", "failed", "This test wasnt successful, check complete test logs for more info");
    diag("--------------------------------SCRIPT HAS CRASHED---------------------------------");
    my $url = $self->driver->get_current_url();
    my $title = $self->driver->get_title();
    my $realtime = localtime();
    diag("Server: $ENV{CATALYST_SERVER}");
    diag("Url: $url");
    diag("Tab Title: $title");
    diag("Perl localtime(): $realtime");
    if($jenkins) {
        $self->driver->capture_screenshot($filename);
        diag("Screenshot has been taken and is avalible in " . $filename);
    };
    diag("------------------------------------------------------------------------------------");
}
1;