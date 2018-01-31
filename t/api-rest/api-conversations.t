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
use JSON;
use Cwd 'abs_path';
use File::Basename;

diag('Note that the next tests require at least one sip account customer,subscriber,call,fax,voicemail,sms,xmpp to be present');

my $SERVER = {
    CALLS => '192.168.1.118',
    XMPP  => '192.168.1.118',
    FAX   => '127.0.0.1',#dummy for now, not used in the executor
    SMS   => '127.0.0.1',#dummy for now, not used in the executor
};
my $AMOUNT = {
    SUBSCRIBERS => 1,#so there will be x2 subscribers - N caller and N callee
    CALLS       => 0,
    SMS         => 1,
    FAX         => 1,
    VOICEMAILS  => 1,
    XMPP        => 1,
};


my $test_machine = Test::Collection->new(
    name => 'conversations',
);
#init test_machine
my $fake_data = Test::FakeData->new;
$fake_data->set_data_from_script({
    'conversations' => {
        'data' => {
            username_format            => 'sub1_%04d',
            username_format_caller     => 'sub1_caller_%04d',
            username_format_callee     => 'sub1_callee_%04d',
            display_name_format        => 'sub1 %04d',
            display_name_format_caller => 'sub1 caller %04d',
            display_name_format_callee => 'sub1 callee %04d',
            password_format            => 'sub_pwd_%04d',
            #we repeate it intentionally, to somplify logic
            password_format_caller     => 'sub_pwd_%04d',
            password_format_callee     => 'sub_pwd_%04d',
            subscriber_template => {
                customer_id => sub { return shift->get_id('customer_sipaccount',@_); },
                domain => '192.168.1.118',
                administrative  => 0,
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


my ($domain,$customer,$contact,$subscribers);

SKIP:
{ #MT#16171

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
}
{#prepare subscribers
    $test_machine->name('subscribers');
    my $type_i = 1;
    foreach my $type (qw/caller callee/){
        my $type_suffix = '_'.$type;
        $subscribers->{$type} //= [];
        my $found = 0;
        for(my $i = 1; $i <= $AMOUNT->{SUBSCRIBERS}; $i++){
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
            my $preferences = {'uri' => '/api/subscriberpreferences/'.$subscriber->{content}->{id}};
            (undef, $preferences->{content}) = $test_machine->request_patch([ { op => 'add', path => '/allow_out_foreign_domain', value => JSON::true } ] ,$preferences->{uri});
            push @{$subscribers->{$type}}, $subscriber->{content};
        }
        $type_i++;
    }
}
{#generate
    for (my $i_item=0; $i_item < $AMOUNT->{SUBSCRIBERS}; $i_item++){
        my $caller = $subscribers->{caller}->[$i_item];
        my $callee = $subscribers->{callee}->[$i_item];
        my $cmd_full;
        my $cmd = 'perl '.dirname(abs_path($0)).'/resources/executor.pl';
        if($AMOUNT->{CALLS}){
            $cmd_full = "$cmd call $AMOUNT->{CALLS} $SERVER->{CALLS} 5060 0 @{$caller}{qw/domain username password/} 0 @{$callee}{qw/domain username password/} ";
            print $cmd_full."\n";
            `$cmd_full`;
        }
        if($AMOUNT->{VOICEMAILS}){
            $test_machine->request_patch([ { 
                'op' => 'add', 
                'path' => '/cfu', 
                'value' => {
                    'destinations' => [
                        { 'destination' => 'voicebox', 'timeout' => 200},
                    ],
                    'times' => undef,
                },
            } ] ,'/api/callforwards/'.$callee->{id});

            $cmd_full = "$cmd voicemail $AMOUNT->{VOICEMAILS} $SERVER->{CALLS} 5060 0 @{$caller}{qw/domain username password/} 0 @{$callee}{qw/domain username password/} ";
            print $cmd_full."\n";
            `$cmd_full`;
            $test_machine->request_patch([ { 
                'op' => 'remove', 
                'path' => '/cfu', 
            } ] ,'/api/callforwards/'.$callee->{id});
        }
        if($AMOUNT->{XMPP}){
            $cmd_full = "$cmd xmpp $AMOUNT->{XMPP} $SERVER->{XMPP} 5222 0 @{$caller}{qw/domain username password/} 0 @{$callee}{qw/domain username password/} ";
            print $cmd_full."\n";
            `$cmd_full`;
        }
        if($AMOUNT->{SMS}){
            $cmd_full = "$cmd sms $AMOUNT->{SMS} $SERVER->{SMS} 1443 0 @{$caller}{qw/domain username password/} 0 @{$callee}{qw/domain username password/} ";
            print $cmd_full."\n";
            `$cmd_full`;
        }
        if($AMOUNT->{FAX}){
            my $test_machine_aux = Test::Collection->new(name => 'faxserversettings');
            foreach my $type_l (qw/caller callee/){
                my $uri = $test_machine_aux->get_uri($subscribers->{$type_l}->[$i_item]->{id});
                my($res,$faxserversettings,$req) = $test_machine_aux->check_item_get($uri);
                $faxserversettings->{active} = 1;
                $faxserversettings->{password} = 'aaa111';
                $test_machine_aux->request_put($faxserversettings,$uri);    
            }
            $cmd_full = "$cmd fax $AMOUNT->{FAX} $SERVER->{FAX} 1443 0 @{$caller}{qw/domain username password/} 0 @{$callee}{qw/domain username password/} ";
            print $cmd_full."\n";
            `$cmd_full`;
        }

    }
}

done_testing;

# vim: set tabstop=4 expandtab:
