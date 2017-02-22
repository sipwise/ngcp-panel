package NGCP::Panel::Role::API::BillingFees;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Contract;
use NGCP::Panel::Form::BillingFee::API;

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('billing_fees');
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
    return NGCP::Panel::Form::BillingFee::API->new(ctx => $c);
}

sub hal_from_fee {
    my ($self, $c, $fee, $form) = @_;

    my %resource = $fee->get_inflated_columns;

    my $hal = NGCP::Panel::Utils::DataHal->new(
        links => [
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'collection', href => sprintf('/api/%s/', $self->resource_name)),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            Data::HAL::Link->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $fee->id)),
            Data::HAL::Link->new(relation => 'ngcp:billingprofiles', href => sprintf("/api/billingprofiles/%d", $fee->billing_profile->id)),
            Data::HAL::Link->new(relation => 'ngcp:billingzones', href => sprintf("/api/billingzones/%d", $fee->billing_zone->id)),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $form //= $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => \%resource,
        run => 0,
        exceptions => ['billing_profile_id'],
    );

    $resource{id} = int($fee->id);
    $resource{billing_profile_id} = int($fee->billing_profile_id);
    $hal->resource({%resource});
    return $hal;
}

sub fee_by_id {
    my ($self, $c, $id) = @_;

    my $item_rs = $self->item_rs($c);
    return $item_rs->find($id);
}

sub update_fee {
    my ($self, $c, $fee, $old_resource, $resource, $form) = @_;

    delete $resource->{purge_existing};

    my $reseller_id;
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $reseller_id = $c->user->reseller_id;
    } else {
        $reseller_id = $c->user->contract->contact->reseller_id;
    }
    $form //= $self->get_form($c);


    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
        exceptions => ['billing_profile_id'],
    );

    my $profile;
    if(!defined $resource->{billing_profile_id}) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'billing_profile_id'");
        return;
    } elsif($old_resource->{billing_profile_id} != $resource->{billing_profile_id}) {
        $profile //= $c->model('DB')->resultset('billing_profiles')
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

    my $zone = $self->get_billing_zone($c,$profile,$resource);
    if($old_resource->{billing_zone_id} != $resource->{billing_zone_id}) {
        unless($zone) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'billing_zone_id'");
            return;
        }
    }

    $fee->update($resource);

    return $fee;
}
sub get_billing_zone{
    my($self,$c,$profile,$resource) = @_;

    if( (!defined $profile) && defined $resource->{billing_profile_id} ){
        $profile = $c->model('DB')->resultset('billing_profiles')->find($resource->{billing_profile_id});    
    }
    if(!defined $profile){
        $c->log->debug("in get_billing_zone: no profile;");
        return;
    }

    my $zone;
    
    # in case of implicit zone declaration (name/detail instead of id),
    # find or create the zone
    if( (!defined $resource->{billing_zone_id}) &&
        defined $resource->{billing_zone_zone} &&
        defined $resource->{billing_zone_detail}  ) {

        $zone = $profile->billing_zones->find({
            zone => $resource->{billing_zone_zone},
            detail => $resource->{billing_zone_detail},
        });
        $zone = $profile->billing_zones->create({
            zone => $resource->{billing_zone_zone},
            detail => $resource->{billing_zone_detail},
        }) unless $zone;
        delete $resource->{billing_zone_zone};
        delete $resource->{billing_zone_detail};
        $resource->{billing_zone_id} = $zone->id;
    }elsif(defined $resource->{billing_zone_id}) {
        $zone = $profile->billing_zones->find($resource->{billing_zone_id});
    }
    return $zone;
}
1;
# vim: set tabstop=4 expandtab:
