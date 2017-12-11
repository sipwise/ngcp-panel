use strict;
use warnings;

use Test::More;
use Test::Collection;
use Test::FakeData;
use Data::Dumper;

use File::Slurp qw/write_file/;
use IPC::Run3;
use Cwd;
use Log::Log4perl qw/get_logger :levels/;
use Clone qw/clone/;

diag('Note that the next tests require at least one sip account customer,subscriber,call,fax,voicemail,sms,xmpp to be present');

my $AMOUNT_SUBSCRIBERS = 5;
my $AMOUNT_CALLS = 5;
my $AMOUNT_SMS = 5;
my $AMOUNT_FAX = 5;
my $AMOUNT_VOICEMAILS = 5;
my $AMOUNT_XMPP = 5;

my $opt = {};
$opt->{sipp_dir} = '/root/VMHost/data/sipp_toolkit/';
$opt->{target_host} = '127.0.0.1';

my $test_machine = Test::Collection->new(
    name => 'conversations',
);
#init test_machine
my $fake_data = Test::FakeData->new;
$fake_data->set_data_from_script({
    'conversations' => {
        'data' => {
            username_format            => 'sub_%04d',
            username_format_caller     => 'sub_caller_%04d',
            username_format_callee     => 'sub_callee_%04d',
            display_name_format        => 'sub %04d',
            display_name_format_caller => 'sub caller %04d',
            display_name_format_callee => 'sub callee %04d',
            password_format            => 'sub_pwd_%04d',
            #we repeate it intentionally, to somplify logic
            password_format_caller     => 'sub_pwd_%04d',
            password_format_callee     => 'sub_pwd_%04d',
            number => undef,
            subscriber_template => {
                customer_id => sub { return shift->get_id('customer_sipaccount',@_); },
                domain => 'voip.sip',
                administrative  => undef,
                primary_number => {
                    ac => '1',
                    cc => '1',
                    sn => time(),
                },
                status => 'active',
                username => undef,
                password => undef,
                display_name => undef,
            },
        },
    },
});
my $FAKE_DATA_INIT = $fake_data->build_data;
my $FAKE_DATA_PROCESSED = $fake_data->process('conversations');


my ($domain,$customer,$contact,$subscribers,$callers,$callees,$amount);

SKIP:
{ #MT#16171
    my ($res,$content,$collection);

    if(!defined $FAKE_DATA_PROCESSED->{subscriber_template}->{domain}){
        skip("Precondition not met: need a domain",1);
    }
    $customer = $test_machine->get_item_hal('customers','/api/customers/'.$FAKE_DATA_PROCESSED->{subscriber_template}->{customer_id});
    if(!$customer->{total_count}){
        skip("Precondition not met: Customer not found", 1);
    }
    $contact = $test_machine->get_item_hal('customercontacts','/api/customercontacts/'.$customer->{content}->{contact_id});
    if(!$contact->{total_count}){
        skip("Precondition not met: Customer contact not found", 1);
    }
    $domain = $test_machine->get_item_hal('domains','/api/domains/?domain='.$FAKE_DATA_PROCESSED->{subscriber_template}->{domain});
    if(!$domain->{total_count}){
        skip("Precondition not met: Domain not found", 1);
    }
    if($contact->{content}->{reseller_id} != $domain->{content}->{reseller_id}){
        skip("Precondition not met: Domain should belong to the reseller_id = ".$customer->{content}->{reseller_id}, 1);
    }
    $test_machine->name('subscribers');
    my $type_i = 1;
    foreach my $type (qw/caller callee/){
        my $type_suffix = '_'.$type;
        $subscribers->{$type} //= [];
        my $found = 0;
        for(my $i = 1; $i <= $AMOUNT_SUBSCRIBERS; $i++){
            my $subscriber = $test_machine->get_item_hal('subscribers','/api/subscribers/?username='.sprintf( $FAKE_DATA_PROCESSED->{'username_format'.$type_suffix}, $i ));
            if(!$subscriber->{total_count}){
                $subscriber = $test_machine->check_create_correct( 1, sub{
                    my $num = $i;
                    $_[0] = clone $FAKE_DATA_PROCESSED->{subscriber_template};
                    $_[0]->{primary_number}->{sn} .= $num.$type_i;
                    foreach my $field(qw/username password display_name/){
                        $_[0]->{$field} = sprintf( $FAKE_DATA_PROCESSED->{$field.'_format'.$type_suffix}, $num );
                    }
                } )->[0];
            }
            push @{$subscribers->{$type}}, $subscriber->{content};
        }
        $type_i++;
    }
    print Dumper [map { map { $_->{content}} @{$subscribers->{$_}} } qw/caller callee/ ];
    #register two ip's as for the real phones here subscribers are registered.
    #according tto the 
    
    for (my $i_item=0; $i_item < $AMOUNT_SUBSCRIBERS; $i_item++){
        print Dumper $subscribers->{caller}->[$i_item];
        my $cmd = "perl /root/VMHost/ngcp-panel/sandbox/conversations_data/sip.pl $AMOUNT_CALLS 127.0.0.1 5060 0 @{$subscribers->{caller}->[$i_item]}{qw/domain username password/} 0 @{$subscribers->{callee}->[$i_item]}{qw/domain username password/} ";
        print $cmd."\n";
        `$cmd`;
    }
}


done_testing;



# vim: set tabstop=4 expandtab:
