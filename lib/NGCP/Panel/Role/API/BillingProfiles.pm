package NGCP::Panel::Role::API::BillingProfiles;
use Moose::Role;
use Sipwise::Base;

use boolean qw(true);
use Try::Tiny;
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Contract;
use NGCP::Panel::Form::BillingProfile::Admin qw();

sub hal_from_profile {
    my ($self, $c, $profile, $form) = @_;

    my %resource = $profile->get_inflated_columns;

    # TODO: we should return the fees in an embedded field,
    # if the structure is returned for one single item
    # (make it a method flag)

    my $hal = Data::HAL->new(
        links => [
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'collection', href => sprintf('/api/%s/', $self->resource_name)),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            Data::HAL::Link->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $profile->id)),
            ( map { Data::HAL::Link->new(relation => 'ngcp:billingfees', href => sprintf("/api/billingfees/%d", $_->id)) } $profile->billing_fees->all ),
            ( map { Data::HAL::Link->new(relation => 'ngcp:billingzones', href => sprintf("/api/billingzones/%d", $_->id)) } $profile->billing_zones->all ),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $form //= NGCP::Panel::Form::BillingProfile::Admin->new;
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => \%resource,
        run => 0,
    );

    $resource{id} = int($profile->id);
    $hal->resource({%resource});
    return $hal;
}

sub profile_by_id {
    my ($self, $c, $id) = @_;

    my $profiles = $c->model('DB')->resultset('billing_profiles');
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $profiles = $profiles->search({
            reseller_id => $c->user->reseller_id,
        });
    } else {
        $profiles = $profiles->search({
            reseller_id => $c->user->contract->contact->reseller_id,
        });
    }

    return $profiles->find($id);
}

sub update_profile {
    my ($self, $c, $profile, $old_resource, $resource, $form) = @_;

    $form //= NGCP::Panel::Form::BillingProfile::Admin->new;
    # TODO: for some reason, formhandler lets missing reseller slip thru
    $resource->{reseller_id} //= undef;
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
    );

    if($old_resource->{reseller_id} != $resource->{reseller_id}) {
        my $reseller = $c->model('DB')->resultset('resellers')
            ->find($resource->{reseller_id});
        unless($reseller) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'reseller_id'");
            return;
        }
    }

    $profile->update($resource);

    return $profile;
}

1;
# vim: set tabstop=4 expandtab:
