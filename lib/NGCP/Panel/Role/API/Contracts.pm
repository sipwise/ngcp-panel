package NGCP::Panel::Role::API::Contracts;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Contract;
use NGCP::Panel::Utils::ProfilePackages qw();
use NGCP::Panel::Utils::BillingMappings qw();

sub _item_rs {
    my ($self, $c, $include_terminated,$now) = @_;

    my $item_rs = NGCP::Panel::Utils::Contract::get_contract_rs(
        schema => $c->model('DB'),
        include_terminated => (defined $include_terminated && $include_terminated ? 1 : 0),
        now => $now,
    );
    my @product_ids = map { $_->id; } $c->model('DB')->resultset('products')->search_rs({ 'class' => ['pstnpeering','sippeering','reseller'] })->all;
    $item_rs = $item_rs->search({
        'product_id' => { -in => [ @product_ids ] },
    },{
        join => 'contact',
    });
   
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::get("NGCP::Panel::Form::Contract::ContractAPI", $c);
}

sub resource_from_item {
    my ($self, $c, $item, $form, $now) = @_;

    my %resource = $item->get_inflated_columns;

    $now //= NGCP::Panel::Utils::DateTime::current_local;
    my $billing_mapping = NGCP::Panel::Utils::BillingMappings::get_actual_billing_mapping(c => $c, now => $now, contract => $item, );
    my $billing_profile_id = $billing_mapping->billing_profile->id;
    my $future_billing_profiles = NGCP::Panel::Utils::BillingMappings::resource_from_future_mappings($item);
    my $billing_profiles = NGCP::Panel::Utils::BillingMappings::resource_from_mappings($item);

    #contract balances are created with GET api/contracts/4711
    NGCP::Panel::Utils::ProfilePackages::catchup_contract_balances(c => $c,
            contract => $item,
            now => $now);

    $form //= $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => \%resource,
        run => 0,
    );

    $resource{type} = $item->product->class;
    $resource{billing_profiles} = $future_billing_profiles;
    $resource{all_billing_profiles} = $billing_profiles;

    $resource{id} = int($item->id);
    $resource{billing_profile_id} = $billing_profile_id ? int($billing_profile_id) : undef;
    $resource{billing_profile_definition} = 'id';

    return \%resource;
}

sub hal_from_contract {
    my ($self, $c, $contract, $form, $now) = @_;

    my $resource = $self->resource_from_item($c, $contract, $form, $now);

    my @profile_links = ();
    my @network_links = ();
    foreach my $mapping ($contract->billing_mappings->all) {
        push(@profile_links,Data::HAL::Link->new(relation => 'ngcp:billingprofiles', href => sprintf("/api/billingprofiles/%d", $mapping->billing_profile->id)));
        if ($mapping->network_id) {
            push(@profile_links,Data::HAL::Link->new(relation => 'ngcp:billingnetworks', href => sprintf("/api/billingnetworks/%d", $mapping->network_id)));
        }
    }

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
            Data::HAL::Link->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $contract->id)),
            Data::HAL::Link->new(relation => 'ngcp:systemcontacts', href => sprintf("/api/systemcontacts/%d", $contract->contact->id)),
            @profile_links,
            @network_links,
            Data::HAL::Link->new(relation => 'ngcp:balanceintervals', href => sprintf("/api/balanceintervals/%d", $contract->id)),
            $self->get_journal_relation_link($c, $contract->id),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $self->expand_fields($c, $resource);
    $hal->resource($resource);
    return $hal;
}

sub contract_by_id {
    my ($self, $c, $id, $include_terminated, $now) = @_;
    my $item_rs = $self->item_rs($c,$include_terminated,$now);
    return $item_rs->find($id);
}

sub update_contract {
    my ($self, $c, $contract, $old_resource, $resource, $form, $now) = @_;

    my $billing_mapping = NGCP::Panel::Utils::BillingMappings::get_actual_billing_mapping(c => $c, now => $now, contract => $contract, );
    my $billing_profile = $billing_mapping->billing_profile;

    $old_resource->{billing_mapping} = $billing_mapping;

    my $old_package = $contract->profile_package;

    $form //= $self->get_form($c);
    # TODO: for some reason, formhandler lets missing contact_id slip thru
    $resource->{contact_id} //= undef;
    $resource->{type} //= $contract->product->class;
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
    );

    my $mappings_to_create = [];
    my $delete_mappings = 0;
    my $set_package = ($resource->{billing_profile_definition} // 'id') eq 'package';
    return unless NGCP::Panel::Utils::BillingMappings::prepare_billing_mappings(
        c => $c,
        resource => $resource,
        old_resource => $old_resource,
        mappings_to_create => $mappings_to_create,
        delete_mappings => \$delete_mappings,
        now => $now,
        err_code => sub {
            my ($err) = @_;
            #$c->log->error($err);
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, $err);
        });
    delete $resource->{type};

    #according to api_description, the whole contracts API is dedicated to the peering/reseller contracts and so no product checking is needed here, but to avoid possible mess in the future, we will check product
    if ( 
        NGCP::Panel::Utils::Contract::is_peering_reseller_contract( c => $c, contract => $contract ) 
        && 
        ( my $prepaid_billing_profile_exist = NGCP::Panel::Utils::BillingMappings::check_prepaid_profiles_exist(
            c => $c,
            mappings_to_create => $mappings_to_create) )
    ) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Peering/reseller contract can't be connected to the prepaid billing profile $prepaid_billing_profile_exist.");
        return;
    }
    $resource->{modify_timestamp} = $now; #problematic for ON UPDATE current_timestamp columns

    if($old_resource->{contact_id} != $resource->{contact_id}) {
        my $syscontact = $c->model('DB')->resultset('contacts')
            ->search({
                'me.status' => { '!=' => 'terminated' },
                reseller_id => undef,
            })->find($resource->{contact_id});
        unless($syscontact) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'contact_id'");
            return;
        }
    }
    if($resource->{status} eq "terminated") {
        $resource->{terminate_timestamp} = NGCP::Panel::Utils::DateTime::current_local;
    }

    try {
        $contract->update($resource);
        NGCP::Panel::Utils::BillingMappings::append_billing_mappings(c => $c,
            contract => $contract,
            mappings_to_create => $mappings_to_create,
            now => $now,
            delete_mappings => $delete_mappings,
        );
        $contract = $self->contract_by_id($c, $contract->id,1,$now);

        my $balance = NGCP::Panel::Utils::ProfilePackages::catchup_contract_balances(c => $c,
            contract => $contract,
            old_package => $old_package,
            now => $now); #make balance_intervals.t work
        $balance = NGCP::Panel::Utils::ProfilePackages::resize_actual_contract_balance(c => $c,
            contract => $contract,
            old_package => $old_package,
            balance => $balance,
            now => $now,
            profiles_added => ($set_package ? scalar @$mappings_to_create : 0),
            );

        $billing_mapping = NGCP::Panel::Utils::BillingMappings::get_actual_billing_mapping(c => $c, now => $now, contract => $contract, );
        $billing_profile = $billing_mapping->billing_profile;

        if($old_resource->{status} ne $resource->{status}) {
            if($contract->id == 1) {
                $self->error($c, HTTP_FORBIDDEN, "Cannot set contract status to '".$resource->{status}."' for contract id '1'");
                return;
            }
            NGCP::Panel::Utils::Contract::recursively_lock_contract(
                c => $c,
                contract => $contract,
            );
        }

        return $contract;
        # TODO: what about changed product, do we allow it?
    } catch($e) {
        $c->log->error("Failed to update contract id '".$contract->id."': $e");
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error.");
    };


}

1;
# vim: set tabstop=4 expandtab:
