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
        },
        {
            param => 'customer_id',
            description => 'Filter for calls for a specific customer. Either this or subscriber_id is mandatory if called by admin, reseller or subscriberadmin to filter list down to a specific customer. For calls within the same customer_id, the direction will always be "out".',
        },
        
        {
            param => 'direction',
            description => 'Filter for calls starting greater or equal the specified time stamp.',
        },         
        
        {
            param => 'status',
            description => 'Filter for calls starting greater or equal the specified time stamp.',
        }, 
        
        {
            param => 'type',
            description => 'Filter for calls starting greater or equal the specified time stamp.',
        },        
        
        {
            param => 'from',
            description => 'Filter for calls starting greater or equal the specified time stamp.',
        },
        {
            param => 'to',
            description => 'Filter for calls starting lower or equal the specified time stamp.',
        },
        
    ];
}

sub order_by_cols {
    return {
        'timestamp' => 'me.timestamp',
        'type' => 'me.type',
    };
}

1;

