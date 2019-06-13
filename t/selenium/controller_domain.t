use warnings;
use strict;

use lib 't/lib';
use Test::More import => [qw(done_testing is ok diag like)];
use Selenium::Remote::Driver::FirefoxExtensions;
use Selenium::Collection::Common;
use Selenium::Collection::Functions;

sub ctr_domain {
    my ($port) = @_;
    my $d = Selenium::Collection::Functions::create_driver($port);
    my $c = Selenium::Collection::Common->new(
        driver => $d
    );

    my $domainstring = ("domain" . int(rand(100000)) . ".example.org");

    $c->login_ok();
    $c->create_domain($domainstring);

    diag("Check if entry exists and if the search works");
    $d->fill_element('//*[@id="Domain_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($d->find_element_by_css('#Domain_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $d->fill_element('//*[@id="Domain_table_filter"]/label/input', 'xpath', $domainstring);

    diag("Check domain details");
    ok($d->find_element_by_xpath('//*[@id="Domain_table"]/tbody/tr[1]/td[contains(text(), "default")]'), "Reseller is correct");
    ok($d->wait_for_text('//*[@id="Domain_table"]/tbody/tr[1]/td[contains(text(), "domain")]', $domainstring), "Domain name is correct");

    diag("Open Preferences of first Domain");
    $d->move_and_click('//*[@id="Domain_table"]//tr[1]//td//a[contains(text(), "Preferences")]', 'xpath', '//*[@id="Domain_table_filter"]/label/input');

    diag('Open the tab "Access Restrictions"');
    $d->find_element("Access Restrictions", 'link_text')->click();

    diag("Click edit for the preference concurrent_max");
    $d->move_and_click('//table//tr/td[contains(text(), "concurrent_max")]/../td//a[contains(text(), "Edit")]', 'xpath', '//table//tr/td[contains(text(), "reject_emergency")]');
	
    diag("Try to change this to a value which is not a number");
    $d->fill_element('#concurrent_max', 'css', 'thisisnonumber');
    $d->find_element("#save", 'css')->click();

    diag('Type 789 and click Save');
    ok($d->find_text('Value must be an integer'), 'Wrong value detected');
    $d->fill_element('#concurrent_max', 'css', '789');
    $d->find_element('#save', 'css')->click();

    diag('Check if value has been applied');
    ok($d->find_element_by_xpath('//table/tbody/tr/td[contains(text(), "concurrent_max")]/../td[contains(text(), "789")]'), "Value has been applied");

    diag("Click edit for the preference allowed_ips");
    $d->move_and_click('//table/tbody/tr/td[contains(text(), "allowed_ips")]/../td/div/a[contains(text(), "Edit")]', 'xpath', '//table/tbody/tr/td[contains(text(), "man_allowed_ips")]/../td/div/a[contains(text(), "Edit")]');

    diag("Enter an IP address");
    $d->fill_element('//*[@id="allowed_ips"]', 'xpath', '127.0.0.0.0');
    $d->find_element('//*[@id="add"]')->click();
    ok($d->find_element_by_xpath('//*[@id="mod_edit"]//div//span[contains(text(), "Invalid IPv4 or IPv6 address")]'), "Invalid IP address detected");
    $d->fill_element('//*[@id="allowed_ips"]', 'xpath', '127.0.0.1');
    $d->find_element('//*[@id="add"]')->click();
    $d->find_element('//*[@id="mod_close"]')->click();

    diag("Check if IP address has been added");
    ok($d->find_element_by_xpath('//table/tbody/tr/td[contains(text(), "allowed_ips")]/../td[contains(text(), "127.0.0.1")]'), "IP address has beeen found");

    diag("Enable transcoding to Opus Mono and Stereo");
    $d->scroll_to_element($d->find_element('Media Codec Transcoding Options', 'link_text'));
    $d->find_element('Media Codec Transcoding Options', 'link_text')->click();

    diag("Enable Opus Mono");
    $d->scroll_to_element($d->find_element('//table//tr/td[contains(text(), "transcode_opus_mono")]'));
    $d->move_and_click('//table//tr/td[contains(text(), "transcode_opus_mono")]/../td//a[contains(text(), "Edit")]', 'xpath', '//table//tr/td[contains(text(), "transcode_opus_stereo")]');
    $d->select_if_unselected('//*[@id="transcode_opus_mono"]');
    $d->find_element('//*[@id="save"]')->click();

    diag("Check if Opus Mono was enabled");
    ok($d->find_element_by_xpath('//table//tr/td[contains(text(), "transcode_opus_mono")]/../td//input[@checked="checked"]'), "Opus mono was enabled");

    diag("Change Opus Mono Bitrate");
    $d->scroll_to_element($d->find_element('//table//tr/td[contains(text(), "transcode_opus_mono")]'));
    $d->move_and_click('//table//tr/td[contains(text(), "opus_mono_bitrate")]/../td//a[contains(text(), "Edit")]', 'xpath', '//table//tr/td[contains(text(), "opus_stereo_bitrate")]');

    diag("Change to 32 kbit/s");
    $d->find_element('//*[@id="opus_mono_bitrate"]/option[contains(text(), "32")]')->click();
    $d->find_element('//*[@id="save"]')->click();

    diag("Check if Bitrate was applied");
    ok($d->find_element_by_xpath('//table//tr/td[contains(text(), "opus_mono_bitrate")]/../td/select/option[text()[contains(., "32")]][@selected="selected"]'), "Correct bitrate was selected");

    diag("Enable Opus Stereo");
    $d->scroll_to_element($d->find_element('//table//tr/td[contains(text(), "transcode_opus_stereo")]'));
    $d->move_and_click('//table//tr/td[contains(text(), "transcode_opus_stereo")]/../td//a[contains(text(), "Edit")]', 'xpath', '//table//tr/td[contains(text(), "transcode_opus_mono")]');
    $d->select_if_unselected('//*[@id="transcode_opus_stereo"]');
    $d->find_element('//*[@id="save"]')->click();

    diag("Check if Opus Stereo was enabled");
    ok($d->find_element_by_xpath('//table//tr/td[contains(text(), "transcode_opus_stereo")]/../td//input[@checked="checked"]'), "Opus stereo was enabled");

    diag("Change Opus Stereo Bitrate");
    $d->scroll_to_element($d->find_element('//table//tr/td[contains(text(), "transcode_opus_stereo")]'));
    $d->move_and_click('//table//tr/td[contains(text(), "opus_stereo_bitrate")]/../td//a[contains(text(), "Edit")]', 'xpath', '//table//tr/td[contains(text(), "opus_mono_bitrate")]');

    diag("Change to 32 kbit/s");
    $d->find_element('//*[@id="opus_stereo_bitrate"]/option[contains(text(), "32")]')->click();
    $d->find_element('//*[@id="save"]')->click();

    diag("Check if Bitrate was applied");
    ok($d->find_element_by_xpath('//table//tr/td[contains(text(), "opus_stereo_bitrate")]/../td/select/option[text()[contains(., "32")]][@selected="selected"]'), "Correct bitrate was selected");

    diag("Open delete dialog and press cancel");
    $c->delete_domain($domainstring, 1);
    $d->fill_element('//*[@id="Domain_table_filter"]/label/input', 'xpath', $domainstring);
    ok($d->wait_for_text('//*[@id="Domain_table"]/tbody/tr[1]/td[3]', $domainstring), 'Domain is still here');

    diag('Open delete dialog and press delete');
    $c->delete_domain($domainstring, 0);
    $d->fill_element('//*[@id="Domain_table_filter"]/label/input', 'xpath', $domainstring);
    ok($d->find_element_by_css('#Domain_table tr > td.dataTables_empty', 'css'), 'Domain was deleted');
}

if(! caller) {
    ctr_domain();
    done_testing;
}

1;