package NGCP::Panel::Role::API::Resellers;
use NGCP::Panel::Utils::Generic qw(:all);

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use TryCatch;
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Form::ResellerAPI qw();

sub _item_rs {
    my ($self, $c) = @_;

    # no restriction needed, as only admins have access here?
    my $item_rs = $c->model('DB')->resultset('resellers');
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::ResellerAPI->new;
}

sub hal_from_reseller {
    my ($self, $c, $reseller, $form) = @_;

    my %resource = $reseller->get_inflated_columns;
    if ($reseller->rtc_user) {
        $resource{enable_rtc} = JSON::true;
    } else {
        $resource{enable_rtc} = JSON::false;
    }

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
            Data::HAL::Link->new(relation => 'ngcp:billingprofiles', href => sprintf("/api/billingprofiles/?reseller_id=%d", $reseller->id)),
            Data::HAL::Link->new(relation => 'ngcp:ncoslevels', href => sprintf("/api/ncoslevels/?reseller_id=%d", $reseller->id)),
            Data::HAL::Link->new(relation => 'ngcp:soundsets', href => sprintf("/api/soundsets/?reseller_id=%d", $reseller->id)),
            Data::HAL::Link->new(relation => 'ngcp:rewriterulesets', href => sprintf("/api/rewriterulesets/?reseller_id=%d", $reseller->id)),
            Data::HAL::Link->new(relation => 'ngcp:pbxdevices', href => sprintf("/api/pbxdevices/?reseller_id=%d", $reseller->id)),
            $self->get_journal_relation_link($reseller->id),
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

    my $resellers = $self->item_rs($c);
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

    $reseller->update({
            name => $resource->{name},
            status => $resource->{status},
            contract_id => $resource->{contract_id},
        });

    NGCP::Panel::Utils::Rtc::modify_reseller_rtc(
        old_resource => $old_resource,
        resource => $resource,
        config => $c->config,
        reseller_item => $reseller,
        err_code => sub {
                $c->log->warn(shift); return;
            });

    # TODO: should we lock reseller admin logins if reseller gets terminated?
    # or terminate all his customers and delete non-billing data?


    return $reseller;
}

1;
# vim: set tabstop=4 expandtab:
