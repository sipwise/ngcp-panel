package NGCP::Panel::Role::API::Customers;
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
use NGCP::Panel::Utils::Preferences;
use NGCP::Panel::Form::Contract::ProductOptional;

sub item_rs {
    my ($self, $c) = @_;

    # returns a contracts rs filtered based on role
    my $item_rs = NGCP::Panel::Utils::Contract::get_customer_rs(
        c => $c,
        include_terminated => 1,
    );
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::Contract::ProductOptional->new;
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
            Data::HAL::Link->new(relation => 'ngcp:customerpreferences', href => sprintf("/api/customerpreferences/%d", $customer->id)),
            Data::HAL::Link->new(relation => 'ngcp:billingprofiles', href => sprintf("/api/billingprofiles/%d", $billing_profile_id)),
            Data::HAL::Link->new(relation => 'ngcp:contractbalances', href => sprintf("/api/contractbalances/%d", $contract_balance->id)),
            $customer->invoice_template ? (Data::HAL::Link->new(relation => 'ngcp:invoicetemplates', href => sprintf("/api/invoicetemplates/%d", $customer->invoice_template_id))) : (),
            $customer->subscriber_email_template_id ? (Data::HAL::Link->new(relation => 'ngcp:subscriberemailtemplates', href => sprintf("/api/emailtemplates/%d", $customer->subscriber_email_template_id))) : (),
            $customer->passreset_email_template_id ? (Data::HAL::Link->new(relation => 'ngcp:passresetemailtemplates', href => sprintf("/api/emailtemplates/%d", $customer->passreset_email_template_id))) : (),
            $customer->invoice_email_template_id ? (Data::HAL::Link->new(relation => 'ngcp:invoiceemailtemplates', href => sprintf("/api/emailtemplates/%d", $customer->invoice_email_template_id))) : (),
            Data::HAL::Link->new(relation => 'ngcp:calls', href => sprintf("/api/calls/?customer_id=%d", $customer->id)),
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
    my $customers = $self->item_rs($c);
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

    $billing_profile = $c->model('DB')->resultset('billing_profiles')->find($resource->{billing_profile_id});
    unless($billing_profile) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'billing_profile_id', doesn't exist");
        return;
    }
    if($old_resource->{billing_profile_id} != $resource->{billing_profile_id}) {
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

    my $custcontact;
    if($old_resource->{contact_id} != $resource->{contact_id}) {
        $custcontact = $c->model('DB')->resultset('contacts')
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
    } else {
        $custcontact = $customer->contact;
    }

    my $oldinvoicetmpl = $old_resource->{invoice_template_id} // 0;
    if($resource->{invoice_template_id} && 
       $oldinvoicetmpl != $resource->{invoice_template_id}) {
        my $tmpl = $c->model('DB')->resultset('invoice_templates')
            ->search({ reseller_id => $custcontact->reseller_id })
            ->find($resource->{invoice_template_id});
        unless($tmpl) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'invoice_template_id', doesn't exist for reseller assigned to customer contact");
            return;
        }
    }
    my $oldsubtmpl = $old_resource->{subscriber_email_template_id} // 0;
    if($resource->{subscriber_email_template_id} && 
       $oldsubtmpl != $resource->{subscriber_email_template_id}) {
        my $tmpl = $c->model('DB')->resultset('email_templates')
            ->search({ reseller_id => $custcontact->reseller_id })
            ->find($resource->{subscriber_email_template_id});
        unless($tmpl) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'subscriber_email_template_id', doesn't exist for reseller assigned to customer contact");
            return;
        }
    }
    my $oldpasstmpl = $old_resource->{passreset_email_template_id} // 0;
    if($resource->{passreset_email_template_id} && 
       $oldpasstmpl != $resource->{passreset_email_template_id}) {
        my $tmpl = $c->model('DB')->resultset('email_templates')
            ->search({ reseller_id => $custcontact->reseller_id })
            ->find($resource->{passreset_email_template_id});
        unless($tmpl) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'passreset_email_template_id', doesn't exist for reseller assigned to customer contact");
            return;
        }
    }
    my $oldinvtmpl = $old_resource->{invoice_email_template_id} // 0;
    if($resource->{invoice_email_template_id} && 
       $oldinvtmpl != $resource->{invoice_email_template_id}) {
        my $tmpl = $c->model('DB')->resultset('email_templates')
            ->search({ reseller_id => $custcontact->reseller_id })
            ->find($resource->{invoice_email_template_id});
        unless($tmpl) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'invoice_email_template_id', doesn't exist for reseller assigned to customer contact");
            return;
        }
    }

    my $old_ext_id = $customer->external_id // '';

    $customer->update($resource);

    if(($customer->external_id // '') ne $old_ext_id) {
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
