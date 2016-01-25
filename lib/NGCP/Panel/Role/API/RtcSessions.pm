package NGCP::Panel::Role::API::RtcSessions;
use NGCP::Panel::Utils::Generic qw(:all);
use Moose::Role;
with 'NGCP::Panel::Role::API' => {
    -alias       =>{ item_rs  => '_item_rs', },
    -excludes    => [ 'item_rs' ],
};

use boolean qw(true);
use TryCatch;
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use JSON::Types;

use NGCP::Panel::Utils::Subscriber;
use NGCP::Panel::Utils::Rtc;

sub get_form {
    my ($self) = @_;

    #return NGCP::Panel::Form::Rtc::NetworksAdmin->new;
    return;
}

sub hal_from_item {
    my ($self, $c, $item) = @_;

    my $resource = { 
            subscriber_id => $item->subscriber->voip_subscriber->id,  # this may be confusing but we store the provisioning-subscriber-id but show the billing one
            rtc_network_tag => $item->rtc_network_tag,
        };

    my $rtc_session = NGCP::Panel::Utils::Rtc::get_rtc_session(
        config => $c->config,
        item => $item,
        err_code => sub {
            $c->log->warn(shift); return;
        });
    if ($rtc_session) {
        $resource->{rtc_browser_token} = $rtc_session->{data}{token};
    } else {
        # here either delete our DB entry, or recreate it accordingly
    }

    my $hal = Data::HAL->new(
        links => [
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'collection', href => sprintf("/api/%s/", $self->resource_name)),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            Data::HAL::Link->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $item->id)),
            Data::HAL::Link->new(relation => 'ngcp:subscribers', href => sprintf("/api/subscribers/%d", $item->subscriber->voip_subscriber->id)),
            $self->get_journal_relation_link($item->id),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $hal->resource($resource);
    return $hal;
}

sub item_rs {
    my ($self, $c) = @_;

    my $item_rs;
    $item_rs = $c->model('DB')->resultset('rtc_session');
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({
            'contact.reseller_id' => $c->user->reseller_id,
        },{
            join => {subscriber => { voip_subscriber => { contract => 'contact' }}},
        });
    }

    return $item_rs;
}

sub item_by_id {
    my ($self, $c, $id) = @_;

    my $item_rs = $self->item_rs($c);
    return $item_rs->find($id);
}

sub update_item {  # TODO: not yet implemented
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    # my $reseller = $item;

    # if (ref $resource->{networks} ne "ARRAY") {
    #     $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid field 'networks'. Must be an array.");
    #     return;
    # }

    # $form //= $self->get_form($c);
    # return unless $self->validate_form(
    #     c => $c,
    #     form => $form,
    #     resource => $resource,
    # );

    # NGCP::Panel::Utils::Rtc::modify_rtc_networks(
    #     old_resource => $old_resource,
    #     resource => $resource,
    #     config => $c->config,
    #     reseller_item => $reseller,
    #     err_code => sub {
    #         $c->log->warn(shift); return;
    #     });

    # try {

    # } catch($e) {
    #     $c->log->error("failed to update autoattendants: $e");
    #     $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to update autoattendants.");
    #     return;
    # };

    # return $reseller;
}

1;
# vim: set tabstop=4 expandtab:
