package NGCP::Panel::Controller::API::Conversations;

use Sipwise::Base;
#use NGCP::Panel::Utils::Generic qw(:all);
use HTTP::Status qw(:constants);

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::Conversations/;

__PACKAGE__->set_config();

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

sub api_description {
    return 'Combined collection of calls, voice mails, sms and faxes.';
};

sub query_params {
    return [
        {
            param => 'subscriber_id',
            description => 'Filter for calls for a specific subscriber. Either this or customer_id is mandatory if called by admin, reseller or subscriberadmin to filter list down to a specific subscriber in order to properly determine the direction of calls.',
            new_rs => sub {
                #my ($c,$q,$rs) = @_;
                #if ($c->user->roles ne "subscriber") {
                #    my $subscriber = $c->model('DB')->resultset('voip_subscribers')->find($q);
                #    if ($subscriber) {
                #        return SUPER::get_calls_by_uuid_rs($c,$subscriber->uuid);
                #    }
                #}
                #return $rs;
            },
        },
        {
            param => 'customer_id',
            description => 'Filter for calls for a specific customer. Either this or subscriber_id is mandatory if called by admin, reseller or subscriberadmin to filter list down to a specific customer. For calls within the same customer_id, the direction will always be "out".',
            new_rs => sub {
                #my ($c,$q,$rs) = @_;
                #if ($c->user->roles ne "subscriber" and $c->user->roles ne "subscriberadmin" and not exists $c->req->query_params->{subscriber_id}) {
                #    return NGCP::Panel::Utils::CallList::call_list_suppressions_rs($c,$rs->search_rs({
                #            -or => [
                #                'source_account_id' => $q,
                #                'destination_account_id' => $q,
                #            ],
                #        },undef),NGCP::Panel::Utils::CallList::SUPPRESS_INOUT);
                #}
                #return $rs;
            },
        },
        
        
    ];
}

1;

