package NGCP::Panel::Role::API::RtcApps;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';
use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Status qw(:constants);
use JSON::Types;

use NGCP::Panel::Form::Rtc::AppsAdmin;
use NGCP::Panel::Utils::Subscriber;
use NGCP::Panel::Utils::Rtc;

sub get_form {
    my ($self, $c) = @_;

    return NGCP::Panel::Form::Rtc::AppsAdmin->new;
}

sub hal_from_item {
    my ($self, $c, $item, $include_id) = @_;

    my $resource = { reseller_id => $item->id};
    if ($item->rtc_user) {
        my $rtc_user_id = $item->rtc_user->rtc_user_id;
        $resource->{rtc_user_id} = $rtc_user_id if $include_id;
        $resource->{apps} = NGCP::Panel::Utils::Rtc::get_rtc_apps(
            rtc_user_id => $rtc_user_id,
            config => $c->config,
            include_id => $include_id,
            err_code => sub {
                $c->log->warn(shift); return;
            });
    } else {
    }

    my $hal = NGCP::Panel::Utils::DataHal->new(
        links => [
            NGCP::Panel::Utils::DataHalLink->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'collection', href => sprintf("/api/%s/", $self->resource_name)),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $item->id)),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'ngcp:resellers', href => sprintf("/api/resellers/%d", $item->id)),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'ngcp:resellers', href => sprintf("/api/rtcnetworks/%d", $item->id)),
            $self->get_journal_relation_link($item->id),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    my $form = $self->get_form($c);
    unless ($include_id) {
        return unless $self->validate_form(
            c => $c,
            form => $form,
            resource => $resource,
            run => 0,
            exceptions => ['rtc_user_id'],
        );
    }

    $hal->resource($resource);
    return $hal;
}

sub _item_rs {
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

    if (ref $resource->{apps} ne "ARRAY") {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid field 'apps'. Must be an array.");
        return;
    }

    $form //= $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
    );

    NGCP::Panel::Utils::Rtc::modify_rtc_apps(
        old_resource => $old_resource,
        resource => $resource,
        config => $c->config,
        reseller_item => $reseller,
        err_code => sub {
            $c->log->warn(shift); return;
        });

    try {

    } catch($e) {
        $c->log->error("failed to update rtcapps: $e");
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to update rtcapps.");
        return;
    };

    return $reseller;
}

1;
# vim: set tabstop=4 expandtab:
