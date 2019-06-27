use warnings;
use strict;

use lib 't/lib';
use Test::More import => [qw(done_testing is ok diag todo_skip)];
use Selenium::Remote::Driver::FirefoxExtensions;
use Selenium::Collection::Common;
use Selenium::Collection::Functions;

my ($port) = @_;
my $d = Selenium::Collection::Functions::create_driver($port);
my $c = Selenium::Collection::Common->new(
    driver => $d
);

my $resellername = ("reseller" . int(rand(100000)) . "test");
my $contractid = ("contract" . int(rand(100000)) . "test");
my $templatename = ("invoice" . int(rand(100000)) . "tem");
my $contactmail = ("contact" . int(rand(100000)) . '@test.org');
my $billingname = ("billing" . int(rand(100000)) . "test");
my $customerid = ("id" . int(rand(100000)) . "ok");
my $run_ok = 0;

$c->login_ok();
$c->create_reseller_contract($contractid);
$c->create_reseller($resellername, $contractid);
$c->create_contact($contactmail, $resellername);
$c->create_billing_profile($billingname, $resellername);
$c->create_customer($customerid, $contactmail, $billingname);

diag("Search for Customer");
$d->fill_element('#Customer_table_filter input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#Customer_table tr > td.dataTables_empty', 'css'), 'Garbage test not found');
$d->fill_element('#Customer_table_filter input', 'css', $customerid);
ok($d->wait_for_text('//*[@id="Customer_table"]/tbody/tr[1]/td[2]', $customerid), 'Customer found');
my $customernumber = $d->find_element('//*[@id="Customer_table"]/tbody/tr/td[1]')->get_text();

diag('Go to Invoice Templates page');
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element("Invoice Templates", 'link_text')->click();

diag("Trying to create a empty Invoice Template");
$d->find_element("Create Invoice Template", 'link_text')->click();
$d->unselect_if_selected('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input');
$d->find_element('//*[@id="save"]')->click();

diag("Check Error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Reseller field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Name field is required")]'));

diag("Fill in values");
$d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#reselleridtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', $resellername);
ok($d->wait_for_text('//*[@id="reselleridtable"]/tbody/tr[1]/td[2]', $resellername), "Reseller found");
$d->select_if_unselected('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input', 'xpath');
$d->fill_element('//*[@id="name"]', 'xpath', $templatename);
$d->find_element('//*[@id="save"]')->click();

diag("Search for Template");
$d->fill_element('//*[@id="InvoiceTemplate_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#InvoiceTemplate_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="InvoiceTemplate_table_filter"]/label/input', 'xpath', $templatename);

diag("Check details");
ok($d->find_element_by_xpath('//*[@id="content"]//div[contains(text(), "Invoice template successfully created")]'), "Label 'Invoice template successfully created' was shown");
ok($d->wait_for_text('//*[@id="InvoiceTemplate_table"]/tbody/tr/td[2]', $resellername), 'Reseller is correct');
ok($d->wait_for_text('//*[@id="InvoiceTemplate_table"]/tbody/tr/td[3]', $templatename), 'Name is correct');
ok($d->wait_for_text('//*[@id="InvoiceTemplate_table"]/tbody/tr/td[4]', 'svg'), 'Type is correct');

diag("Try to edit Invoice Template Information");
$templatename = ("invoice" . int(rand(100000)) . "tem");
$d->move_and_click('//*[@id="InvoiceTemplate_table"]//tr[1]//td//a[contains(text(), "Edit Meta")]', 'xpath', '//*[@id="InvoiceTemplate_table_filter"]//input');
$d->fill_element('//*[@id="name"]', 'xpath', $templatename);
$d->find_element('//*[@id="save"]')->click();

diag("Search for Template");
$d->fill_element('//*[@id="InvoiceTemplate_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#InvoiceTemplate_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="InvoiceTemplate_table_filter"]/label/input', 'xpath', $templatename);

diag("Check details");
ok($d->find_element_by_xpath('//*[@id="content"]//div[contains(text(), "Invoice template successfully updated")]'), "Label 'Invoice template successfully updated' was shown");
ok($d->wait_for_text('//*[@id="InvoiceTemplate_table"]/tbody/tr/td[2]', $resellername), 'Reseller is correct');
ok($d->wait_for_text('//*[@id="InvoiceTemplate_table"]/tbody/tr/td[3]', $templatename), 'Name is correct');
ok($d->wait_for_text('//*[@id="InvoiceTemplate_table"]/tbody/tr/td[4]', 'svg'), 'Type is correct');

diag('Go to Invoices page');
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element("Invoices", 'link_text')->click();

diag("Trying to create a empty Invoice");
$d->find_element("Create Invoice", 'link_text')->click();
$d->unselect_if_selected('//*[@id="templateidtable"]/tbody/tr[1]/td[4]/input');
$d->unselect_if_selected('//*[@id="contractidtable"]/tbody/tr[1]/td[6]/input');
$d->find_element('//*[@id="save"]')->click();

diag("Check Error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Customer field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Invoice Period field is required")]'));

diag("Fill in Values");
$d->fill_element('//*[@id="templateidtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#templateidtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="templateidtable_filter"]/label/input', 'xpath', $templatename);
ok($d->wait_for_text('//*[@id="templateidtable"]/tbody/tr[1]/td[3]', $templatename), 'Template was found');
$d->select_if_unselected('//*[@id="templateidtable"]/tbody/tr[1]/td[4]/input');
$d->scroll_to_element($d->find_element('//*[@id="contractidtable_filter"]/label/input'));
$d->fill_element('#contractidtable_filter input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#contractidtable tr > td.dataTables_empty', 'css'), 'Garbage test not found');
$d->fill_element('#contractidtable_filter input', 'css', $customerid);
ok($d->wait_for_text('//*[@id="contractidtable"]/tbody/tr[1]/td[4]', $customerid), 'Customer found');
$d->select_if_unselected('//*[@id="contractidtable"]/tbody/tr[1]/td[6]/input');
$d->find_element('//*[@id="period_datepicker"]')->click();
$d->find_element('//*[@id="ui-datepicker-div"]//button[contains(text(), "Today")]')->click();
$d->find_element('//*[@id="save"]')->click();

diag("Search for Invoice");
$d->fill_element('//*[@id="Invoice_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#Invoice_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="Invoice_table_filter"]/label/input', 'xpath', $contactmail);

diag("Check details");
ok($d->find_element_by_xpath('//*[@id="content"]//div[contains(text(), "successfully created")]'), "Label 'Invoice template successfully created' was shown");
ok($d->wait_for_text('//*[@id="Invoice_table"]/tbody/tr/td[2]', $customernumber), 'Customer# is correct');
ok($d->wait_for_text('//*[@id="Invoice_table"]/tbody/tr/td[3]', $contactmail), 'Customer Email is correct');

diag("Trying to NOT delete Invoice");
$d->move_and_click('//*[@id="Invoice_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="Invoice_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmCancel"]')->click();

diag("Check if Invoice is still here");
$d->fill_element('//*[@id="Invoice_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#Invoice_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="Invoice_table_filter"]/label/input', 'xpath', $contactmail);
ok($d->wait_for_text('//*[@id="Invoice_table"]/tbody/tr/td[2]', $customernumber), 'Invoice is still here');
ok($d->wait_for_text('//*[@id="Invoice_table"]/tbody/tr/td[3]', $contactmail), 'Invoice is still here');

diag("Trying to delete Invoice");
$d->move_and_click('//*[@id="Invoice_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="Invoice_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();

diag("Check if Invoice has been deleted");
$d->fill_element('//*[@id="Invoice_table_filter"]/label/input', 'xpath', $contactmail);
ok($d->find_element_by_xpath('//*[@id="content"]//div[contains(text(), "Invoice successfully deleted")]'), "Label 'Invoice template successfully created' was shown");
ok($d->find_element_by_css('#Invoice_table tr > td.dataTables_empty', 'css'), 'Invoice was deleted');

diag("Go to Invoice Templates page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element("Invoice Templates", 'link_text')->click();

diag("Trying to NOT delete Invoice Template");
$d->fill_element('//*[@id="InvoiceTemplate_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#InvoiceTemplate_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="InvoiceTemplate_table_filter"]/label/input', 'xpath', $templatename);
$d->move_and_click('//*[@id="InvoiceTemplate_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="InvoiceTemplate_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmCancel"]')->click();

diag("Check if Invoice Template is still here");
$d->fill_element('//*[@id="InvoiceTemplate_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#InvoiceTemplate_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="InvoiceTemplate_table_filter"]/label/input', 'xpath', $templatename);
ok($d->wait_for_text('//*[@id="InvoiceTemplate_table"]/tbody/tr/td[3]', $templatename), 'Template is still here');

diag("Trying to delete Invoice Template");
$d->move_and_click('//*[@id="InvoiceTemplate_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="InvoiceTemplate_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();

diag("Check if Invoice Template was deleted");
$d->fill_element('//*[@id="InvoiceTemplate_table_filter"]/label/input', 'xpath', $templatename);
ok($d->find_element_by_xpath('//*[@id="content"]//div[contains(text(), "Invoice template successfully deleted")]'), "Label 'Invoice template successfully deleted' was shown");
ok($d->find_element_by_css('#InvoiceTemplate_table tr > td.dataTables_empty', 'css'), 'Invoice Template was deleted');

$c->delete_customer($customerid);
$c->delete_reseller_contract($contractid);
$c->delete_reseller($resellername);
$c->delete_contact($contactmail);
$c->delete_billing_profile($billingname);

diag("This test run was successfull");
$run_ok = 1;

END {
    if(!$run_ok) {
        is("tests", "failed", "This test wasnt successful, check complete test logs for more info");
        diag("-----------------------SCRIPT HAS CRASHED-----------------------");
        my $url = $d->get_current_url();
        my $title = $d->get_title();
        my $realtime = localtime();
        if($d->find_text("Sorry!") || $d->find_text("Oops!")) {
            my $crashvar = $d->find_element_by_css('.error-container > h2:nth-child(2)')->get_text();
            my $incident = "incident number: not avalible";
            my $time = "time of incident: not avalible";
            eval {
                $incident = $d->find_element('.error-details > div:nth-child(2)', 'css')->get_text();
                $time = $d->find_element('.error-details > div:nth-child(3)', 'css')->get_text();
            };
            diag("Server: $ENV{CATALYST_SERVER}");
            diag("Url: $url");
            diag("Tab Title: $title");
            diag("Server error: $crashvar");
            diag($incident);
            diag($time);
            diag("Perl localtime(): $realtime");
        } elsif($d->find_text("nginx")) {
            my $crashvar = $d->find_element_by_css('body > center:nth-child(1) > h1:nth-child(1)')->get_text();
            diag("Server: $ENV{CATALYST_SERVER}");
            diag("Url: $url");
            diag("Tab Title: $title");
            diag("nginx error: $crashvar");
            diag("Perl localtime(): $realtime");
        } else {
            diag("Could not detect Server issues. Maybe script problems?");
            diag("If you still want to check server logs, here's some info");
            diag("Server: $ENV{CATALYST_SERVER}");
            diag("Url: $url");
            diag("Tab Title: $title");
            diag("Perl localtime(): $realtime");
        }
        diag("----------------------------------------------------------------");
    };
    done_testing;
}