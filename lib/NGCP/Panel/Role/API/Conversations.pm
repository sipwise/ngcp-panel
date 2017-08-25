package NGCP::Panel::Role::API::Conversations;

use parent qw/NGCP::Panel::Role::API/;

use Sipwise::Base;
#use NGCP::Panel::Utils::Generic qw(:all);
use NGCP::Panel::Utils::CallList qw();

use HTTP::Status qw(:constants);
use NGCP::Panel::Form::Conversation::API;

sub item_name{
    return 'conversation';
}

sub resource_name{
    return 'conversations';
}

sub dispatch_path{
    return '/api/conversations/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-conversations';
}

sub config_allowed_roles {
    return [qw/admin reseller subscriberadmin subscriber/];
}

sub _item_rs {
    my ($self, $c) = @_;
    
    my ($uuid,$contract_id,$reseller_id,$provider_id);
    #$uuid = ...;
    #$contract_id = ...;
    if ($c->user->roles eq "subscriber") {
        $uuid = $c->user->voip_subscriber->uuid;
    } elsif ($c->user->roles eq "subscriberadmin") {
        $contract_id = $c->user->account_id;
    } elsif ($c->user->roles eq "reseller") {
        $reseller_id = $c->user->reseller_id;
        $provider_id = $c->user->reseller->contract_id;
    }

    my $item_rs;
    if (1) {
        my $rs = $self->get_calls_rs($c,$uuid,$contract_id,$provider_id);
        $rs->result_class('DBIx::Class::ResultClass::HashRefInflator');
        $item_rs = (defined $item_rs ? $item_rs->union_all($rs) : $rs);
    }
    
    if (1) {
        my $rs = $self->get_voicemails_rs($c,$uuid,$contract_id,$reseller_id);
        $rs->result_class('DBIx::Class::ResultClass::HashRefInflator');
        $item_rs = (defined $item_rs ? $item_rs->union_all($rs) : $rs);
    }
    
    return $item_rs;
    
    
}

sub get_calls_rs {
    
    my ($self,$c,$uuid,$contract_id,$provider_id) = @_;
    my $rs = $c->model('DB')->resultset('cdr');
    if ($provider_id) {
        $rs = $rs->search({
            -or => [
                { source_provider_id => $provider_id },
                { destination_provider_id => $provider_id },
            ],
        });        
    }
    if ($contract_id) {
        $rs = $rs->search_rs({
            -or => [
                { source_account_id => $contract_id },
                { destination_account_id => $contract_id },
            ],
        });    
    }
    if ($uuid) {
        my $out_rs = NGCP::Panel::Utils::CallList::call_list_suppressions_rs($c,$rs->search_rs({
            source_user_id => $uuid,
        }),NGCP::Panel::Utils::CallList::SUPPRESS_OUT);
        my $in_rs = NGCP::Panel::Utils::CallList::call_list_suppressions_rs($c,$rs->search_rs({
            destination_user_id => $uuid,
        }),NGCP::Panel::Utils::CallList::SUPPRESS_IN);
        $rs = $out_rs->union_all($in_rs);
    } else {
        $rs = NGCP::Panel::Utils::CallList::call_list_suppressions_rs($c,$rs,NGCP::Panel::Utils::CallList::SUPPRESS_INOUT);
    }
    return $rs->search(undef,{
        select => [
              { '' => \'"call"', -as => 'type' },
              { '' => 'me.id', -as => 'id' },              
            ],
        as => ['type','id'],
    });
       
}

sub get_voicemails_rs {
    
    my ($self,$c,$uuid,$contract_id,$reseller_id) = @_;

    my $rs = $c->model('DB')->resultset('voicemail_spool')->search({
        duration => { '!=' => '' },
    });
    if ($reseller_id) {
        $rs = $rs->search({
            'contact.reseller_id' => $reseller_id,
        },{
            join => { mailboxuser => { provisioning_voip_subscriber => { voip_subscriber => { contract => 'contact' } } } },
        });    
    }
    if ($contract_id) {
        $rs = $rs->search({
            'contract.id' => $contract_id,
        },{
            join => { mailboxuser => { provisioning_voip_subscriber => { voip_subscriber => 'contract' } } },
        }); 
    }
    if ($uuid) {
        $rs = $rs->search({
            'voip_subscriber.uuid' => $c->user->uuid,
        },{
            join => { mailboxuser => { provisioning_voip_subscriber => 'voip_subscriber' } },
        });
    } else {
        $rs = $rs->search({
            'voip_subscriber.id' => { '!=' => undef },
        },{
            join => { mailboxuser => { provisioning_voip_subscriber => 'voip_subscriber' } },
        });        
    }
    return $rs->search(undef,{
        select => [
              { '' => \'"voicemail"', -as => 'type' },
              { '' => 'me.id', -as => 'id' },              
            ],
        as => ['type','id'],
    });
    
}

sub get_form {
    my ($self, $c) = @_;
    return (NGCP::Panel::Form::Conversation::API->new(ctx => $c),['customer_id','template_id']);
}

sub hal_links {
    my($self, $c, $item, $resource, $form) = @_;
    return [
        #NGCP::Panel::Utils::DataHalLink->new(relation => 'ngcp:customers', href => sprintf("/api/customers/%d", $item->contract_id)),
    ];
}

1;
# vim: set tabstop=4 expandtab:
