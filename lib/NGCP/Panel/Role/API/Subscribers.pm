package NGCP::Panel::Role::API::Subscribers;
use Moose::Role;
use Sipwise::Base;

use boolean qw(true);
use Try::Tiny;
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use JSON::Types;
use Test::More;
use NGCP::Panel::Form::Subscriber::SubscriberAPI;
use NGCP::Panel::Utils::XMLDispatcher;
use NGCP::Panel::Utils::Prosody;

sub get_form {
    my ($self, $c) = @_;

    return NGCP::Panel::Form::Subscriber::SubscriberAPI->new;
}

sub transform_resource {
    my ($self, $c, $item, $form) = @_;

    my $bill_resource = { $item->get_inflated_columns };
    my $prov_resource = { $item->provisioning_voip_subscriber->get_inflated_columns };
    my $customer = $self->get_customer($c, $item->contract_id);
    delete $prov_resource->{domain_id};
    delete $prov_resource->{account_id};
    my %resource = %{ $bill_resource->merge($prov_resource) };
    unless($customer->get_column('product_class') eq 'pbxaccount') {
        delete $resource{is_pbx_group};
        delete $resource{pbx_group_id};
    }

    $form //= $self->get_form($c);

    $self->validate_form(
        c => $c,
        resource => \%resource,
        form => $form,
        run => 0,
    );

    if($item->primary_number) {
        $resource{primary_number}->{cc} = $item->primary_number->cc;
        $resource{primary_number}->{ac} = $item->primary_number->ac;
        $resource{primary_number}->{sn} = $item->primary_number->sn;
    }
    if($item->voip_numbers->count) {
         $resource{alias_numbers} = [];
        foreach my $n($item->voip_numbers->all) {
            my $alias = {
                cc => $n->cc,
                ac => $n->ac,
                sn => $n->sn,
            };
            next if($resource{primary_number} && 
               is_deeply($resource{primary_number}, $alias));
            push @{ $resource{alias_numbers} }, $alias;
        }
    }
    $resource{customer_id} = int(delete $resource{contract_id});
    $resource{id} = int($item->id);
    $resource{domain} = $item->domain->domain;

    return \%resource;
}

sub hal_from_item {
    my ($self, $c, $item, $resource, $form) = @_;

    my $hal = Data::HAL->new(
        links => [
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'collection', href => sprintf("/api/%s/", $self->resource_name)),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            Data::HAL::Link->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $item->id)),
            Data::HAL::Link->new(relation => 'ngcp:subscriberpreferences', href => sprintf("/api/subscriberpreferences/%d", $item->id)),
            Data::HAL::Link->new(relation => 'ngcp:domains', href => sprintf("/api/domains/%d", $item->domain->id)),
            Data::HAL::Link->new(relation => 'ngcp:customers', href => sprintf("/api/customers/%d", $item->contract_id)),
            #Data::HAL::Link->new(relation => 'ngcp:registrations', href => sprintf("/api/registrations/%d", $item->contract->id)),
            #Data::HAL::Link->new(relation => 'ngcp:trustedsources', href => sprintf("/api/trustedsources/%d", $item->contract->id)),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $hal->resource($resource);
    return $hal;
}

sub item_rs {
    my ($self, $c) = @_;

    my $item_rs;
    $item_rs = $c->model('DB')->resultset('voip_subscribers')
        ->search({ status => { '!=' => 'terminated' } });
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({
            'contact.reseller_id' => $c->user->reseller_id,
        }, {
            join => { 'contract' => 'contact' },
        });
    }
    return $item_rs;
}

sub item_by_id {
    my ($self, $c, $id) = @_;

    my $item_rs = $self->item_rs($c);
    return $item_rs->find($id);
}

sub get_customer {
    my ($self, $c, $customer_id) = @_;

    my $customer = NGCP::Panel::Utils::Contract::get_contract_rs(
        schema => $c->model('DB'),
    );
    $customer = $customer->search({
            'contact.reseller_id' => { '-not' => undef },
            'me.id' => $customer_id,
        },{
            join => 'contact'
        });
    $customer = $customer->search({
            '-or' => [
                'product.class' => 'sipaccount',
                'product.class' => 'pbxaccount',
            ],
        },{
            join => {'billing_mappings' => 'product' },
            '+select' => [ 'billing_mappings.id', 'product.class' ],
            '+as' => [ 'bmid', 'product_class' ],
        });
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $customer = $customer->search({
            'contact.reseller_id' => $c->user->reseller_id,
        });
    }
    $customer = $customer->first;
    unless($customer) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'customer_id', doesn't exist.");
        return;
    }
    return $customer;
}

sub get_billing_profile {
    my ($self, $c, $customer) = @_;

    my $mapping = $customer->billing_mappings->find($customer->get_column('bmid'));
    if($mapping) {
        return $mapping->billing_profile;
    } else {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'customer_id', doesn't have a valid billing mapping.");
        return;
    }
}

sub prepare_resource {
    my ($self, $c, $schema, $resource) = @_;

    my $domain;
    if($resource->{domain}) {
        $domain = $c->model('DB')->resultset('domains')
            ->search({ domain => $resource->{domain} });
        if($c->user->roles eq "admin") {
        } elsif($c->user->roles eq "reseller") {
            $domain = $domain->search({ 
                'domain_resellers.reseller_id' => $c->user->reseller_id,
            }, {
                join => 'domain_resellers',
            });
        }
        $domain = $domain->first;
        unless($domain) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'domain', doesn't exist.");
            return;
        }
        delete $resource->{domain};
        $resource->{domain_id} = $domain->id;
    }

    $resource->{e164} = delete $resource->{primary_number};
    $resource->{contract_id} = delete $resource->{customer_id};
    $resource->{status} //= 'active';
    $resource->{administrative} //= 0;

    my $form = $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        resource => $resource,
        form => $form,
    );

    unless($domain) {
        $domain = $c->model('DB')->resultset('domains')->search($resource->{domain_id});
        if($c->user->roles eq "admin") {
        } elsif($c->user->roles eq "reseller") {
            $domain = $domain->search({ 
                'domain_resellers.reseller_id' => $c->user->reseller_id,
            }, {
                join => 'domain_resellers',
            });
        }
        $domain = $domain->first;
        unless($domain) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'domain', doesn't exist.");
            return;
        }
    }

    my $customer = $self->get_customer($c, $resource->{contract_id});
    return unless($customer);
    if(defined $customer->max_subscribers && $customer->voip_subscribers->search({ 
            status => { '!=' => 'terminated' }
        })->count >= $customer->max_subscribers) {
        
        $self->error($c, HTTP_FORBIDDEN, "Maximum number of subscribers reached.");
        return;
    }

    my $preferences = {};
    my $admin = 0;
    unless($customer->get_column('product_class') eq 'pbxaccount') {
        delete $resource->{is_pbx_group};
        delete $resource->{pbx_group_id};
        $admin = $resource->{admin} // 0;
    } elsif($c->config->{features}->{cloudpbx}) {
        my $subs = NGCP::Panel::Utils::Subscriber::get_custom_subscriber_struct(
            c => $c,
            contract => $customer,
            show_locked => 1,
        );
        use Data::Printer; say ">>>>>>>>>>>>>>>>>>>> subs"; p $subs;
        my $admin_subscribers = NGCP::Panel::Utils::Subscriber::get_admin_subscribers(
            voip_subscribers => $subs->{subscribers});
        unless(@{ $admin_subscribers }) {
            $admin = $resource->{admin} // 1;
        } else {
            $admin = $resource->{admin} // 0;
        }

        $preferences->{shared_buddylist_visibility} = 1;
        $preferences->{display_name} = $resource->{display_name}
            if(defined $resource->{display_name});

        my $default_sound_set = $customer->voip_sound_sets
            ->search({ contract_default => 1 })->first;
        if($default_sound_set) {
            $preferences->{contract_sound_set} = $default_sound_set->id;
        }

        my $admin_subscriber = $admin_subscribers->[0];
        my $base_number = $admin_subscriber->{primary_number};
        if($base_number) {
            $preferences->{cloud_pbx_base_cli} = $base_number->{cc} . $base_number->{ac} . $base_number->{sn};
        }
    }

    my $billing_profile = $self->get_billing_profile($c, $customer);
    return unless($billing_profile);
    if($billing_profile->prepaid) {
        $preferences->{prepaid} = 1;
    }

    my $subscriber = $c->model('DB')->resultset('voip_subscribers')->find({
        username => $resource->{username},
        domain_id => $resource->{domain_id},
        status => { '!=' => 'terminated' },
    });
    if($subscriber) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Subscriber already exists.");
        return;
    }

    my $alias_numbers = [];
    unless(exists $resource->{alias_numbers}) {
        # no alias numbers given, fine
    } elsif(ref $resource->{alias_numbers} eq "ARRAY") {
        foreach my $num(@{ $resource->{alias_numbers} }) {
            unless(ref $num eq "HASH") {
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid parameter 'alias_numbers', must be hash or array of hashes.");
                return;
            }
            push @{ $alias_numbers }, { e164 => $num };
        }
    } elsif(ref $resource->{alias_numbers} eq "HASH") {
        push @{ $alias_numbers }, { e164 => $resource->{alias_numbers} };
    } else {
        use Data::Printer; p $resource->{alias_numbers}; say ">>>>>>>>>>> '".(ref $resource->{alias_numbers})."'";
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid parameter 'alias_numbers', must be hash or array of hashes.");
        return;
    }

    # TODO: handle pbx subscribers:
        # extension
        # is group
        # default sound set

    # TODO: handle status != active

    my $r = {
        resource => $resource,
        customer => $customer,
        admin => $admin,
        alias_numbers => $alias_numbers,
        preferences => $preferences,
    };
    return $r;
}

sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    $form //= $self->get_form($c);

    print ">>>>>>>>>>>>> validate before update\n";

    $resource->{e164} = delete $resource->{primary_number};

    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
    );

    print ">>>>>>>>>>>>> update\n";
    $item->update($resource);
    print ">>>>>>>>>>>>> done update\n";

    return $item;
}

1;
# vim: set tabstop=4 expandtab:
