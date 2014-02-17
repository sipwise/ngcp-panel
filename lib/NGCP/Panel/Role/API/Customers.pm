package NGCP::Panel::Role::API::Customers;
use Moose::Role;
use Sipwise::Base;

use boolean qw(true);
use TryCatch;
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Contract;
use NGCP::Panel::Utils::Preferences;
use NGCP::Panel::Form::Contract::ProductSelect qw();

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::Contract::PeeringReseller->new;
}

sub hal_from_customer {
    my ($self, $c, $customer, $form) = @_;

    my $billing_mapping = $customer->billing_mappings->find($customer->get_column('bmid'));
    my $billing_profile_id = $billing_mapping->billing_profile->id;
    my $stime = NGCP::Panel::Utils::DateTime::current_local()->truncate(to => 'month');
    my $etime = $stime->clone->add(months => 1);
    my $contract_balance = $customer->contract_balances
        ->find({
            start => { '>=' => $stime },
            end => { '<' => $etime },
            });
    unless($contract_balance) {
        try {
            NGCP::Panel::Utils::Contract::create_contract_balance(
                c => $c,
                profile => $billing_mapping->billing_profile,
                contract => $customer,
            );
        } catch($e) {
            $self->log->error("Failed to create current contract balance for customer contract id '".$customer->id."': $e");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error.");
            return;
        };
        $contract_balance = $customer->contract_balances->find({
            start => { '>=' => $stime },
            end => { '<' => $etime },
        });
    }

    my %resource = $customer->get_inflated_columns;

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
            Data::HAL::Link->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $customer->id)),
            Data::HAL::Link->new(relation => 'ngcp:customercontacts', href => sprintf("/api/customercontacts/%d", $customer->contact->id)),
            Data::HAL::Link->new(relation => 'ngcp:billingprofiles', href => sprintf("/api/billingprofiles/%d", $billing_profile_id)),
            Data::HAL::Link->new(relation => 'ngcp:contractbalances', href => sprintf("/api/contractbalances/%d", $contract_balance->id)),
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

    # return the virtual "type" instead of the actual product id
    delete $resource{product_id};
    $resource{type} = $billing_mapping->product->class;

    $resource{id} = int($customer->id);
    $resource{billing_profile_id} = int($billing_profile_id);
    $hal->resource({%resource});
    return $hal;
}

sub customer_by_id {
    my ($self, $c, $id) = @_;

    # we only return customers, that is, contracts with contacts with a
    # reseller
    my $customers = NGCP::Panel::Utils::Contract::get_contract_rs(
        schema => $c->model('DB'),
    );
    $customers = $customers->search({
            'contact.reseller_id' => { '-not' => undef },
        },{
            join => 'contact'
        });

    $customers = $customers->search({
            '-or' => [
                'product.class' => 'sipaccount',
                'product.class' => 'pbxaccount',
            ],
        },{
            join => {'billing_mappings' => 'product' },
            '+select' => 'billing_mappings.id',
            '+as' => 'bmid',
        });

    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $customers = $customers->search({
            'contact.reseller_id' => $c->user->reseller_id,
        });
    } 

    return $customers->find($id);
}

sub update_customer {
    my ($self, $c, $customer, $old_resource, $resource, $form) = @_;

    my $billing_mapping = $customer->billing_mappings->find($customer->get_column('bmid'));
    $old_resource->{billing_profile_id} = $billing_mapping->billing_profile_id;
    $old_resource->{prepaid} =  $billing_mapping->billing_profile->prepaid;
    unless($resource->{billing_profile_id}) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'billing_profile_id', not defined");
        return;
    }
   
    $form //= $self->get_form($c);
    # TODO: for some reason, formhandler lets missing contact_id slip thru
    $resource->{contact_id} //= undef; 
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
    );

    my $now = NGCP::Panel::Utils::DateTime::current_local;
    $resource->{modify_timestamp} = $now;
    my $billing_profile;

    if($old_resource->{billing_profile_id} != $resource->{billing_profile_id}) {
        $billing_profile = $c->model('DB')->resultset('billing_profiles')->find($resource->{billing_profile_id});
        unless($billing_profile) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'billing_profile_id', doesn't exist");
            return;
        }
        unless($billing_profile->reseller_id == $customer->contact->reseller_id) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'billing_profile_id', reseller doesn't match customer contact reseller");
            return;
        }
        $customer->billing_mappings->create({
            start_date => NGCP::Panel::Utils::DateTime::current_local,
            billing_profile_id => $resource->{billing_profile_id},
            product_id => $billing_mapping->product_id,
        });
    }
    delete $resource->{billing_profile_id};


    if($old_resource->{contact_id} != $resource->{contact_id}) {
        my $custcontact = $c->model('DB')->resultset('contacts')
            ->search({ reseller_id => { '-not' => undef }})
            ->find($resource->{contact_id});
        unless($custcontact) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'contact_id', doesn't exist");
            return;
        }
        unless($billing_profile->reseller_id == $custcontact->reseller_id) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'contact_id', reseller doesn't match billing profile reseller");
            return;
        }
    }

    my $old_ext_id = $customer->external_id;

    $customer->update($resource);

    if($customer->external_id ne $old_ext_id) {
        foreach my $sub($customer->voip_subscribers->all) {
            my $prov_sub = $sub->provisioning_voip_subscriber;
            next unless($prov_sub);
            NGCP::Panel::Utils::Subscriber::update_preferences(
                c => $c,
                prov_subscriber => $prov_sub,
                preferences => { ext_contract_id => $customer->external_id }
            );
        }
    }

    if($old_resource->{status} ne $resource->{status}) {
        if($customer->id == 1) {
            $self->error($c, HTTP_FORBIDDEN, "Cannot set customer status to '".$resource->{status}."' for customer id '1'");
            return;
        }
        NGCP::Panel::Utils::Contract::recursively_lock_contract(
            c => $c,
            contract => $customer,
        );
    }

    if($billing_profile) { # check prepaid change if billing profile changed
        if($old_resource->{prepaid} && !$billing_profile->prepaid) {
            foreach my $sub($customer->voip_subscribers->all) {
                my $prov_sub = $sub->provisioning_voip_subscriber;
                next unless($prov_sub);
                my $pref = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                    c => $c, attribute => 'prepaid', prov_subscriber => $prov_sub);
                if($pref->first) {
                    $pref->first->delete;
                }
            }
        } elsif(!$old_resource->{prepaid} && $billing_profile->prepaid) {
            foreach my $sub($customer->voip_subscribers->all) {
                my $prov_sub = $sub->provisioning_voip_subscriber;
                next unless($prov_sub);
                my $pref = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                    c => $c, attribute => 'prepaid', prov_subscriber => $prov_sub);
                if($pref->first) {
                    $pref->first->update({ value => 1 });
                } else {
                    $pref->create({ value => 1 });
                }
            }
        }
    }

    # TODO: what about changed product, do we allow it?

    return $customer;
}

1;
# vim: set tabstop=4 expandtab:
