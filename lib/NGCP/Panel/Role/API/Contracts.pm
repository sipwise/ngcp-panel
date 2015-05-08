package NGCP::Panel::Role::API::Contracts;
use Moose::Role;
use Sipwise::Base;
with 'NGCP::Panel::Role::API' => {
    -alias       =>{ item_rs  => '_item_rs', },
    -excludes    => [ 'item_rs' ],
};

use boolean qw(true);
use TryCatch;
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Contract;
#use NGCP::Panel::Form::Contract::PeeringResellerAPI qw();
use NGCP::Panel::Form::Contract::ContractAPI qw();

sub item_rs {
    my ($self, $c, $include_terminated) = @_;

    my $item_rs = NGCP::Panel::Utils::Contract::get_contract_rs(
        schema => $c->model('DB'),
        include_terminated => (defined $include_terminated && $include_terminated ? 1 : 0),
    );
    $item_rs = $item_rs->search({
            'contact.reseller_id' => undef
        },{
            join => 'contact',
            '+select' => 'billing_mappings.id',
            '+as' => 'bmid',
        });

    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::Contract::ContractAPI->new;
}

sub hal_from_contract {
    my ($self, $c, $contract, $form) = @_;

    my $billing_mapping = $contract->billing_mappings->find($contract->get_column('bmid'));
    my $billing_profile_id = $billing_mapping->billing_profile_id;
    my $billing_profiles = NGCP::Panel::Utils::Contract::resource_from_mappings($contract);
    my $stime = NGCP::Panel::Utils::DateTime::current_local()->truncate(to => 'month');
    my $etime = $stime->clone->add(months => 1);
    my $contract_balance = $contract->contract_balances
        ->find({
            start => { '>=' => $stime },
            end => { '<' => $etime },
            });
    unless($contract_balance) {
        try {
            NGCP::Panel::Utils::Contract::create_contract_balance(
                c => $c,
                profile => $billing_mapping->billing_profile,
                contract => $contract,
            );
        } catch($e) {
            $c->log->error("Failed to create current contract balance for contract id '".$contract->id."': $e");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error.");
            return;
        }
        $contract_balance = $contract->contract_balances->find({
            start => { '>=' => $stime },
            end => { '<' => $etime },
        });
    }

    my %resource = $contract->get_inflated_columns;

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
            $billing_profile_id
                ? Data::HAL::Link->new(relation => 'ngcp:billingprofiles', href => sprintf("/api/billingprofiles/%d", $billing_profile_id))
                : (),
            $self->get_journal_relation_link($contract->id),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $form //= $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => \%resource,
        run => 0,
        exceptions => [ "contact_id", "billing_profile_id" ],
    );

    $resource{type} = $billing_mapping->product->class;    
    $resource{billing_profiles} = $billing_profiles;

    $resource{id} = int($contract->id);
    $resource{billing_profile_id} = $billing_profile_id ? int($billing_profile_id) : undef;
    $hal->resource({%resource});
    return $hal;
}

sub contract_by_id {
    my ($self, $c, $id, $include_terminated) = @_;
    my $item_rs = $self->item_rs($c,$include_terminated);
    return $item_rs->find($id);
}

sub update_contract {
    my ($self, $c, $contract, $old_resource, $resource, $form) = @_;

    #my $billing_mapping = $contract->billing_mappings->find($contract->get_column('bmid'));
    #$old_resource->{billing_profile_id} = $billing_mapping->billing_profile_id; 
    #unless($resource->{billing_profile_id}) {
    #    $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'billing_profile_id', not defined");
    #    return;
    #}

    my $billing_mapping = $contract->billing_mappings->find($contract->get_column('bmid'));
    my $billing_profile = $billing_mapping->billing_profile;
    
    $form //= $self->get_form($c);
    # TODO: for some reason, formhandler lets missing contact_id slip thru
    $resource->{billing_profile_id} //= undef;
    $resource->{billing_profiles} //= undef;    
    $resource->{contact_id} //= undef;
    $resource->{type} //= $billing_mapping->product->class;
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
        exceptions => [ "contact_id", "billing_profile_id" ],
    );

    my $mappings_to_create = [];
    my $is_multi_bm_mode = 0;
    return unless NGCP::Panel::Utils::Contract::prepare_billing_mappings(
        c => $c,
        resource => $resource,
        old_resource => $old_resource,
        mappings_to_create => $mappings_to_create,
        is_multi_mode => \$is_multi_bm_mode,
        err_code => sub {
            my ($err) = @_;
            #$c->log->error($err);
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, $err);
        });
    delete $resource->{billing_profile_id};
    delete $resource->{billing_profiles};
    delete $resource->{type};

    #if($old_resource->{billing_profile_id} != $resource->{billing_profile_id}) {
    #    my $billing_profile = $c->model('DB')->resultset('billing_profiles')->find($resource->{billing_profile_id});
    #    unless($billing_profile) {
    #        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'billing_profile_id'");
    #        return;
    #    }
    #    $contract->billing_mappings->create({
    #        start_date => NGCP::Panel::Utils::DateTime::current_local,
    #        billing_profile_id => $resource->{billing_profile_id},
    #        product_id => $billing_mapping->product_id,
    #    });
    #}
    #delete $resource->{billing_profile_id};

    
    
    my $now = NGCP::Panel::Utils::DateTime::current_local;
    $resource->{modify_timestamp} = $now;

    if($old_resource->{contact_id} != $resource->{contact_id}) {
        my $syscontact = $c->model('DB')->resultset('contacts')
            ->search({ reseller_id => undef })
            ->find($resource->{contact_id});
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
        NGCP::Panel::Utils::Contract::remove_future_billing_mappings($contract) if $is_multi_bm_mode;
        foreach my $mapping (@$mappings_to_create) {
            $contract->billing_mappings->create($mapping); 
        }
        $contract = $self->contract_by_id($c, $contract->id,1);
        $billing_mapping = $contract->billing_mappings->find($contract->get_column('bmid'));
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
    
        # TODO: what about changed product, do we allow it?
    } catch($e) {
        $c->log->error("Failed to update contract id '".$contract->id."': $e");
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error.");
        return;
    };        

    return $contract;
}

1;
# vim: set tabstop=4 expandtab:
