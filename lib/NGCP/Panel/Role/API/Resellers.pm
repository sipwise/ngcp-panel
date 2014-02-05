package NGCP::Panel::Role::API::Resellers;
use Moose::Role;
use Sipwise::Base;

use boolean qw(true);
use Try::Tiny;
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Form::Reseller qw();

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::Reseller->new;
}

sub hal_from_reseller {
    my ($self, $c, $reseller, $form) = @_;

    my %resource = $reseller->get_inflated_columns;

    # TODO: we should return the relations in embedded fields,
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
            Data::HAL::Link->new(relation => 'collection', href => sprintf('%s', $self->dispatch_path)),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            Data::HAL::Link->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $reseller->id)),
            Data::HAL::Link->new(relation => 'ngcp:contracts', href => sprintf("/api/contracts/%d", $reseller->contract->id)),
            ( map { Data::HAL::Link->new(relation => 'ngcp:admins', href => sprintf("/api/admins/%d", $_->id)) } $reseller->admins->all ),
            ( map { Data::HAL::Link->new(relation => 'ngcp:billingprofiles', href => sprintf("/api/billingprofiles/%d", $_->id)) } $reseller->billing_profiles->all ),
            ( map { Data::HAL::Link->new(relation => 'ngcp:ncoslevels', href => sprintf("/api/ncoslevels/%d", $_->id)) } $reseller->ncos_levels->all ),
            ( map { Data::HAL::Link->new(relation => 'ngcp:soundsets', href => sprintf("/api/soundsets/%d", $_->id)) } $reseller->voip_sound_sets->all ),
            ( map { Data::HAL::Link->new(relation => 'ngcp:rewriterulesets', href => sprintf("/api/rewriterulesets/%d", $_->id)) } $reseller->voip_rewrite_rule_sets->all ),
            ( map { Data::HAL::Link->new(relation => 'ngcp:pbxdevices', href => sprintf("/api/pbxdevices/%d", $_->id)) } $reseller->autoprov_devices->all ),
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

    $resource{id} = int($reseller->id);
    $hal->resource({%resource});
    return $hal;
}

sub reseller_by_id {
    my ($self, $c, $id) = @_;

    my $resellers = $c->model('DB')->resultset('resellers');
    # no restriction needed, as only admins have access here?
    return $resellers->find($id);
}

sub update_reseller {
    my ($self, $c, $reseller, $old_resource, $resource, $form) = @_;

    $form //= $self->get_form($c);
    $resource->{contract_id} //= undef;
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
    );

    if($old_resource->{contract_id} != $resource->{contract_id}) {
        if($c->model('DB')->resultset('resellers')->find({
                contract_id => $resource->{contract_id},
        })) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'contract_id', reseller with this contract already exists");
            return;
        }
        my $contract = $c->model('DB')->resultset('contracts')
            ->find($resource->{contract_id});
        unless($contract) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'contract_id'");
            return;
        }
        if($contract->contact->reseller_id) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'contract_id' linking to a customer contact");
            return;
        }

        # TODO: check if product is reseller (contract/billing-mapping/product), also in POST
    }
    if($old_resource->{name} ne $resource->{name}) {
        if($c->model('DB')->resultset('resellers')->find({
                name => $resource->{name},
        })) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'name', reseller with this name already exists");
            return;
        }
    }

    $reseller->update($resource);

    # TODO: should we lock reseller admin logins if reseller gets terminated?
    # or terminate all his customers and delete non-billing data?


    return $reseller;
}

1;
# vim: set tabstop=4 expandtab:
