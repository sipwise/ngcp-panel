package NGCP::Panel::Controller::API::Conversations;

use Sipwise::Base;
#use NGCP::Panel::Utils::Generic qw(:all);
use HTTP::Status qw(:constants);

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::Conversations/;

__PACKAGE__->set_config();

sub config_allowed_roles {
    return [qw/admin reseller subscriberadmin subscriber/];
}

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

sub api_description {
    return 'Combined collection of conversation events (calls, voice mails, sms, faxes, xmpp messages).';
};

sub query_params {
    return [
        {
            param => 'tz',
            description => 'Format timestamp according to the optional time zone provided here, e.g. Europe/Berlin.',
        },
        {
            param => 'use_owner_tz',
            description => 'Format timestamp according to the filtered customer\'s/subscribers\'s inherited time zone.',
        },
        {
            param => 'subscriber_id',
            description => 'Filter for conversation events of a specific subscriber. Either this or customer_id filter is mandatory if called by admin, reseller or subscriberadmin.',
        },
        {
            param => 'customer_id',
            description => 'Filter for conversation events for a specific customer. Either this or subscriber_id filter is mandatory if called by admin, reseller or subscriberadmin.',
        },

        {
            param => 'direction',
            description => 'Filter for conversation events with a specific direction. One of "in", "out". Voicemails are considered as incoming only.',
        },

        {
            param => 'status',
            description => 'todo',
        },

        {
            param => 'type',
            description => 'Filter for conversation events of given types ("call", "voicemail", "sms", "fax", "xmpp"). Multiple types can be included by concatenating type strings, eg. "?type=call-voicemial".',
        },

        {
            param => 'from',
            description => 'Filter for conversation events starting greater or equal the specified time stamp.',
        },
        {
            param => 'to',
            description => 'Filter for conversation events starting lower or equal the specified time stamp.',
        },
        {
            param => 'fax_number_rewrite_mode',
            description => "Force the fax numbers normalization logic to use (available: 'default', 'extended').",
        },

    ];
}

sub order_by_cols {
    my ($self, $c) = @_;
    my $cols = {
        'start_time' => 'timestamp',
        'timestamp' => 'timestamp',
        'type' => 'type',
    };
    return $cols;
}

1;
