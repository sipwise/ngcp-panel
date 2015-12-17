package NGCP::Panel::Role::API::RtcNetworks;
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
    my ($self, $c) = @_;

    #return NGCP::Panel::Form::Subscriber::AutoAttendantAPI->new;
    return;
}

sub hal_from_item {
    my ($self, $c, $item) = @_;

    my $resource = { reseller_id => $item->id};
    if ($item->rtc_user) {
        my $rtc_user_id = $item->rtc_user->rtc_user_id;
        $resource->{rtc_user_id} = $rtc_user_id; # tmp: remove
        $resource->{networks} = NGCP::Panel::Utils::Rtc::get_rtc_networks($rtc_user_id, $c->config, undef, sub {
                $c->log->warn(shift); return;
            });
    } else {
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
            Data::HAL::Link->new(relation => 'ngcp:autoattendants', href => sprintf("/api/autoattendants/%d", $item->id)),
            Data::HAL::Link->new(relation => 'ngcp:subscribers', href => sprintf("/api/subscribers/%d", $item->id)),
            $self->get_journal_relation_link($item->id),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    my $form = $self->get_form($c);
    # return unless $self->validate_form(
    #     c => $c,
    #     form => $form,
    #     resource => $resource,
    #     run => 0,
    #     exceptions => ['subscriber_id'],
    # );

    $hal->resource($resource);
    return $hal;
}

sub item_rs {
    my ($self, $c) = @_;

    my $item_rs;
    $item_rs = $c->model('DB')->resultset('resellers')
        ->search_rs(undef, {
                prefetch => 'rtc_user',
            });
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({
            id => $c->user->reseller_id,
        });
    }

    return $item_rs;
}

sub item_by_id {
    my ($self, $c, $id) = @_;

    my $item_rs = $self->item_rs($c);
    return $item_rs->find($id);
}

sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    my $reseller = $item;

    if (ref $resource->{networks} ne "ARRAY") {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid field 'networks'. Must be an array.");
        return;
    }

    # $form //= $self->get_form($c);
    # return unless $self->validate_form(
    #     c => $c,
    #     form => $form,
    #     resource => $resource,
    # );

    NGCP::Panel::Utils::Rtc::modify_rtc_networks($old_resource, $resource, $c->config,
        $reseller, sub {
            $c->log->warn(shift); return;
        });

    try {

    } catch($e) {
        $c->log->error("failed to update autoattendants: $e");
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to update autoattendants.");
        return;
    };

    return $reseller;
}

1;
# vim: set tabstop=4 expandtab:
