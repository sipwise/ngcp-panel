use warnings;
use strict;

use lib 't/lib';
use Test::More import => [qw(done_testing is ok diag)];
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
my $templatename = ("template" . int(rand(100000)) . "mail");
my $run_ok = 0;

$c->login_ok();
$c->create_reseller_contract($contractid);

diag('Go to reseller page');
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Resellers', 'link_text')->click();

diag('Try to create a empty reseller');
$d->find_element('Create Reseller', 'link_text')->click();
$d->unselect_if_selected('//*[@id="contractidtable"]/tbody/tr/td[5]/input');
$d->find_element('//*[@id="save"]')->click();

diag('Check Error Messages');
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Contract field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Name field is required")]'));

diag('Create a legit reseller');
$d->find_element('#mod_close', 'css')->click();
$c->create_reseller($resellername, $contractid);

diag("Search our new reseller");
$d->fill_element('#Resellers_table_filter label input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#Resellers_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('#Resellers_table_filter label input', 'css', $resellername);

diag("Check Reseller Details");
ok($d->wait_for_text('//*[@id="Resellers_table"]/tbody/tr[1]/td[3]', $resellername), 'Reseller Name is correct');
ok($d->find_element_by_xpath('//*[@id="Resellers_table"]//tr//td[contains(text(), "active")]'), 'Status is correct');

diag("Click Edit on our newly created reseller");
$d->move_and_click('//*[@id="Resellers_table"]/tbody/tr[1]//td//div//a[contains(text(),"Edit")]', 'xpath', '//*[@id="Resellers_table_filter"]//input');

diag("Edit name and status");
$resellername = ("reseller" . int(rand(100000)) . "test");
$d->fill_element('//*[@id="name"]', 'xpath', $resellername);
$d->find_element('//*[@id="status"]/option[@value="locked"]')->click();
$d->find_element('#save', 'css')->click();

diag("Search our new reseller");
$d->fill_element('#Resellers_table_filter label input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#Resellers_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('#Resellers_table_filter label input', 'css', $resellername);

diag("Check Reseller Details");
ok($d->wait_for_text('//*[@id="Resellers_table"]/tbody/tr[1]/td[3]', $resellername), 'Reseller Name is correct');
ok($d->find_element_by_xpath('//*[@id="Resellers_table"]//tr//td[contains(text(), "locked")]'), 'Status is correct');

diag("Click Details on our newly created reseller");
$d->move_and_click('//*[@id="Resellers_table"]/tbody/tr[1]//td//div//a[contains(text(),"Details")]', 'xpath', '//*[@id="Resellers_table_filter"]//input');

diag("Create a empty Phonebook entry");
$d->scroll_to_element($d->find_element('//*[@id="reseller_details"]//div//div//a[contains(text(),"Phonebook")]'));
$d->find_element('//*[@id="reseller_details"]//div//div//a[contains(text(),"Phonebook")]')->click();
$d->scroll_to_element($d->find_element("Create Phonebook Entry", 'link_text'));
$d->find_element("Create Phonebook Entry", 'link_text')->click();
$d->find_element('//*[@id="save"]')->click();

diag("Check Error Messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Name field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Number field is required")]'));

diag("Fill in values");
$d->fill_element('//*[@id="name"]', 'xpath', 'testname');
$d->fill_element('//*[@id="number"]', 'xpath', '0123456789');
$d->find_element('//*[@id="save"]')->click();

diag("Searching Phonebook entry");
$d->scroll_to_element($d->find_element('//*[@id="reseller_details"]//div//div//a[contains(text(),"Phonebook")]'));
$d->find_element('//*[@id="reseller_details"]//div//div//a[contains(text(),"Phonebook")]')->click();
$d->scroll_to_element($d->find_element("Create Phonebook Entry", 'link_text'));
$d->fill_element('//*[@id="phonebook_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#phonebook_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="phonebook_table_filter"]/label/input', 'xpath', 'testname');

diag("Checking Phonebook entry details");
ok($d->wait_for_text('//*[@id="phonebook_table"]/tbody/tr/td[2]', 'testname'), 'Name is correct');
ok($d->wait_for_text('//*[@id="phonebook_table"]/tbody/tr/td[3]', '0123456789'), 'Number is correct');

diag("Edit Phonebook entry");
$d->move_and_click('//*[@id="phonebook_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="phonebook_table_filter"]/label/input');
$d->fill_element('//*[@id="name"]', 'xpath', 'newtestname');
$d->fill_element('//*[@id="number"]', 'xpath', '0987654321');
$d->find_element('//*[@id="save"]')->click();

diag("Searching Phonebook entry");
$d->scroll_to_element($d->find_element('//*[@id="reseller_details"]//div//div//a[contains(text(),"Phonebook")]'));
$d->find_element('//*[@id="reseller_details"]//div//div//a[contains(text(),"Phonebook")]')->click();
$d->scroll_to_element($d->find_element("Create Phonebook Entry", 'link_text'));
$d->fill_element('//*[@id="phonebook_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#phonebook_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="phonebook_table_filter"]/label/input', 'xpath', 'newtestname');

diag("Checking Phonebook entry details");
ok($d->wait_for_text('//*[@id="phonebook_table"]/tbody/tr/td[2]', 'newtestname'), 'Name is correct');
ok($d->wait_for_text('//*[@id="phonebook_table"]/tbody/tr/td[3]', '0987654321'), 'Number is correct');

diag('Go to Email Templates');
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element("Email Templates", 'link_text')->click();

diag('Trying to create a empty Template');
$d->find_element("Create Email Template", 'link_text')->click();
$d->unselect_if_selected('//*[@id="reselleridtable"]//tr[1]/td[5]/input');
$d->find_element('//*[@id="save"]')->click();

diag('Check Error Messages');
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Name field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "From Email Address field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Subject field is required")]'));

diag('Fill in values');
$d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#reselleridtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', $resellername);
ok($d->wait_for_text('//*[@id="reselleridtable"]/tbody/tr[1]/td[2]', $resellername), "Reseller found");
$d->select_if_unselected('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input');
$d->fill_element('//*[@id="name"]', 'xpath', $templatename);
$d->fill_element('//*[@id="from_email"]', 'xpath', 'default@mail.test');
$d->fill_element('//*[@id="subject"]', 'xpath', 'Testing Stuff');
$d->fill_element('//*[@id="body"]', 'xpath', 'Howdy Buddy, this is just a test text =)');
$d->fill_element('//*[@id="attachment_name"]', 'xpath', 'Random Character');
$d->find_element('//*[@id="save"]')->click();

diag('Searching new Template');
$d->fill_element('//*[@id="email_template_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#email_template_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="email_template_table_filter"]/label/input', 'xpath', $templatename);

diag('Check Details of Template');
ok($d->wait_for_text('//*[@id="email_template_table"]/tbody/tr/td[3]', $templatename), "Name is correct");
ok($d->wait_for_text('//*[@id="email_template_table"]/tbody/tr/td[2]', $resellername), "Reseller is correct");
ok($d->wait_for_text('//*[@id="email_template_table"]/tbody/tr/td[4]', 'default@mail.test'), "From Email is correct");
ok($d->wait_for_text('//*[@id="email_template_table"]/tbody/tr/td[5]', 'Testing Stuff'), "Subject is correct");

diag('Edit Email Template');
$templatename = ("template" . int(rand(100000)) . "mail");
$d->move_and_click('//*[@id="email_template_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="email_template_table_filter"]/label/input');
$d->fill_element('//*[@id="name"]', 'xpath', $templatename);
$d->fill_element('//*[@id="from_email"]', 'xpath', 'standard@mail.test');
$d->fill_element('//*[@id="subject"]', 'xpath', 'testing much stuff');
$d->fill_element('//*[@id="body"]', 'xpath', 'No seriously, this is just for testing');
$d->fill_element('//*[@id="attachment_name"]', 'xpath', '=)');
$d->find_element('//*[@id="save"]')->click();

diag('Searching new Template');
$d->fill_element('//*[@id="email_template_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#email_template_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="email_template_table_filter"]/label/input', 'xpath', $templatename);

diag('Check Details of Template');
ok($d->wait_for_text('//*[@id="email_template_table"]/tbody/tr/td[3]', $templatename), "Name is correct");
ok($d->wait_for_text('//*[@id="email_template_table"]/tbody/tr/td[2]', $resellername), "Reseller is correct");
ok($d->wait_for_text('//*[@id="email_template_table"]/tbody/tr/td[4]', 'standard@mail.test'), "From Email is correct");
ok($d->wait_for_text('//*[@id="email_template_table"]/tbody/tr/td[5]', 'testing much stuff'), "Subject is correct");

diag('Try to NOT delete Email Template');
$d->move_and_click('//*[@id="email_template_table"]//tr[1]/td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="email_template_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmCancel"]')->click();

diag('Check if Template Email is still here');
$d->fill_element('//*[@id="email_template_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#email_template_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="email_template_table_filter"]/label/input', 'xpath', $templatename);
ok($d->wait_for_text('//*[@id="email_template_table"]/tbody/tr/td[3]', $templatename), "Template is still here");

diag('Delete Template Email');
$d->move_and_click('//*[@id="email_template_table"]//tr[1]/td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="email_template_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();

diag('Check if Template Email was deleted');
$d->fill_element('//*[@id="email_template_table_filter"]/label/input', 'xpath', $templatename);
ok($d->find_element_by_css('#email_template_table tr > td.dataTables_empty', 'css'), 'Template was deleted');

diag("Open delete dialog and press cancel");
$c->delete_reseller_contract($contractid, 1);
$d->fill_element('//*[@id="contract_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#contract_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="contract_table_filter"]/label/input', 'xpath', $contractid);
ok($d->wait_for_text('//*[@id="contract_table"]/tbody/tr[1]/td[2]', $contractid), 'Reseller contract is still here');

diag('Open delete dialog and press delete');
$c->delete_reseller_contract($contractid, 0);
$d->fill_element('//*[@id="contract_table_filter"]/label/input', 'xpath', $contractid);
ok($d->find_element_by_css('#contract_table tr > td.dataTables_empty'), 'Reseller contract was deleted');

diag("Open delete dialog and press cancel");
$c->delete_reseller($resellername, 1);
$d->fill_element('//*[@id="Resellers_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#Resellers_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="Resellers_table_filter"]/label/input', 'xpath', $resellername);
ok($d->wait_for_text('//*[@id="Resellers_table"]/tbody/tr[1]/td[3]', $resellername), 'Reseller is still here');

diag('Open delete dialog and press delete');
$c->delete_reseller($resellername, 0);
$d->fill_element('//*[@id="Resellers_table_filter"]/label/input', 'xpath', $resellername);
ok($d->find_element_by_css('#Resellers_table tr > td.dataTables_empty'), 'Reseller was deleted');

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
        } elsif($d->find_element_by_xpath('//*[@id="content"]//div[@class="alert alert-error"]')) {
            my $label = "Label: could not get text";
            eval {
                $label = $d->find_element('//*[@id="content"]//div[@class="alert alert-error"]')->get_text();
            };
            diag("Server: $ENV{CATALYST_SERVER}");
            diag("Url: $url");
            diag("Tab Title: $title");
            diag("Error Label: $label");
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