package NGCP::Panel::Controller::API::TimeSets;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;
use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::TimeSets/;

use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::TimeSet;

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
    backward_allow_empty_upload => 1,
    POST => {
        'ContentType' => ['multipart/form-data','application/json'],
        #'Uploads'     => { 'calendarfile' => [NGCP::Panel::Utils::TimeSet::CALENDAR_MIME_TYPE] },
        #perl -e 'use File::Type; my $ft = File::Type->new();print $ft->mime_type("/root/VMHost/data/test_from_form_1.ics");'
        # =====> application/x-awk 
        'Uploads'     => ['calendarfile'],
    },
});

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines a collection of (generic) Time Sets, which can each specify a number of ' .
    '(recurring) time-slots, which can be currently used in PeeringRules to select certain peerings.';
}

sub query_params {
    return [
        {
            param => 'reseller_id',
            description => 'Filter for Time Sets belonging to a specific reseller',
            query_type => 'string_eq',
        },
        {
            param => 'name',
            description => 'Filter for items by Time Set name',
            query_type => 'wildcard',
        },
    ];
}

sub create_item {
    my ($self, $c, $resource, $form, $process_extras) = @_;

    my $timeset;

    try {
        # no checks, they are in check_resource
        $timeset = NGCP::Panel::Utils::TimeSet::create_timeset(
            c => $c,
            resource => $resource,
        );
    } catch($e) {
        $c->log->error("failed to create timeset: $e");
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create timeset.");
        return;
    }

    return $timeset;
}

1;

# vim: set tabstop=4 expandtab:
