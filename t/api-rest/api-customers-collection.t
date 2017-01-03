use strict;
use warnings;

use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;

#init test_machine
my $test_machine = Test::Collection->new(
    name => 'customers',
);
$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH)};

my $fake_data =  Test::FakeData->new;
$fake_data->set_data_from_script({
    'customers' => {
        'data' => {
            status             => 'active',
            contact_id         => sub { return shift->get_id('customercontacts',@_); },
            billing_profile_id => sub { return shift->get_id('billingprofiles',@_); },
            max_subscribers    => undef,
            external_id        => 'api_test customer'.time(),
            type               => 'pbxaccount',#sipaccount
            'invoice_template_id'          => sub { return shift->get_id('invoicetemplates',@_); },
            'subscriber_email_template_id' => sub { return shift->get_id('emailtemplates',@_); },
            'passreset_email_template_id'  => sub { return shift->get_id('emailtemplates',@_); },
            'invoice_email_template_id'    => sub { return shift->get_id('emailtemplates',@_); },
        },
        'query' => ['external_id'],
        'no_delete_available' => 1,
    },
});

SKIP:{
    my ($res,$req,$content);
    #ew don't have POST fro the invoice templates 
    my $invoicetemplate = $test_machine->get_item_hal('invoicetemplates','/api/invoicetemplates/?name=api_test');

    if(!$invoicetemplate->{total_count} ){
        skip("Testing requires invoice template with name api_test. No creation is available.",1);
    }
    $fake_data->data->{customers}->{data}->{invoice_template_id} = $invoicetemplate->{content}->{id};
    #for item creation test purposes /post request data/
    $test_machine->DATA_ITEM_STORE($fake_data->process('customers'));

    $test_machine->form_data_item( );
    # create 3 new sound sets from DATA_ITEM
    my $customer = $test_machine->check_create_correct( 1, sub{ $_[0]->{external_id} .=  $_[1]->{i}; } )->[0];
    is($customer->{content}->{invoice_template_id}, $invoicetemplate->{content}->{id}, "Check invoice template id of the created customer.");
    for my $template_id (qw/subscriber_email_template_id passreset_email_template_id invoice_email_template_id/){
        is($customer->{content}->{$template_id}, $test_machine->DATA_ITEM->{$template_id}, "Check $template_id of the created customer.");
    }

    $test_machine->check_bundle();
}


#$fake_data->clear_test_data_all();
#$test_machine->clear_test_data_all();
undef $fake_data;
undef $test_machine;

done_testing;

# vim: set tabstop=4 expandtab:
