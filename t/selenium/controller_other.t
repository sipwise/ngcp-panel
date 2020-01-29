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
my $domainstring = ("domain" . int(rand(100000)) . ".example.org");
my $soundsetname = ("sound" . int(rand(100000)) . "set");
my $phonebookname = ("phone" . int(rand(100000)) . "book");
my $contactmail = ("contact" . int(rand(100000)) . '@test.org');
my $run_ok = 0;

$c->login_ok();
$c->create_reseller_contract($contractid);
$c->create_reseller($resellername, $contractid);
$c->create_domain($domainstring);

diag("Go to 'Call List Suppressions' page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Call List Suppressions', 'link_text')->click();

diag("Try to create an empty Call List Suppression");
$d->find_element('Create call list suppression', 'link_text')->click();
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Create Call List Suppression")]'), "Edit window has been opened");
$d->find_element('//*[@id="save"]')->click();

diag("Check error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Pattern field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Label field is required")]'));

diag("Fill in values");
$d->fill_element('//*[@id="domain"]', 'xpath', $domainstring);
$d->fill_element('//*[@id="pattern"]', 'xpath', 'test');
$d->fill_element('//*[@id="label"]', 'xpath', 'label');
$d->find_element('//*[@id="save"]')->click();

diag("Search Call List Suppression");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Call list suppression successfully created',  'Correct Alert was shown');
$d->fill_element('//*[@id="call_list_suppression_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#call_list_suppression_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="call_list_suppression_table_filter"]/label/input', 'xpath', $domainstring);

diag("Check details");
ok($d->find_element_by_xpath('//*[@id="call_list_suppression_table"]//tr[1]/td[contains(text(), "' . $domainstring . '")]'), "Domain is correct");
ok($d->find_element_by_xpath('//*[@id="call_list_suppression_table"]//tr[1]/td[contains(text(), "outgoing")]'), 'Direction is correct');
ok($d->find_element_by_xpath('//*[@id="call_list_suppression_table"]//tr[1]/td[contains(text(), "test")]'), 'Pattern is correct');
ok($d->find_element_by_xpath('//*[@id="call_list_suppression_table"]//tr[1]/td[contains(text(), "filter")]'), 'Mode is correct');
ok($d->find_element_by_xpath('//*[@id="call_list_suppression_table"]//tr[1]/td[contains(text(), "label")]'), 'Label is correct');

diag("Edit Call List Suppression");
$d->move_and_click('//*[@id="call_list_suppression_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="call_list_suppression_table_filter"]//input');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Call List Suppression")]'), 'Edit window has been opened');
$d->find_element('//*[@id="domain"]')->click();
sleep 1;
$d->fill_element('//*[@id="domain"]', 'xpath', $domainstring);
$d->find_element('//*[@id="direction"]/option[@value="incoming"]')->click();
$d->fill_element('//*[@id="pattern"]', 'xpath', 'testing');
$d->find_element('//*[@id="mode"]/option[@value="obfuscate"]')->click();
$d->fill_element('//*[@id="label"]', 'xpath', 'text');
$d->find_element('//*[@id="save"]')->click();

diag("Search Call List Suppression");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Call list suppression successfully updated',  'Correct Alert was shown');
$d->fill_element('//*[@id="call_list_suppression_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#call_list_suppression_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="call_list_suppression_table_filter"]/label/input', 'xpath', $domainstring);

diag("Check details");
ok($d->find_element_by_xpath('//*[@id="call_list_suppression_table"]//tr[1]/td[contains(text(), "' . $domainstring . '")]'), "Domain is correct");
ok($d->find_element_by_xpath('//*[@id="call_list_suppression_table"]//tr[1]/td[contains(text(), "incoming")]'), 'Direction is correct');
ok($d->find_element_by_xpath('//*[@id="call_list_suppression_table"]//tr[1]/td[contains(text(), "testing")]'), 'Pattern is correct');
ok($d->find_element_by_xpath('//*[@id="call_list_suppression_table"]//tr[1]/td[contains(text(), "obfuscate")]'), 'Mode is correct');
ok($d->find_element_by_xpath('//*[@id="call_list_suppression_table"]//tr[1]/td[contains(text(), "text")]'), 'Label is correct');

diag("Try to NOT delete Call List Suppression");
$d->move_and_click('//*[@id="call_list_suppression_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="call_list_suppression_table_filter"]//input');
$d->find_element('//*[@id="dataConfirmCancel"]')->click();

diag("Check if Call List Suppression is still here");
$d->fill_element('//*[@id="call_list_suppression_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#call_list_suppression_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="call_list_suppression_table_filter"]/label/input', 'xpath', $domainstring);
ok($d->find_element_by_xpath('//*[@id="call_list_suppression_table"]//tr[1]/td[contains(text(), "' . $domainstring . '")]'), 'Call List Suppression is still here');

diag("Try to delete Call List Suppression");
$d->move_and_click('//*[@id="call_list_suppression_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="call_list_suppression_table_filter"]//input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();

diag("Check if Call List Suppression has been deleted");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Call list suppression successfully deleted',  'Correct Alert was shown');
$d->fill_element('//*[@id="call_list_suppression_table_filter"]/label/input', 'xpath', $domainstring);
ok($d->find_element_by_css('#call_list_suppression_table tr > td.dataTables_empty', 'css'), 'Call List Suppression has been deleted');

diag("Go to 'Phonebook' page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Phonebook', 'link_text')->click();

diag("Try to create an empty Phonebook entry");
$d->find_element('Create Phonebook Entry', 'link_text')->click();
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Create Phonebook")]'), "Edit window has been opened");
$d->unselect_if_selected('//*[@id="reselleridtable"]//tr[1]/td[5]/input');
$d->find_element('//*[@id="save"]')->click();

diag("Check error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Reseller field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Name field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Number field is required")]'));

diag("Fill in values");
$d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#reselleridtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', $resellername);
ok($d->find_element_by_xpath('//*[@id="reselleridtable"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller found');
$d->select_if_unselected('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input', 'xpath');
$d->fill_element('//*[@id="name"]', 'xpath', $phonebookname);
$d->fill_element('//*[@id="number"]', 'xpath', '0123456789');
$d->find_element('//*[@id="save"]')->click();

diag("Search Phonebook entry");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Phonebook entry successfully created',  'Correct Alert was shown');
$d->fill_element('//*[@id="phonebook_table_filter"]//input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#phonebook_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="phonebook_table_filter"]//input', 'xpath', $phonebookname);

diag("Check details");
ok($d->find_element_by_xpath('//*[@id="phonebook_table"]//tr[1]/td[contains(text(), "' . $phonebookname . '")]'), 'Name is correct');
ok($d->find_element_by_xpath('//*[@id="phonebook_table"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller is correct');
ok($d->find_element_by_xpath('//*[@id="phonebook_table"]//tr[1]/td[contains(text(), "0123456789")]'), 'Number is correct');

diag("Edit Phonebook entry");
$phonebookname = ("phone" . int(rand(100000)) . "book");
$d->move_and_click('//*[@id="phonebook_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="phonebook_table_filter"]//input');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Phonebook")]'), 'Edit window has been opened');
$d->fill_element('//*[@id="name"]', 'xpath', $phonebookname);
$d->fill_element('//*[@id="number"]', 'xpath', '9876543210');
$d->find_element('//*[@id="save"]')->click();

diag("Search Phonebook entry");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Phonebook entry successfully updated',  'Correct Alert was shown');
$d->fill_element('//*[@id="phonebook_table_filter"]//input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#phonebook_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="phonebook_table_filter"]//input', 'xpath', $phonebookname);

diag("Check details");
ok($d->find_element_by_xpath('//*[@id="phonebook_table"]//tr[1]/td[contains(text(), "' . $phonebookname . '")]'), 'Name is correct');
ok($d->find_element_by_xpath('//*[@id="phonebook_table"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller is correct');
ok($d->find_element_by_xpath('//*[@id="phonebook_table"]//tr[1]/td[contains(text(), "9876543210")]'), 'Number is correct');

diag("Try to NOT delete Phonebook entry");
$d->move_and_click('//*[@id="phonebook_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="phonebook_table_filter"]//input');
$d->find_element('//*[@id="dataConfirmCancel"]')->click();
$d->refresh();

diag("Check if Phonebook entry is still here");
$d->fill_element('//*[@id="phonebook_table_filter"]//input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#phonebook_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="phonebook_table_filter"]//input', 'xpath', $phonebookname);
ok($d->find_element_by_xpath('//*[@id="phonebook_table"]//tr[1]/td[contains(text(), "' . $phonebookname . '")]'), 'Phonebook entry is still here');

diag("Try to delete Phonebook entry");
$d->move_and_click('//*[@id="phonebook_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="phonebook_table_filter"]//input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();

diag("Check if Phonebook entry has been deleted");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Phonebook entry successfully deleted',  'Correct Alert was shown');
$d->fill_element('//*[@id="phonebook_table_filter"]//input', 'xpath', $phonebookname);
ok($d->find_element_by_css('#phonebook_table tr > td.dataTables_empty', 'css'), 'Phonebook entry has been deleted');

diag("Go to 'Contacts' page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Contacts', 'link_text')->click();

diag("Try to create an empty Contact");
$d->find_element('Create Contact', 'link_text')->click();
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Create Contact")]'), "Edit window has been opened");
$d->unselect_if_selected('//*[@id="reselleridtable"]//tr[1]/td[5]/input');
$d->find_element('//*[@id="save"]')->click();

diag("Check error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Reseller field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Email field is required")]'));

diag("Fill in values");
$d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#reselleridtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', $resellername);
ok($d->find_element_by_xpath('//*[@id="reselleridtable"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller found');
$d->select_if_unselected('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input', 'xpath');
$d->fill_element('//*[@id="firstname"]', 'xpath', 'Test');
$d->fill_element('//*[@id="lastname"]', 'xpath', 'User');
$d->fill_element('//*[@id="company"]', 'xpath', 'SIPWISE');
$d->fill_element('//*[@id="email"]', 'xpath', $contactmail);
$d->find_element('//*[@id="save"]')->click();

diag("Search Contact");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Contact successfully created',  'Correct Alert was shown');
$d->fill_element('//*[@id="contact_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#contact_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="contact_table_filter"]/label/input', 'xpath', $resellername);

diag("Check details");
ok($d->find_element_by_xpath('//*[@id="contact_table"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller is correct');
ok($d->find_element_by_xpath('//*[@id="contact_table"]//tr[1]/td[contains(text(), "Test")]'), 'First Name is correct');
ok($d->find_element_by_xpath('//*[@id="contact_table"]//tr[1]/td[contains(text(), "User")]'), 'Last Name is correct');
ok($d->find_element_by_xpath('//*[@id="contact_table"]//tr[1]/td[contains(text(), "SIPWISE")]'), 'Company is correct');
ok($d->find_element_by_xpath('//*[@id="contact_table"]//tr[1]/td[contains(text(), "' . $contactmail . '")]'), 'Email is correct');

diag("Edit Contact");
$contactmail = ("contact" . int(rand(100000)) . '@test.org');
$d->move_and_click('//*[@id="contact_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="contact_table_filter"]//input');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Contact")]'), "Edit window has been opened");
$d->fill_element('//*[@id="firstname"]', 'xpath', 'Tester');
$d->fill_element('//*[@id="lastname"]', 'xpath', 'Using');
$d->fill_element('//*[@id="company"]', 'xpath', 'sip');
$d->fill_element('//*[@id="email"]', 'xpath', $contactmail);
$d->fill_element('#company', 'css', 'sip');
$d->fill_element('#street', 'css', 'Europaring');
$d->fill_element('#postcode', 'css', '2345');
$d->fill_element('#city', 'css', 'Brunn/Gebirge');
$d->fill_element('#countryidtable_filter input', 'css', 'thisshouldnotexist');
$d->find_element('#countryidtable tr > td.dataTables_empty', 'css');
$d->fill_element('#countryidtable_filter input', 'css', 'Austria');
$d->select_if_unselected('//table[@id="countryidtable"]/tbody/tr[1]/td[contains(text(),"Austria")]/..//input[@type="checkbox"]');
$d->find_element('//*[@id="save"]')->click();

diag("Search Contact");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Contact successfully changed',  'Correct Alert was shown');
$d->fill_element('//*[@id="contact_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#contact_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="contact_table_filter"]/label/input', 'xpath', $resellername);

diag("Check details");
ok($d->find_element_by_xpath('//*[@id="contact_table"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller is correct');
ok($d->find_element_by_xpath('//*[@id="contact_table"]//tr[1]/td[contains(text(), "Tester")]'), 'First Name is correct');
ok($d->find_element_by_xpath('//*[@id="contact_table"]//tr[1]/td[contains(text(), "Using")]'), 'Last Name is correct');
ok($d->find_element_by_xpath('//*[@id="contact_table"]//tr[1]/td[contains(text(), "sip")]'), 'Company is correct');
ok($d->find_element_by_xpath('//*[@id="contact_table"]//tr[1]/td[contains(text(), "' . $contactmail . '")]'), 'Email is correct');

diag("Try to NOT delete Contact");
$d->move_and_click('//*[@id="contact_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="contact_table_filter"]//input');
$d->find_element('//*[@id="dataConfirmCancel"]')->click();
$d->refresh();

diag("Check if Contact is still here");
$d->fill_element('//*[@id="contact_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#contact_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="contact_table_filter"]/label/input', 'xpath', $resellername);
ok($d->find_element_by_xpath('//*[@id="contact_table"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), "Contact is still here");

diag("Try to delete Contact");
$d->move_and_click('//*[@id="contact_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="contact_table_filter"]//input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();

diag("Check if Contact has been deleted");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Contact successfully deleted',  'Correct Alert was shown');
$d->fill_element('//*[@id="contact_table_filter"]/label/input', 'xpath', $resellername);
ok($d->find_element_by_css('#contact_table tr > td.dataTables_empty', 'css'), 'Contact has been deleted');

diag("Go to 'Security Bans' page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Security Bans', 'link_text')->click();

diag("Try to refresh Banned IPs");
$d->find_element('//*[@id="toggle-accordions"]')->click();
$d->find_element('Refresh banned IPs data', 'link_text')->click();
ok($d->find_element_by_xpath('//*[@id="banned_ips_table_processing"][@style="display: none;"]'), "Processing is done");

diag("Try to refresh banned users");
$d->find_element('Refresh banned users data', 'link_text')->click();
ok($d->find_element_by_xpath('//*[@id="banned_users_table_processing"][@style="display: none;"]'), "Processing is done");

diag("Go to homepage");
$d->find_element('//*[@id="main-nav"]/li[1]/a')->click();

diag("Change language to German");
$d->find_element('//*[@id="top-nav"]/ul/li[3]/a')->click();
$d->find_element('//*[@id="top-nav"]/ul/li[3]//a[@href="?lang=de"]')->click();

diag("Check if language was applied");
#is($d->get_text_safe('//*[@id="masthead"]/div/div/div/h2'), 'Übersicht', "language");
is($d->get_text_safe('//*[@id="admin_billing_overview_lazy_items_header"]/div[1]'), 'Verrechnung', 'was');
is($d->get_text_safe('//*[@id="admin_peering_overview_lazy_items_header"]/div[1]'), 'Peerings', 'changed');
is($d->get_text_safe('//*[@id="admin_reseller_overview_lazy_items_header"]/div[1]'), 'Reseller', 'successfully');

diag("Change language to French");
$d->find_element('//*[@id="top-nav"]/ul/li[3]/a')->click();
$d->find_element('//*[@id="top-nav"]/ul/li[3]//a[@href="?lang=fr"]')->click();

diag("Check if language was applied");
is($d->get_text_safe('//*[@id="masthead"]/div/div/div/h2'), 'Tableau de bord', "language");
is($d->get_text_safe('//*[@id="admin_billing_overview_lazy_items_header"]/div[1]'), 'Facturation', 'was');
#is($d->get_text_safe('//*[@id="admin_peering_overview_lazy_items_header"]/div[1]'), 'Opérateurs', 'changed');
is($d->get_text_safe('//*[@id="admin_reseller_overview_lazy_items_header"]/div[1]'), 'Revendeurs', 'successfully');

diag("Change language to Italian");
$d->find_element('//*[@id="top-nav"]/ul/li[3]/a')->click();
$d->find_element('//*[@id="top-nav"]/ul/li[3]//a[@href="?lang=it"]')->click();

diag("Check if language was applied");
is($d->get_text_safe('//*[@id="masthead"]/div/div/div/h2'), 'Dashboard', "language");
is($d->get_text_safe('//*[@id="admin_billing_overview_lazy_items_header"]/div[1]'), 'Fatturazione', 'was');
is($d->get_text_safe('//*[@id="admin_peering_overview_lazy_items_header"]/div[1]'), 'Peers', 'changed');
is($d->get_text_safe('//*[@id="admin_reseller_overview_lazy_items_header"]/div[1]'), 'Rivenditori', 'successfully');

diag("Change language to Spanish");
$d->find_element('//*[@id="top-nav"]/ul/li[3]/a')->click();
$d->find_element('//*[@id="top-nav"]/ul/li[3]//a[@href="?lang=es"]')->click();

diag("Check if language was applied");
#is($d->get_text_safe('//*[@id="masthead"]/div/div/div/h2'), 'Tablón', "language");
#is($d->get_text_safe('//*[@id="admin_billing_overview_lazy_items_header"]/div[1]'), 'Facturación', 'was');
is($d->get_text_safe('//*[@id="admin_peering_overview_lazy_items_header"]/div[1]'), 'Peerings', 'changed');
is($d->get_text_safe('//*[@id="admin_reseller_overview_lazy_items_header"]/div[1]'), 'Resellers', 'successfully');

=pod
diag("Change language to Russian");
$d->find_element('//*[@id="top-nav"]/ul/li[3]/a')->click();
$d->find_element('//*[@id="top-nav"]/ul/li[3]//a[@href="?lang=ru"]')->click();

diag("Check if language was applied");
is($d->get_text_safe('//*[@id="masthead"]/div/div/div/h2'), 'Главная', "language");
is($d->get_text_safe('//*[@id="admin_billing_overview_lazy_items_header"]/div[1]'), 'Биллинг', 'was');
is($d->get_text_safe('//*[@id="admin_peering_overview_lazy_items_header"]/div[1]'), 'SIP Транк', 'changed');
is($d->get_text_safe('//*[@id="admin_reseller_overview_lazy_items_header"]/div[1]'), 'Реселлеры', 'successfully');
=cut

diag("Change language Back to English");
$d->find_element('//*[@id="top-nav"]/ul/li[3]/a')->click();
$d->find_element('//*[@id="top-nav"]/ul/li[3]//a[@href="?lang=en"]')->click();

$c->delete_domain($domainstring);
$c->delete_reseller_contract($contractid);
$c->delete_reseller($resellername);

diag("Test the Handbook");
$d->find_element('//*[@id="main-nav"]/li[2]/a')->click();
$d->find_element('//*[@id="main-nav"]//li//a[contains(text(), "Handbook")]')->click();

diag("Check if we start at the right page");
ok($d->find_element_by_xpath('/html/body//div//h2/a[@name="_introduction"]'), "We are on the right page");

diag("Change page");
sleep 1; #else the element will get blocked by... itself? (<html>)
$d->find_element('//*[@id="toc-root-item-2"]//a[contains(text(), "Architecture")]')->click();

diag("Check if page was successfully changed");
ok($d->find_element_by_xpath('/html/body//div//h2/a[@name="architecture"]'), "We are on the right page");

diag("This test run was successful");
$run_ok = 1;

END {
    if(!$run_ok) {
        $c->crash_handler("/results/crash_other.png");
    }
    $d->quit();
    done_testing;
}
