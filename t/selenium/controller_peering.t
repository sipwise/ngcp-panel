use warnings;
use strict;

use lib 't/lib';
use Test::More import => [qw(done_testing is ok diag todo_skip)];
use Selenium::Remote::Driver::FirefoxExtensions;

my $browsername = $ENV{BROWSER_NAME} || "firefox"; # possible values: firefox, htmlunit, chrome

my $d = Selenium::Remote::Driver::FirefoxExtensions->new(
    browser_name => $browsername,
    extra_capabilities => {
        acceptInsecureCerts => \1,
    },
);

$d->login_ok();

diag("Go to Peerings page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element("Peerings", 'link_text')->click();
sleep 1;

$d->find_element('//*[@id="sip_peering_group_table_length"]/label/select')->click();
$d->find_element('//*[@id="sip_peering_group_table_length"]/label/select/option[2]')->click();
sleep 3;
done_testing;
# vim: filetype=perl

