package Selenium::Collection::Common;

use warnings;
use strict;
use Moo;
use TryCatch;
use Test::More import => [qw(diag ok is)];

has 'driver' => (
    is => 'ro'
);

sub login_ok {
    my ($self, $login, $pwd) = @_;
    $login = 'administrator' unless $login;
    $pwd = 'administrator' unless $pwd;

    diag("Load login page (logout first)");
    my $uri = $ENV{CATALYST_SERVER} || 'http://localhost:3000';
    $self->driver->get("$uri/logout");
    $self->driver->get("$uri/login");

    diag("Do Admin Login");
    ok($self->driver->find_element('/html/body//div//h1[contains(text(), "Admin Sign In")]'), "Text 'Admin Sign In' found");
    is($self->driver->get_title, '', 'No Tab Title was set');
    $self->driver->fill_element('#username', 'css', $login);
    $self->driver->fill_element('#password', 'css', $pwd);
    $self->driver->find_element('#submit', 'css')->click();

    diag("Check Admin interface");
    is($self->driver->find_element('//*[@id="masthead"]//h2')->get_text(), "Dashboard", 'Dashboard is shown');
    is($self->driver->get_title, 'Dashboard', 'We are in the Dashboard. Login Successful');
}

sub create_domain {
    my ($self, $name, $reseller) = @_;
    return unless $name;
    $reseller = 'default' unless $reseller;

    diag("Go to 'Domains' page");
    $self->driver->scroll_to_element($self->driver->find_element('//*[@id="main-nav"]'));
    $self->driver->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $self->driver->find_element('Domains', 'link_text')->click();

    diag("Try to create Domain");
    $self->driver->find_element('Create Domain', 'link_text')->click();
    $self->driver->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($self->driver->find_element_by_css('#reselleridtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $self->driver->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', $reseller);
    ok($self->driver->find_element_by_xpath('//*[@id="reselleridtable"]//tr[1]/td[contains(text(), "' . $reseller . '")]'), 'Reseller found');
    $self->driver->select_if_unselected('//*[@id="reselleridtable"]/tbody/tr[1]//td//input');
    $self->driver->fill_element('//*[@id="domain"]', 'xpath', $name);
    $self->driver->find_element('//*[@id="save"]')->click();
    is($self->driver->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Domain successfully created',  'Correct Alert was shown');
}

sub delete_domain {
    my ($self, $name, $cancel) = @_;
    return unless $name;

    diag("Go to 'Domains' page");
    $self->driver->scroll_to_element($self->driver->find_element('//*[@id="main-nav"]'));
    $self->driver->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $self->driver->find_element('Domains', 'link_text')->click();

    diag("Try to delete Domain");
    $self->driver->fill_element('//*[@id="Domain_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($self->driver->find_element_by_css('#Domain_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $self->driver->fill_element('//*[@id="Domain_table_filter"]/label/input', 'xpath', $name);
    ok($self->driver->find_element_by_xpath('//*[@id="Domain_table"]//tr[1]/td[contains(text(), "' . $name . '")]'), 'Domain found');
    $self->driver->move_and_click('//*[@id="Domain_table"]/tbody/tr[1]//td//div//a[contains(text(),"Delete")]', 'xpath', '//*[@id="Domain_table_filter"]/label/input');
    if($cancel){
        popup_confirm_cancel($self, 'We are NOT going to delete this Domain');
    } else {
        popup_confirm_ok($self, 'We are going to delete this Domain');
        is($self->driver->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Domain successfully deleted!',  'Correct Alert was shown');
    };
}

sub create_reseller {
    my ($self, $name, $resellerid) = @_;
    return unless $name && $resellerid;

    diag("Go to 'Resellers' page");
    $self->driver->scroll_to_element($self->driver->find_element('//*[@id="main-nav"]'));
    $self->driver->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $self->driver->find_element('Resellers', 'link_text')->click();

    diag("Try to create Reseller");
    $self->driver->find_element('Create Reseller', 'link_text')->click();
    $self->driver->fill_element('//*[@id="contractidtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($self->driver->find_element_by_css('#contractidtable tr > td.dataTables_empty'), 'Garbage text was not found');
    $self->driver->fill_element('//*[@id="contractidtable_filter"]/label/input', 'xpath', $resellerid);
    ok($self->driver->find_element_by_xpath('//*[@id="contractidtable"]//tr[1]/td[contains(text(), "' . $resellerid . '")]'), 'Default Contact found');
    $self->driver->select_if_unselected('//*[@id="contractidtable"]/tbody/tr//td//input');
    $self->driver->fill_element('//*[@id="name"]', 'xpath', $name);
    $self->driver->find_element('//*[@id="save"]')->click();
    is($self->driver->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Reseller successfully created.',  'Correct Alert was shown');
}

sub create_reseller_contract {
    my ($self, $resellerid) = @_;
    return unless $resellerid;

    diag("Go to 'Reseller and Peering Contracts' page");
    $self->driver->scroll_to_element($self->driver->find_element('//*[@id="main-nav"]'));
    $self->driver->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $self->driver->find_element('Reseller and Peering Contracts', 'link_text')->click();

    diag("Try to create Reseller Contract");
    $self->driver->find_element('Create Reseller Contract', 'link_text')->click();
    $self->driver->fill_element('//*[@id="contactidtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($self->driver->find_element_by_css('#contactidtable tr > td.dataTables_empty'), 'Garbage text was not found');
    $self->driver->fill_element('//*[@id="contactidtable_filter"]/label/input', 'xpath', 'default-system@default.invalid');
    ok($self->driver->find_element_by_xpath('//*[@id="contactidtable"]//tr[1]/td[contains(text(), "default-system@default.invalid")]'), "Default Contact found");
    $self->driver->select_if_unselected('//*[@id="contactidtable"]/tbody/tr[1]//td//input');
    $self->driver->scroll_to_element($self->driver->find_element('//*[@id="external_id"]'));
    $self->driver->fill_element('//*[@id="billing_profileidtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($self->driver->find_element_by_css('#billing_profileidtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $self->driver->fill_element('//*[@id="billing_profileidtable_filter"]/label/input', 'xpath', 'Default Billing Profile');
    ok($self->driver->find_element_by_xpath('//*[@id="billing_profileidtable"]//tr[1]/td[contains(text(), "Default Billing Profile")]'), 'Default Billing Profile found');
    $self->driver->select_if_unselected('//*[@id="billing_profileidtable"]/tbody/tr[1]//td//input');
    $self->driver->fill_element('//*[@id="external_id"]', 'xpath', $resellerid);
    $self->driver->find_element('//*[@id="save"]')->click();
    ok($self->driver->find_element_by_xpath('//*[@id="content"]//div[contains(text(), "successfully created")]'), 'Correct Alert was shown');
}


sub delete_reseller {
    my ($self, $name, $cancel) = @_;
    return unless $name;

    diag("Go to 'Resellers' page");
    $self->driver->scroll_to_element($self->driver->find_element('//*[@id="main-nav"]'));
    $self->driver->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $self->driver->find_element('Resellers', 'link_text')->click();

    diag("Try to delete Reseller");
    $self->driver->fill_element('//*[@id="Resellers_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($self->driver->find_element_by_css('#Resellers_table tr > td.dataTables_empty'), 'Garbage text was not found');
    $self->driver->fill_element('//*[@id="Resellers_table_filter"]/label/input', 'xpath', $name);
    ok($self->driver->find_element_by_xpath('//*[@id="Resellers_table"]//tr[1]/td[contains(text(), "' . $name . '")]'), 'Entry found');
    $self->driver->move_and_click('//*[@id="Resellers_table"]/tbody/tr[1]//td//div//a[contains(text(),"Terminate")]', 'xpath', '//*[@id="Resellers_table_filter"]/label/input');
    if($cancel){
        popup_confirm_cancel($self, 'We are NOT going to delete this Reseller');
    } else {
        popup_confirm_ok($self, 'We are going to delete this Reseller');
        is($self->driver->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Successfully terminated reseller',  'Correct Alert was shown');
    };
}

sub delete_reseller_contract {
    my ($self, $resellerid, $cancel) = @_;
    return unless $resellerid;

    diag("Go to 'Reseller and Peering Contracts' page");
    $self->driver->scroll_to_element($self->driver->find_element('//*[@id="main-nav"]'));
    $self->driver->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $self->driver->find_element('Reseller and Peering Contracts', 'link_text')->click();

    diag("Try to delete Reseller Contract");
    $self->driver->fill_element('//*[@id="contract_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($self->driver->find_element_by_css('#contract_table tr > td.dataTables_empty'), 'Garbage text was not found');
    $self->driver->fill_element('//*[@id="contract_table_filter"]/label/input', 'xpath', $resellerid);
    ok($self->driver->find_element_by_xpath('//*[@id="contract_table"]//tr[1]/td[contains(text(), "' . $resellerid . '")]'), 'Entry found');
    $self->driver->move_and_click('//*[@id="contract_table"]/tbody/tr[1]//td//div//a[contains(text(),"Terminate")]', 'xpath', '//*[@id="contract_table_filter"]/label/input');
    if($cancel){
        popup_confirm_cancel($self, 'We are NOT going to delete this Reseller Contract');
    } else {
        popup_confirm_ok($self, 'We are going to delete this Reseller Contract');
        is($self->driver->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), "Contract successfully terminated",  "Correct Alert was shown");
    };
}

sub create_rw_ruleset {
    my($self, $rulesetname, $resellername) = @_;
    return unless $rulesetname && $resellername;

    diag("Go to 'Rewrite Rule Sets' page");
    $self->driver->scroll_to_element($self->driver->find_element('//*[@id="main-nav"]'));
    $self->driver->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $self->driver->find_element('Rewrite Rule Sets', 'link_text')->click();

    diag("Try to create Rewrite Rule Set");
    $self->driver->find_element('Create Rewrite Rule Set', 'link_text')->click();
    $self->driver->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($self->driver->find_element_by_css('#reselleridtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $self->driver->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', $resellername);
    ok($self->driver->find_element_by_xpath('//*[@id="reselleridtable"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller was found');
    $self->driver->select_if_unselected('//*[@id="reselleridtable"]/tbody/tr[1]//td//input');
    $self->driver->fill_element('//*[@id="name"]', 'xpath', $rulesetname);
    $self->driver->fill_element('//*[@id="description"]', 'xpath', 'For testing purposes');
    $self->driver->find_element('//*[@id="save"]')->click();
    is($self->driver->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Rewrite rule set successfully created',  'Correct Alert was shown');
}

sub delete_rw_ruleset {
    my($self, $rulesetname, $cancel) = @_;
    return unless $rulesetname;

    diag("Go to 'Rewrite Rule Sets' page");
    $self->driver->scroll_to_element($self->driver->find_element('//*[@id="main-nav"]'));
    $self->driver->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $self->driver->find_element('Rewrite Rule Sets', 'link_text')->click();

    diag("Try to delete Rewrite Rule Set");
    $self->driver->fill_element('//*[@id="rewrite_rule_set_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($self->driver->find_element_by_css('#rewrite_rule_set_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $self->driver->fill_element('//*[@id="rewrite_rule_set_table_filter"]/label/input', 'xpath', $rulesetname);
    ok($self->driver->find_element_by_xpath('//*[@id="rewrite_rule_set_table"]//tr[1]/td[contains(text(), "' . $rulesetname . '")]'), 'Ruleset was found');
    $self->driver->move_and_click('//*[@id="rewrite_rule_set_table"]/tbody/tr[1]//td//div//a[contains(text(), "Delete")]', 'xpath', '//*[@id="rewrite_rule_set_table_filter"]/label/input');
    if($cancel){
        popup_confirm_cancel($self, 'We are NOT going to delete this Rewrite Rule Set');
    } else {
        popup_confirm_ok($self, 'We are going to delete this Rewrite Rule Set');
        is($self->driver->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Rewrite rule set successfully deleted',  'Correct Alert was shown');
    };
}

sub create_customer {
    my($self, $customerid, $contactmail, $billingname, $special) = @_;
    return unless $customerid && $contactmail && $billingname;
    $special = 'empty' unless $special;

    diag("Go to 'Customers' page");
    $self->driver->scroll_to_element($self->driver->find_element('//*[@id="main-nav"]'));
    $self->driver->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $self->driver->find_element("Customers", 'link_text')->click();

    diag("Try to create Customer");
    $self->driver->find_element('Create Customer', 'link_text')->click();
    $self->driver->fill_element('#contactidtable_filter input', 'css', 'thisshouldnotexist');
    $self->driver->find_element('#contactidtable tr > td.dataTables_empty', 'css');
    $self->driver->fill_element('#contactidtable_filter input', 'css', $contactmail);
    $self->driver->select_if_unselected('//table[@id="contactidtable"]/tbody/tr[1]/td//input[@type="checkbox"]');
    try {
        $self->driver->set_timeout("implicit", 2_000);
        $self->driver->fill_element('#productidtable_filter input', 'css', 'thisshouldnotexist');
        $self->driver->find_element('#productidtable tr > td.dataTables_empty', 'css');
        $self->driver->fill_element('#productidtable_filter input', 'css', 'Basic');
        $self->driver->find_element_by_xpath('//*[@id="productidtable"]//tr[1]//td/input')->click();
        $self->driver->set_timeout("implicit", 10_000);
    } catch {
        $self->driver->set_timeout("implicit", 10_000);
    };
    $self->driver->fill_element('#billing_profileidtable_filter input', 'css', 'thisshouldnotexist');
    $self->driver->find_element('#billing_profileidtable tr > td.dataTables_empty', 'css');
    $self->driver->fill_element('#billing_profileidtable_filter input', 'css', $billingname);
    $self->driver->select_if_unselected('//table[@id="billing_profileidtable"]/tbody/tr[1]/td//input[@type="checkbox"]');
    if(index($special, 'locked') != -1) {
        diag("Creating locked Customer");
        $self->driver->scroll_to_element($self->driver->find_element('//*[@id="status"]'));
        $self->driver->find_element('//*[@id="status"]/option[contains(text(), "locked")]')->click();
    }
    $self->driver->fill_element('#external_id', 'css', $customerid);
    $self->driver->find_element('#save', 'css')->click();
    ok($self->driver->find_element_by_xpath('//*[@id="content"]//div[contains(text(), "successfully created")]'), 'Correct Alert was shown');
}

sub delete_customer {
    my($self, $customerid, $cancel) = @_;
    return unless $customerid;

    diag("Go to 'Customers' page");
    $self->driver->scroll_to_element($self->driver->find_element('//*[@id="main-nav"]'));
    $self->driver->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $self->driver->find_element("Customers", 'link_text')->click();

    diag("Try to delete Customer");
    $self->driver->fill_element('#Customer_table_filter input', 'css', 'thisshouldnotexist');
    ok($self->driver->find_element_by_css('#Customer_table tr > td.dataTables_empty'), 'Garbage text was not found');
    $self->driver->fill_element('#Customer_table_filter input', 'css', $customerid);
    ok($self->driver->find_element_by_xpath('//*[@id="Customer_table"]//tr[1]/td[contains(text(), "' . $customerid . '")]'), 'Found customer');
    $self->driver->move_and_click('//*[@id="Customer_table"]/tbody/tr[1]//td//div//a[contains(text(),"Terminate")]', 'xpath', '//*[@id="Customer_table_filter"]/label/input');
    if($cancel){
        popup_confirm_cancel($self, 'We are NOT going to delete this Customer');
    } else {
        popup_confirm_ok($self, 'We are going to delete this Customer');
        is($self->driver->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Customer successfully terminated',  'Correct Alert was shown');
    };
}

sub create_contact {
    my($self, $contactmail, $reseller) = @_;
    return unless $contactmail && $reseller;

    diag("Go to 'Contacts' page");
    $self->driver->scroll_to_element($self->driver->find_element('//*[@id="main-nav"]'));
    $self->driver->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $self->driver->find_element('Contacts', 'link_text')->click();

    diag("Try to create Contact");
    $self->driver->find_element('Create Contact', 'link_text')->click();
    $self->driver->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($self->driver->find_element_by_css('#reselleridtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $self->driver->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', $reseller);
    ok($self->driver->find_element_by_xpath('//*[@id="reselleridtable"]//tr[1]/td[contains(text(), "' . $reseller . '")]'), 'Reseller was found');
    $self->driver->select_if_unselected('//*[@id="reselleridtable"]/tbody/tr[1]//td//input');
    $self->driver->fill_element('//*[@id="firstname"]', 'xpath', 'Test');
    $self->driver->fill_element('//*[@id="lastname"]', 'xpath', 'User');
    $self->driver->fill_element('//*[@id="email"]', 'xpath', $contactmail);
    $self->driver->fill_element('//*[@id="company"]', 'xpath', 'SIPWISE');
    $self->driver->find_element('//*[@id="save"]')->click();
    is($self->driver->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Contact successfully created',  'Correct Alert was shown');
}

sub delete_contact {
    my($self, $contactmail, $cancel) = @_;
    return unless $contactmail;

    diag("Go to 'Contacts' page");
    $self->driver->scroll_to_element($self->driver->find_element('//*[@id="main-nav"]'));
    $self->driver->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $self->driver->find_element('Contacts', 'link_text')->click();

    diag("Try to delete Contact");
    $self->driver->fill_element('//*[@id="contact_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($self->driver->find_element_by_css('#contact_table tr > td.dataTables_empty'), "Garbage text was not found");
    $self->driver->fill_element('//*[@id="contact_table_filter"]/label/input', 'xpath', $contactmail);
    ok($self->driver->find_element_by_xpath('//*[@id="contact_table"]//tr[1]/td[contains(text(), "' . $contactmail . '")]'), 'Found contact');
    $self->driver->move_and_click('//*[@id="contact_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="contact_table_filter"]/label/input');
    if($cancel){
        popup_confirm_cancel($self, 'We are NOT going to delete this Contact');
    } else {
        popup_confirm_ok($self, 'We are going to delete this Contact');
        is($self->driver->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), "Contact successfully terminated",  "Correct Alert was shown");
    };
}

sub create_billing_profile {
    my($self, $billingname, $resellername) = @_;
    return unless $billingname && $resellername;

    diag("Go to 'Billing' page");
    $self->driver->scroll_to_element($self->driver->find_element('//*[@id="main-nav"]'));
    $self->driver->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $self->driver->find_element('Billing', 'link_text')->click();

    diag("Try to create billing profile");
    $self->driver->find_element('Create Billing Profile', 'link_text')->click();
    $self->driver->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($self->driver->find_element_by_css('#reselleridtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $self->driver->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', $resellername);
    ok($self->driver->find_element_by_xpath('//*[@id="reselleridtable"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller was found');
    $self->driver->select_if_unselected('//*[@id="reselleridtable"]/tbody/tr[1]//td//input');
    $self->driver->fill_element('#name', 'css', $billingname);
    $self->driver->fill_element('[name=handle]', 'css', $billingname);
    $self->driver->find_element('//select[@id="fraud_interval_lock"]/option[contains(text(),"foreign calls")]')->click();
    $self->driver->find_element('//div[contains(@class,"modal")]//input[@type="submit"]')->click();
    is($self->driver->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Billing profile successfully created',  'Correct Alert was shown');
}

sub delete_billing_profile {
    my($self, $billingname, $cancel) = @_;
    return unless $billingname;

    diag("Go to 'Billing' page");
    $self->driver->scroll_to_element($self->driver->find_element('//*[@id="main-nav"]'));
    $self->driver->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $self->driver->find_element('Billing', 'link_text')->click();

    diag("Try to delete Billing Profile");
    $self->driver->fill_element('#billing_profile_table_filter label input', 'css', 'thisshouldnotexist');
    ok($self->driver->find_element_by_css('#billing_profile_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $self->driver->fill_element('#billing_profile_table_filter label input', 'css', $billingname);
    ok($self->driver->find_element_by_xpath('//*[@id="billing_profile_table"]//tr[1]/td[contains(text(), "' . $billingname . '")]'), 'Billing profile was found');
    $self->driver->move_and_click('//*[@id="billing_profile_table"]/tbody/tr[1]//td//div//a[contains(text(), "Terminate")]', 'xpath', '//*[@id="billing_profile_table_filter"]/label/input');
    if($cancel){
        popup_confirm_cancel($self, 'We are NOT going to delete this Billing Profile');
    } else {
        popup_confirm_ok($self, 'We are going to delete this Billing Profile');
            is($self->driver->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Billing profile successfully terminated',  'Correct Alert was shown');
    };
}

sub create_ncos {
    my($self, $resellername, $ncosname) = @_;
    return unless $resellername && $ncosname;

    diag("Go to 'NCOS Levels' page");
    $self->driver->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $self->driver->find_element('NCOS Levels', 'link_text')->click();

    diag("Try to create NCOS");
    $self->driver->find_element('Create NCOS Level', 'link_text')->click();
    $self->driver->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($self->driver->find_element_by_css('#reselleridtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $self->driver->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', $resellername);
    ok($self->driver->find_element_by_xpath('//*[@id="reselleridtable"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller found');
    $self->driver->select_if_unselected('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input', 'xpath');
    $self->driver->fill_element('//*[@id="level"]', 'xpath', $ncosname);
    $self->driver->find_element('//*[@id="mode"]/option[@value="blacklist"]')->click();
    $self->driver->fill_element('//*[@id="description"]', 'xpath', 'This is a simple description');
    $self->driver->find_element('//*[@id="save"]')->click();
    is($self->driver->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'NCOS level successfully created',  'Correct Alert was shown');
}

sub delete_ncos {
    my($self, $ncosname, $cancel) = @_;
    return unless $ncosname;

    diag("Go to 'NCOS Levels' page");
    $self->driver->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $self->driver->find_element('NCOS Levels', 'link_text')->click();

    diag("Try to delete NCOS");
    $self->driver->fill_element('//*[@id="ncos_level_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($self->driver->find_element_by_css('#ncos_level_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $self->driver->fill_element('//*[@id="ncos_level_table_filter"]/label/input', 'xpath', $ncosname);
    ok($self->driver->find_element_by_xpath('//*[@id="ncos_level_table"]//tr[1]/td[contains(text(), "' . $ncosname . '")]'), "NCOS found");
    $self->driver->move_and_click('//*[@id="ncos_level_table"]/tbody/tr[1]/td/div/a[contains(text(), "Delete")]', 'xpath', '//*[@id="ncos_level_table_filter"]/label/input');

    if($cancel){
        popup_confirm_cancel($self, 'We are NOT going to delete this NCOS Entry');
    } else {
        popup_confirm_ok($self, 'We are going to delete this NCOS Entry');
        is($self->driver->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'NCOS level successfully deleted',  'Correct Alert was shown');
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
    is("tests", "failed", "This test was not successful, check complete test logs for more info");
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
        diag("Screenshot has been taken and is available in " . $filename);
    };
    diag("------------------------------------------------------------------------------------");
}
1;
