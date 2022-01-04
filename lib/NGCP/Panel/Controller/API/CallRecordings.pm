package NGCP::Panel::Controller::API::CallRecordings;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::CallRecordings/;

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller subscriberadmin subscriber/],
});

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

sub api_description {
    return 'Defines calls being recorded on the system. The recorded streams belonging to a recorded call can be found in <a href="#callrecordingstreams">CallRecordingStreams</a>.';
};

sub query_params {
    return [
        {
            param => 'reseller_id',
            description => 'Filter for callrecordings belonging to a specific reseller',
            query_type => 'string_eq',
        },
        {
            param => 'status',
            description => 'Filter for callrecordings with a specific status',
            query_type => 'string_eq',
        },
        {
            # we handle that separately/manually in the role
            param => 'subscriber_id',
            description => 'Filter for callrecordings where the subscriber with the given id is involved.',
        },
        {
            # we handle that separately/manually in the role
            param => 'tz',
            description => 'Format start_time according to the optional time zone provided here, e.g. Europe/Berlin.',
        },
        {
            param => 'force_delete',
            type  => 'item_params',
            apply_to  => {'item' => {DELETE => 1}},
            description => 'Force callrecording info deletion from database despite callrecording files deletion errors.',
        },
        {
            param => 'call_id',
            description => 'Filter for callrecordings belonging to a specific call',
            query => {
                first => sub {
                    my $q = shift;
                    { 'me.call_id' => $q };
                }
            },
        },
        {
            param => 'caller',
            description => 'Filter by the caller number',
            query => {
                first => sub {
                    my $q = shift;
                    {
                       'recording_metakeys.key' => 'caller',
                       'recording_metakeys.value' => $q,
                    };
                }
            },
        },
        {
            param => 'callee',
            description => 'Filter by the callee number',
            query => {
                first => sub {
                    my $q = shift;
                    {
                       'recording_metakeys.key' => 'callee',
                       'recording_metakeys.value' => $q,
                    };
                }
            },
        },
        {
            param => 'start_time',
            description => 'Filter for callrecordings made at a later date than provided datetime.',
            query => {
                first => sub {
                    my $q = shift;
                    if ($q) {
                        my $dt = NGCP::Panel::Utils::DateTime::from_string($q);
                        return { 'me.start_timestamp' => { '>=' => $dt->epoch } };
                    }
                    return {};
                },
                second => sub {},
            },
        },
        {
            param => 'end_time',
            description => 'Filter for callrecordings made at an earlier date than provided datetime.',
            query => {
                first => sub {
                    my $q = shift;
                    if ($q) {
                        my $dt = NGCP::Panel::Utils::DateTime::from_string($q);
                        return { 'me.end_timestamp' => { '<=' => $dt->epoch } };
                    }
                    return {};
                },
                second => sub {},
            },
        },
    ];
}

1;

# vim: set tabstop=4 expandtab:
