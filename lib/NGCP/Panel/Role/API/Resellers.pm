package NGCP::Panel::Role::API::Resellers;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::DateTime;

sub _item_rs {
    my ($self, $c) = @_;

    # no restriction needed, as only admins have access here?
    my $item_rs = $c->model('DB')->resultset('resellers');
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::get("NGCP::Panel::Form::ResellerAPI", $c);
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

    my $hal = NGCP::Panel::Utils::DataHal->new(
        links => [
            NGCP::Panel::Utils::DataHalLink->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'collection', href => sprintf('%s', $self->dispatch_path)),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $reseller->id)),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'ngcp:contracts', href => sprintf("/api/contracts/%d", $reseller->contract->id)),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'ngcp:billingprofiles', href => sprintf("/api/billingprofiles/?reseller_id=%d", $reseller->id)),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'ngcp:ncoslevels', href => sprintf("/api/ncoslevels/?reseller_id=%d", $reseller->id)),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'ngcp:soundsets', href => sprintf("/api/soundsets/?reseller_id=%d", $reseller->id)),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'ngcp:rewriterulesets', href => sprintf("/api/rewriterulesets/?reseller_id=%d", $reseller->id)),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'ngcp:pbxdevices', href => sprintf("/api/pbxdevices/?reseller_id=%d", $reseller->id)),
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
    if(defined $resource->{contract_id} && !is_int($resource->{contract_id})) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'contract_id', not a number");
        return;
    }

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

    eval {
        NGCP::Panel::Utils::Rtc::modify_reseller_rtc(
            old_resource => $old_resource,
            resource => $resource,
            config => $c->config,
            reseller_item => $reseller,
            err_code => sub {
                my ($msg, $debug) = @_;
                $c->log->debug($debug) if $debug;
                $c->log->warn($msg);
                die $msg,"\n";
            });
    };
    my $rtc_err = $@ // '';
    if ($rtc_err) {
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Could not modify rtc_user: $rtc_err");
        return;
    }

    if($old_resource->{status} ne $resource->{status}) {
        NGCP::Panel::Utils::Reseller::_handle_reseller_status_change($c, $reseller);
    }

    # TODO: should we lock reseller admin logins if reseller gets terminated?
    # or terminate all his customers and delete non-billing data?


    return $reseller;
}

1;
# vim: set tabstop=4 expandtab:
