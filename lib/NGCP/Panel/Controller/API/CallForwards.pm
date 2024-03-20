package NGCP::Panel::Controller::API::CallForwards;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);


sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

sub api_description {
    return 'Specifies basic callforwards of a subscriber, where a number of destinations, times and sources ' .
           ' can be specified for each type (cfu, cfb, cft, cfna, cfs, cfr, cfo). For more complex configurations with ' .
           ' multiple combinations of Timesets, Destinationsets and SourceSets see <a href="#cfmappings">CFMappings</a>.';
};

sub query_params {
    return [ #TODO
    ];
}

sub documentation_sample {
    return {
        cfb => { "destinations" => [{
                    "destination" => "voicebox",
                    "priority" => "1",
                    "timeout" => "300",
                }],
            "times" => [],
            "sources" => [],
        },
        cfna => {},
        cft => { "ringtimeout" => "199" },
        cfu => {},
        cfs => {},
        cfr => {},
        cfo => {},
    };
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::CallForwards/;

sub resource_name{
    return 'callforwards';
}

sub dispatch_path{
    return '/api/callforwards/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-callforwards';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller ccareadmin ccare subscriberadmin subscriber/],
});

1;

# vim: set tabstop=4 expandtab:
