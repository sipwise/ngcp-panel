use warnings;
use strict;

use lib 't/lib';
use Test::More import => [qw(done_testing is ok diag todo_skip)];
use Selenium::Remote::Driver::FirefoxExtensions;
use Selenium::Collection::Common;

sub ctr_admin() {
    my ($port) = @_;
    $port = '4444' unless $port;

    my $browsername = $ENV{BROWSER_NAME} || "firefox"; # possible values: firefox, htmlunit, chrome

    my $d = Selenium::Remote::Driver::FirefoxExtensions->new(
        browser_name => $browsername,
        extra_capabilities => {
            acceptInsecureCerts => \1,
        },
        port => $port
    );

    my $c = Selenium::Collection::Common->new(
        driver => $d
    );

    my $adminname = ("admin" . int(rand(100000)) . "test");
    my $adminpwd = ("pwd" . int(rand(100000)) . "test");
    my $resellername = ("reseller" . int(rand(100000)) . "test");
    my $contractid = ("contract" . int(rand(100000)) . "test");

    $c->login_ok();
    $c->create_reseller_contract($contractid);
    $c->create_reseller($resellername, $contractid);

    diag('Go to admin interface');
    $d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $d->find_element("Administrators", 'link_text')->click();

    diag('Trying to create a new administrator');
    $d->find_element("Create Administrator", 'link_text')->click();

    diag('Fill in values');
    $d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($d->find_element_by_css('#reselleridtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', $resellername);
    ok($d->wait_for_text('//*[@id="reselleridtable"]/tbody/tr[1]/td[2]', $resellername), "Reseller found");
    $d->select_if_unselected('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input', 'xpath');
    $d->fill_element('//*[@id="login"]', 'xpath', $adminname);
    $d->fill_element('//*[@id="password"]', 'xpath', $adminpwd);
    $d->find_element('//*[@id="save"]')->click();

    diag('Search for our new admin');
    $d->fill_element('//*[@id="administrator_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($d->find_element_by_css('#administrator_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $d->fill_element('//*[@id="administrator_table_filter"]/label/input', 'xpath', $adminname);
    ok($d->wait_for_text('//*[@id="administrator_table"]/tbody/tr[1]/td[3]', $adminname), "Admin found");

    diag('New admin tries to login now');
    $c->login_ok($adminname, $adminpwd);

    diag('Go to admin interface');
    $d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $d->find_element("Administrators", 'link_text')->click();

    diag('Switch over to default admin');
    $c->login_ok();

    diag('Go to admin interface');
    $d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $d->find_element("Administrators", 'link_text')->click();

    diag('Try to delete Administrator');
    $d->fill_element('//*[@id="administrator_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($d->find_element_by_css('#administrator_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $d->fill_element('//*[@id="administrator_table_filter"]/label/input', 'xpath', $adminname);
    ok($d->wait_for_text('//*[@id="administrator_table"]/tbody/tr[1]/td[3]', $adminname), "Admin found");
    $d->move_action(element => $d->find_element('//*[@id="administrator_table"]/tbody/tr[1]/td//a[contains(text(), "Delete")]'));
    $d->find_element('//*[@id="administrator_table"]/tbody/tr[1]/td//a[contains(text(), "Delete")]')->click();
    $d->find_element('//*[@id="dataConfirmOK"]')->click();

    diag('Check if admin is deleted');
    $d->fill_element('//*[@id="administrator_table_filter"]/label/input', 'xpath', $adminname);
    ok($d->find_element_by_css('#administrator_table tr > td.dataTables_empty', 'css'), 'Admin was deleted');

    $c->delete_reseller_contract($contractid);
    $c->delete_reseller($resellername);
}

if(! caller) {
    ctr_admin();
    done_testing;
}

1;

