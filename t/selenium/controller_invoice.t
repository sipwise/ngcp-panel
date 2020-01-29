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
my $compstring;
my $run_ok = 0;

$c->login_ok();
$c->create_reseller_contract($contractid);
$c->create_reseller($resellername, $contractid);
$c->create_contact($contactmail, $resellername);
$c->create_billing_profile($billingname, $resellername);
$c->create_customer($customerid, $contactmail, $billingname);

diag("Go to 'Invoice Templates' page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Invoice Templates', 'link_text')->click();

diag("Try to create an empty Invoice Template");
$d->find_element('Create Invoice Template', 'link_text')->click();
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Create Invoice Template")]'), 'Edit window has been opened');
$d->unselect_if_selected('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input');
$d->find_element('//*[@id="save"]')->click();

diag("Check error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Reseller field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Name field is required")]'));

diag("Fill in values");
$d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#reselleridtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', $resellername);
ok($d->find_element_by_xpath('//*[@id="reselleridtable"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller found');
$d->select_if_unselected('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input', 'xpath');
$d->fill_element('//*[@id="name"]', 'xpath', $templatename);
$d->find_element('//*[@id="save"]')->click();

diag("Search Template");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Invoice template successfully created',  'Correct Alert was shown');
$d->fill_element('//*[@id="InvoiceTemplate_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#InvoiceTemplate_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="InvoiceTemplate_table_filter"]/label/input', 'xpath', $templatename);

diag("Check details");
ok($d->find_element_by_xpath('//*[@id="InvoiceTemplate_table"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller is correct');
ok($d->find_element_by_xpath('//*[@id="InvoiceTemplate_table"]//tr[1]/td[contains(text(), "' . $templatename . '")]'), 'Name is correct');
ok($d->find_element_by_xpath('//*[@id="InvoiceTemplate_table"]//tr[1]/td[contains(text(), "svg")]'), 'Type is correct');

diag("Edit Invoice Template");
$templatename = ("invoice" . int(rand(100000)) . "tem");
$d->move_and_click('//*[@id="InvoiceTemplate_table"]//tr[1]//td//a[contains(text(), "Edit Meta")]', 'xpath', '//*[@id="InvoiceTemplate_table_filter"]//input');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Invoice Template")]'), 'Edit window has been opened');
$d->fill_element('//*[@id="name"]', 'xpath', $templatename);
$d->find_element('//*[@id="save"]')->click();

diag("Search Template");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Invoice template successfully updated',  'Correct Alert was shown');
$d->fill_element('//*[@id="InvoiceTemplate_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#InvoiceTemplate_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="InvoiceTemplate_table_filter"]/label/input', 'xpath', $templatename);

diag("Check details");
ok($d->find_element_by_xpath('//*[@id="InvoiceTemplate_table"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller is correct');
ok($d->find_element_by_xpath('//*[@id="InvoiceTemplate_table"]//tr[1]/td[contains(text(), "' . $templatename . '")]'), 'Name is correct');
ok($d->find_element_by_xpath('//*[@id="InvoiceTemplate_table"]//tr[1]/td[contains(text(), "svg")]'), 'Type is correct');

diag("Go to 'Customers' page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Customers', 'link_text')->click();

diag("Search Customer");
$d->fill_element('#Customer_table_filter input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#Customer_table tr > td.dataTables_empty', 'css'), 'Garbage test not found');
$d->fill_element('#Customer_table_filter input', 'css', $customerid);
ok($d->find_element_by_xpath('//*[@id="Customer_table"]//tr[1]/td[contains(text(), "' . $customerid . '")]'), 'Customer found');
my $custnum = $d->find_element('//*[@id="Customer_table"]/tbody/tr/td[1]')->get_text();

diag("Add Invoice Template to Customer");
$d->move_and_click('//*[@id="Customer_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="Customer_table_filter"]/label/input');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Customer")]'), 'Edit window has been opened');
$d->fill_element('//*[@id="invoice_templateidtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#invoice_templateidtable tr > td.dataTables_empty', 'css'), 'Garbage test not found');
$d->fill_element('//*[@id="invoice_templateidtable_filter"]/label/input', 'xpath', $templatename);
ok($d->find_element_by_xpath('//*[@id="invoice_templateidtable"]//tr[1]/td[contains(text(), "' . $templatename . '")]'), 'Invoice Template was found');
$d->find_element('//*[@id="invoice_templateidtable"]//tr[1]/td[4]/input')->click();
$d->find_element('//*[@id="save"]')->click();

diag("Check if Invoice Template was applied");
$compstring = "Customer #" . $custnum . " successfully updated";
is($d->find_element_by_xpath('//*[@id="content"]//div[contains(@class, "alert")]')->get_text(), $compstring,  'Correct Alert was shown');
$d->fill_element('#Customer_table_filter input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#Customer_table tr > td.dataTables_empty', 'css'), 'Garbage test not found');
$d->fill_element('#Customer_table_filter input', 'css', $customerid);
ok($d->find_element_by_xpath('//*[@id="Customer_table"]//tr[1]/td[contains(text(), "' . $customerid . '")]'), 'Customer found');
$d->move_and_click('//*[@id="Customer_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="Customer_table_filter"]/label/input');
$d->scroll_to_element($d->find_element('//*[@id="Customer_table_filter"]/label/input'));
ok($d->find_element_by_xpath('//*[@id="invoice_templateidtable"]//tr[1]/td[contains(text(), "'. $templatename .'")]/../td[4]/input[@checked="checked"]'), 'Invoice Template was selected');
$d->find_element('//*[@id="mod_close"]')->click();

diag("Go to 'Invoices' page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Invoices', 'link_text')->click();

diag("Try to create a empty Invoice");
$d->find_element('Create Invoice', 'link_text')->click();
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Create Invoice")]'), 'Edit window has been opened');
$d->unselect_if_selected('//*[@id="templateidtable"]/tbody/tr[1]/td[4]/input');
$d->unselect_if_selected('//*[@id="contractidtable"]/tbody/tr[1]/td[6]/input');
$d->find_element('//*[@id="save"]')->click();

diag("Check error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Customer field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Invoice Period field is required")]'));

diag("Fill in values");
$d->fill_element('//*[@id="templateidtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#templateidtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="templateidtable_filter"]/label/input', 'xpath', $templatename);
ok($d->find_element_by_xpath('//*[@id="templateidtable"]//tr[1]/td[contains(text(), "' . $templatename . '")]'), 'Template was found');
$d->select_if_unselected('//*[@id="templateidtable"]/tbody/tr[1]/td[4]/input');
$d->fill_element('#contractidtable_filter input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#contractidtable tr > td.dataTables_empty', 'css'), 'Garbage test not found');
$d->fill_element('#contractidtable_filter input', 'css', $customerid);
ok($d->find_element_by_xpath('//*[@id="contractidtable"]//tr[1]/td[contains(text(), "' . $customerid . '")]'), 'Customer found');
$d->select_if_unselected('//*[@id="contractidtable"]/tbody/tr[1]/td[6]/input');
$d->find_element('//*[@id="period_datepicker"]')->click();
$d->find_element('//*[@id="ui-datepicker-div"]//button[contains(text(), "Today")]')->click();
$d->find_element('//*[@id="save"]')->click();

diag("Search Invoice");
$d->fill_element('//*[@id="Invoice_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#Invoice_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="Invoice_table_filter"]/label/input', 'xpath', $contactmail);

diag("Check details");
ok($d->find_element_by_xpath('//*[@id="Invoice_table"]//tr[1]/td[contains(text(), "' . $custnum . '")]'), 'Customer# is correct');
ok($d->find_element_by_xpath('//*[@id="Invoice_table"]//tr[1]/td[contains(text(), "' . $contactmail . '")]'), 'Customer Email is correct');
my $invnum = $d->get_text('//*[@id="Invoice_table"]/tbody/tr/td[1]');
$compstring = "Invoice #" . $invnum . " successfully created";
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), $compstring,  'Correct Alert was shown');

diag("Try to NOT delete Invoice");
$d->move_and_click('//*[@id="Invoice_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="Invoice_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmCancel"]')->click();

diag("Check if Invoice is still here");
$d->fill_element('//*[@id="Invoice_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#Invoice_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="Invoice_table_filter"]/label/input', 'xpath', $contactmail);
ok($d->find_element_by_xpath('//*[@id="Invoice_table"]//tr[1]/td[contains(text(), "' . $custnum . '")]'), 'Invoice is still here');
ok($d->find_element_by_xpath('//*[@id="Invoice_table"]//tr[1]/td[contains(text(), "' . $contactmail . '")]'), 'Invoice is still here');

diag("Try to delete Invoice");
$d->move_and_click('//*[@id="Invoice_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="Invoice_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();

diag("Check if Invoice has been deleted");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Invoice successfully deleted',  'Correct Alert was shown');
$d->fill_element('//*[@id="Invoice_table_filter"]/label/input', 'xpath', $contactmail);
ok($d->find_element_by_css('#Invoice_table tr > td.dataTables_empty', 'css'), 'Invoice has been deleted');

diag("Go to 'Invoice Templates' page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element("Invoice Templates", 'link_text')->click();

diag("Try to NOT delete Invoice Template");
$d->fill_element('//*[@id="InvoiceTemplate_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#InvoiceTemplate_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="InvoiceTemplate_table_filter"]/label/input', 'xpath', $templatename);
$d->move_and_click('//*[@id="InvoiceTemplate_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="InvoiceTemplate_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmCancel"]')->click();

diag("Check if Invoice Template is still here");
$d->fill_element('//*[@id="InvoiceTemplate_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#InvoiceTemplate_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="InvoiceTemplate_table_filter"]/label/input', 'xpath', $templatename);
ok($d->find_element_by_xpath('//*[@id="InvoiceTemplate_table"]//tr[1]/td[contains(text(), "' . $templatename . '")]'), 'Template is still here');

diag("Try to delete Invoice Template");
$d->move_and_click('//*[@id="InvoiceTemplate_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="InvoiceTemplate_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();

diag("Check if Invoice Template has been deleted");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Invoice template successfully deleted',  'Correct Alert was shown');
$d->fill_element('//*[@id="InvoiceTemplate_table_filter"]/label/input', 'xpath', $templatename);
ok($d->find_element_by_css('#InvoiceTemplate_table tr > td.dataTables_empty', 'css'), 'Invoice Template has been deleted');

$c->delete_customer($customerid);
$c->delete_reseller_contract($contractid);
$c->delete_reseller($resellername);
$c->delete_contact($contactmail);
$c->delete_billing_profile($billingname);

diag("This test run was successful");
$run_ok = 1;

END {
    if(!$run_ok) {
        $c->crash_handler("/results/crash_invoice.png");
    }
    $d->quit();
    done_testing;
}
