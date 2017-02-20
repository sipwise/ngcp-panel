package NGCP::Panel::Role::API::Customers;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Contract;
use NGCP::Panel::Utils::ProfilePackages qw();
use NGCP::Panel::Utils::Preferences;
use NGCP::Panel::Utils::Subscriber qw();
use NGCP::Panel::Form::Contract::CustomerAPI qw();

sub _item_rs {
    my ($self, $c, $now) = @_;

    # returns a contracts rs filtered based on role
    my $item_rs = NGCP::Panel::Utils::Contract::get_customer_rs(
        c => $c,
        include_terminated => 1,
        now => $now,
    );
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::Contract::CustomerAPI->new;
}

sub hal_from_customer {
    my ($self, $c, $customer, $form, $now) = @_;

    my $billing_mapping = $customer->billing_mappings->find($customer->get_column('bmid'));
    my $billing_profile_id = $billing_mapping->billing_profile->id;
    my $future_billing_profiles = NGCP::Panel::Utils::Contract::resource_from_future_mappings($customer);
    my $billing_profiles = NGCP::Panel::Utils::Contract::resource_from_mappings($customer);

    NGCP::Panel::Utils::ProfilePackages::catchup_contract_balances(c => $c,
            contract => $customer,
            now => $now);

    my %resource = $customer->get_inflated_columns;

    my @profile_links = ();
    my @network_links = ();
    foreach my $mapping ($customer->billing_mappings->all) {
        push(@profile_links,NGCP::Panel::Utils::DataHalLink->new(relation => 'ngcp:billingprofiles', href => sprintf("/api/billingprofiles/%d", $mapping->billing_profile_id)));
        if ($mapping->network_id) {
            push(@profile_links,NGCP::Panel::Utils::DataHalLink->new(relation => 'ngcp:billingnetworks', href => sprintf("/api/billingnetworks/%d", $mapping->network_id)));
        }
    }

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
            NGCP::Panel::Utils::DataHalLink->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $customer->id)),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'ngcp:customercontacts', href => sprintf("/api/customercontacts/%d", $customer->contact->id)),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'ngcp:customerpreferences', href => sprintf("/api/customerpreferences/%d", $customer->id)),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'ngcp:customerfraudpreferences', href => sprintf("/api/customerfraudpreferences/%d", $customer->id)),
            @profile_links,
            @network_links,
            $customer->profile_package_id ? NGCP::Panel::Utils::DataHalLink->new(relation => 'ngcp:profilepackages', href => sprintf("/api/profilepackages/%d", $customer->profile_package_id)) : (),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'ngcp:customerbalances', href => sprintf("/api/customerbalances/%d", $customer->id)),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'ngcp:balanceintervals', href => sprintf("/api/balanceintervals/%d", $customer->id)),
            $customer->invoice_template ? (NGCP::Panel::Utils::DataHalLink->new(relation => 'ngcp:invoicetemplates', href => sprintf("/api/invoicetemplates/%d", $customer->invoice_template_id))) : (),
            $customer->subscriber_email_template_id ? (NGCP::Panel::Utils::DataHalLink->new(relation => 'ngcp:subscriberemailtemplates', href => sprintf("/api/emailtemplates/%d", $customer->subscriber_email_template_id))) : (),
            $customer->passreset_email_template_id ? (NGCP::Panel::Utils::DataHalLink->new(relation => 'ngcp:passresetemailtemplates', href => sprintf("/api/emailtemplates/%d", $customer->passreset_email_template_id))) : (),
            $customer->invoice_email_template_id ? (NGCP::Panel::Utils::DataHalLink->new(relation => 'ngcp:invoiceemailtemplates', href => sprintf("/api/emailtemplates/%d", $customer->invoice_email_template_id))) : (),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'ngcp:calls', href => sprintf("/api/calls/?customer_id=%d", $customer->id)),
            $self->get_journal_relation_link($customer->id),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $form //= $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => \%resource,
        run => 0,
        exceptions => [ "contact_id", "billing_profile_id", "profile_package_id", "invoice_template_id", "invoice_email_template_id", "passreset_email_template_id", "subscriber_email_template_id" ],
    );

    foreach my $field (qw/create_timestamp activate_timestamp modify_timestamp terminate_timestamp/){
        $resource{$field} =  defined $resource{$field} ? NGCP::Panel::Utils::DateTime::to_string(NGCP::Panel::Utils::DateTime::from_string($resource{$field})) : undef ;
    }
    # return the virtual "type" instead of the actual product id
    $resource{type} = $billing_mapping->product->class;
    $resource{billing_profiles} = $future_billing_profiles;
    $resource{all_billing_profiles} = $billing_profiles;

    $resource{id} = int($customer->id);
    $resource{billing_profile_id} = int($billing_profile_id);
    $resource{billing_profile_definition} = 'id';
    $hal->resource({%resource});
    return $hal;
}

sub customer_by_id {
    my ($self, $c, $id, $now) = @_;
    my $customers = $self->item_rs($c,$now);
    return $customers->find($id);
}

sub update_customer {
    my ($self, $c, $customer, $old_resource, $resource, $form, $now) = @_;

    if ($customer->status eq 'terminated') {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, 'Customer is already terminated and cannot be changed.');
        return;
    }

    my $billing_mapping = $customer->billing_mappings->find($customer->get_column('bmid'));
    my $billing_profile = $billing_mapping->billing_profile;

    my $old_package = $customer->profile_package;

    $old_resource->{prepaid} = $billing_profile->prepaid;

    $form //= $self->get_form($c);
    # TODO: for some reason, formhandler lets missing contact_id slip thru
    $resource->{contact_id} //= undef;
    $resource->{type} //= $billing_mapping->product->class;
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
        exceptions => [ "contact_id", "billing_profile_id", "profile_package_id", "invoice_template_id", "invoice_email_template_id", "passreset_email_template_id", "subscriber_email_template_id"],
    );
    #$resource->{profile_package_id} = undef unless NGCP::Panel::Utils::ProfilePackages::ENABLE_PROFILE_PACKAGES;

    #my $now = NGCP::Panel::Utils::DateTime::current_local;

    my $mappings_to_create = [];
    my $delete_mappings = 0;
    my $set_package = ($resource->{billing_profile_definition} // 'id') eq 'package';
    return unless NGCP::Panel::Utils::Contract::prepare_billing_mappings(
        c => $c,
        resource => $resource,
        old_resource => $old_resource,
        mappings_to_create => $mappings_to_create,
        now => $now,
        delete_mappings => \$delete_mappings,
        err_code => sub {
            my ($err) = @_;
            #$c->log->error($err);
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, $err);
        });
    delete $resource->{type};

    $resource->{modify_timestamp} = $now; #problematic for ON UPDATE current_timestamp columns

    my $custcontact;
    if($old_resource->{contact_id} != $resource->{contact_id}) {
        $custcontact = $c->model('DB')->resultset('contacts')
            ->search({
                'me.status' => { '!=' => 'terminated' },
                reseller_id => { '-not' => undef },
            })->find($resource->{contact_id});
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

    my $tmplfields = $self->get_template_fields_spec();
    foreach my $field (keys %$tmplfields){
        my $oldtmpl = $old_resource->{$field} // 0;
        if($resource->{$field} &&
           $oldtmpl != $resource->{$field}) {
            my $tmpl = $c->model('DB')->resultset($tmplfields->{$field}->[0])
                ->search({ reseller_id => $custcontact->reseller_id })
                ->find($resource->{$field});
            unless($tmpl) {
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid '$field', doesn't exist for reseller assigned to customer contact");
                return;
            }
        }
    }

    my $old_ext_id = $customer->external_id // '';
    if($resource->{status} eq "terminated") {
        $resource->{terminate_timestamp} = NGCP::Panel::Utils::DateTime::current_local;
    }

    try {
        $customer->update($resource);
        NGCP::Panel::Utils::Contract::remove_future_billing_mappings($customer,$now) if $delete_mappings;
        foreach my $mapping (@$mappings_to_create) {
            $customer->billing_mappings->create($mapping);
        }
        $customer = $self->customer_by_id($c, $customer->id, $now);

        my $balance = NGCP::Panel::Utils::ProfilePackages::catchup_contract_balances(c => $c,
            contract => $customer,
            old_package => $old_package,
            now => $now); #make balance_intervals.t work
        $balance = NGCP::Panel::Utils::ProfilePackages::resize_actual_contract_balance(c => $c,
            contract => $customer,
            old_package => $old_package,
            balance => $balance,
            now => $now,
            profiles_added => ($set_package ? scalar @$mappings_to_create : 0),
            );

        $billing_mapping = $customer->billing_mappings->find($customer->get_column('bmid'));
        $billing_profile = $billing_mapping->billing_profile;

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

        NGCP::Panel::Utils::Subscriber::switch_prepaid_contract(c => $c,
            #old_prepaid => $old_resource->{prepaid},
            #new_prepaid => $billing_profile->prepaid,
            prepaid => $billing_profile->prepaid,
            contract => $customer,
        );

        # TODO: what about changed product, do we allow it?
    } catch($e) {
        $c->log->error("Failed to update customer contract id '".$customer->id."': $e");
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error.");
        return;
    };

    return $customer;
}

sub get_template_fields_spec{
    return {
        'invoice_template_id'          => [qw/invoice_templates invoice_template/],
        'subscriber_email_template_id' => [qw/email_templates subscriber_email_template/],
        'passreset_email_template_id'  => [qw/email_templates passreset_email_template/],
        'invoice_email_template_id'    => [qw/email_templates invoice_email_template/],
    };
}

1;
# vim: set tabstop=4 expandtab:
