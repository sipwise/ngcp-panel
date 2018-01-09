package NGCP::Panel::Role::API::BillingZones;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Contract;

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('billing_zones');
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({
                'billing_profile.reseller_id' => $c->user->reseller_id
            }, {
                join => 'billing_profile',
            });
    } else {
        $item_rs = $item_rs->search({
                'billing_profile.reseller_id' => $c->user->contract->contact->reseller_id,
            }, {
                join => 'billing_profile',
            });
    }
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::get("NGCP::Panel::Form::BillingZone::API", $c);
}

sub hal_from_zone {
    my ($self, $c, $zone, $form) = @_;

    my %resource = $zone->get_inflated_columns;

    my $hal = NGCP::Panel::Utils::DataHal->new(
        links => [
            NGCP::Panel::Utils::DataHalLink->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'collection', href => sprintf('/api/%s/', $self->resource_name)),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $zone->id)),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'ngcp:billingprofiles', href => sprintf("/api/billingprofiles/%d", $zone->billing_profile->id)),
            ( map { NGCP::Panel::Utils::DataHalLink->new(relation => 'ngcp:billingfees', href => sprintf("/api/billingfees/%d", $_->id)) } $zone->billing_fees->all ),
            $self->get_journal_relation_link($zone->id),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $form //= $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => \%resource,
        run => 0,
    );

    $resource{id} = int($zone->id);
    $resource{billing_profile_id} = int($zone->billing_profile_id);
    $hal->resource({%resource});
    return $hal;
}

sub zone_by_id {
    my ($self, $c, $id) = @_;

    my $zones = $self->item_rs($c);
    return $zones->find($id);
}

sub update_zone {
    my ($self, $c, $zone, $old_resource, $resource, $form) = @_;

    my $reseller_id;
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $reseller_id = $c->user->reseller_id;
    } else {
        $reseller_id = $c->user->contract->contact->reseller_id;
    }
    $form //= $self->get_form($c);
    # TODO: for some reason, formhandler lets missing profile id
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
    );

    if($old_resource->{billing_profile_id} != $resource->{billing_profile_id}) {
        my $profile = $c->model('DB')->resultset('billing_profiles')
            ->find($resource->{billing_profile_id});
        unless($profile) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'billing_profile_id'");
            return;
        }
        if($c->user->roles ne "admin" && $profile->reseller->id != $reseller_id) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'billing_profile_id'");
            return;
        }
    }

    $zone->update($resource);

    return $zone;
}

1;
# vim: set tabstop=4 expandtab:
