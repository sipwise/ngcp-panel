package NGCP::Panel::Role::API::Subscribers;
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
use JSON::Types;
use Test::More;
use NGCP::Panel::Form::Subscriber::SubscriberAPI;
use NGCP::Panel::Utils::XMLDispatcher;
use NGCP::Panel::Utils::Prosody;
use NGCP::Panel::Utils::Subscriber;

sub get_form {
    my ($self, $c) = @_;

    return NGCP::Panel::Form::Subscriber::SubscriberAPI->new(ctx => $c);
}

sub resource_from_item {
    my ($self, $c, $item, $form) = @_;

    my $bill_resource = { $item->get_inflated_columns };
    my $prov_resource = { $item->provisioning_voip_subscriber->get_inflated_columns };
    my $customer = $self->get_customer($c, $item->contract_id);
    delete $prov_resource->{domain_id};
    delete $prov_resource->{account_id};
    my %resource = %{ $bill_resource->merge($prov_resource) };
    $resource{administrative} = delete $resource{admin};

    unless($customer->get_column('product_class') eq 'pbxaccount') {
        delete $resource{is_pbx_group};
        delete $resource{is_pbx_pilot};
        delete $resource{pbx_extension};
        delete $resource{pbx_group_id};
    }
    unless($self->is_true($resource{is_pbx_group})) {
        delete $resource{pbx_hunt_policy};
        delete $resource{pbx_hunt_timeout};
    }
    delete $resource{contact_id};
    if($item->contact) {
        $resource{email} = $item->contact->email;
    } else {
        $resource{email} = undef;
    }


    $form //= $self->get_form($c);
    last unless $self->validate_form(
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

    my $pref = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
        c => $c, attribute => 'lock', 
        prov_subscriber => $item->provisioning_voip_subscriber);
    if($pref->first) {
        $resource{lock} = $pref->first->value;
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
            ($item->provisioning_voip_subscriber && $item->provisioning_voip_subscriber->profile_set_id) ? (Data::HAL::Link->new(relation => 'ngcp:subscriberprofilesets', href => sprintf("/api/subscriberprofilesets/%d", $item->provisioning_voip_subscriber->profile_set_id))) : (),
            ($item->provisioning_voip_subscriber && $item->provisioning_voip_subscriber->profile_id) ? (Data::HAL::Link->new(relation => 'ngcp:subscriberprofiles', href => sprintf("/api/subscriberprofiles/%d", $item->provisioning_voip_subscriber->profile_id))) : (),
            Data::HAL::Link->new(relation => 'ngcp:calls', href => sprintf("/api/calls/?subscriber_id=%d", $item->id)),
            Data::HAL::Link->new(relation => 'ngcp:voicemailsettings', href => sprintf("/api/voicemailsettings/%d", $item->id)),
            Data::HAL::Link->new(relation => 'ngcp:subscriberregistrations', href => sprintf("/api/subscriberregistrations/?subscriber_id=%d", $item->id)),
            Data::HAL::Link->new(relation => 'ngcp:reminders', href => sprintf("/api/reminders/?subscriber_id=%d", $item->id)),
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
        ->search({ 'me.status' => { '!=' => 'terminated' } });
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
            join => 'contact',
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
    my ($self, $c, $schema, $resource, $update) = @_;

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
    $resource->{status} //= 'active';
    $resource->{administrative} //= 0;
    $resource->{is_pbx_pilot} //= 0;
    $resource->{profile_set}{id} = delete $resource->{profile_set_id};
    $resource->{profile}{id} = delete $resource->{profile_id};
    my $subscriber_id = $resource->{id} // 0;

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

    my $customer = $self->get_customer($c, $resource->{customer_id});
    return unless($customer);
    if(!$update && defined $customer->max_subscribers && $customer->voip_subscribers->search({ 
            status => { '!=' => 'terminated' },
        })->count >= $customer->max_subscribers) {
        
        $self->error($c, HTTP_FORBIDDEN, "Maximum number of subscribers reached.");
        return;
    }

    my $pilot;
    if($customer->get_column('product_class') eq 'pbxaccount') {
        $pilot = $customer->voip_subscribers->search({
            'provisioning_voip_subscriber.is_pbx_pilot' => 1,
        },{
            join => 'provisioning_voip_subscriber',
        })->first;

        if($pilot && $self->is_true($resource->{is_pbx_pilot}) && $pilot->id != $subscriber_id) {
            $c->log->error("failed to create subscriber, contract_id " . $customer->id . " already has pbx pilot subscriber");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Customer already has a pbx pilot subscriber.");
            return;
        }
        elsif(!$pilot && !$self->is_true($resource->{is_pbx_pilot})) {
            $c->log->error("failed to create subscriber, contract_id " . $customer->id . " has no pbx pilot subscriber and is_pbx_pilot is set");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Customer has no pbx pilot subscriber yet and is_pbx_pilot is not set.");
            return;
        }
    }


    my $preferences = {};
    my $admin = 0;
    unless($customer->get_column('product_class') eq 'pbxaccount') {
        for my $pref(qw/is_pbx_group pbx_group_id pbx_extension pbx_hunt_policy pbx_hunt_timeout is_pbx_pilot/) {
            delete $resource->{$pref};
        }
        $admin = $resource->{admin} // 0;
    } elsif($c->config->{features}->{cloudpbx}) {
        my $subs = $c->model('DB')->resultset('voip_subscribers')->search({
            contract_id => $customer->id,
            status => { '!=' => 'terminated' },
            'provisioning_voip_subscriber.is_pbx_group' => 0,
        }, {
            join => 'provisioning_voip_subscriber',
        });

        if($pilot && $pilot->id != $subscriber_id) {
            unless($resource->{pbx_extension}) {
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "A pbx_extension is required if customer is PBX and pilot subscriber exists.");
                return;
            }
            $resource->{e164}->{cc} = $pilot->primary_number->cc;
            $resource->{e164}->{ac} = $pilot->primary_number->ac // '';
            $resource->{e164}->{sn} = $pilot->primary_number->sn . $resource->{pbx_extension};

            unless($self->is_true($resource->{is_pbx_group})) {
                unless($resource->{pbx_group_id}) {
                    $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "A pbx_group_id is required if customer is PBX and pilot subscriber exists.");
                    return;
                }
                my $group_subscriber = $c->model('DB')->resultset('voip_subscribers')->find({
                    id => $resource->{pbx_group_id},
                    contract_id => $resource->{customer_id},
                    'provisioning_voip_subscriber.is_pbx_group' => 1,
                },{
                    join => 'provisioning_voip_subscriber',
                });
                unless($group_subscriber) {
                    $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid pbx_group_id, does not exist for this contract.");
                    return;
                }
            }
        }

        $preferences->{shared_buddylist_visibility} = 1;
        $preferences->{display_name} = $resource->{display_name}
            if(defined $resource->{display_name});

        my $default_sound_set = $customer->voip_sound_sets
            ->search({ contract_default => 1 })->first;
        if($default_sound_set) {
            $preferences->{contract_sound_set} = $default_sound_set->id;
        }

        # TODO: if we edit the primary of the pilot, will we not get the old primary number here?
        my $base_number = $pilot ? $pilot->primary_number : undef;
        if($base_number) {
            $preferences->{cloud_pbx_base_cli} = $base_number->cc . ($base_number->ac // '') . $base_number->sn;
        }
    }
    if(exists $resource->{external_id}) {
        $preferences->{ext_subscriber_id} = $resource->{external_id};
    }
    if(defined $customer->external_id) {
        $preferences->{ext_contract_id} = $customer->external_id;
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
    if($update) {
        unless($subscriber) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Subscriber does not exist.");
            return;
        }
    } else {
        if($subscriber) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Subscriber already exists.");
            return;
        }
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
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid parameter 'alias_numbers', must be hash or array of hashes.");
        return;
    }

    # TODO: handle status != active

    my $r = {
        resource => $resource,
        customer => $customer,
        alias_numbers => $alias_numbers,
        preferences => $preferences,
    };

    return $r;
}

sub update_item {
    my ($self, $c, $item, $full_resource, $resource, $form) = @_;

    my $subscriber = $item;
    my $customer = $full_resource->{customer};
    my $alias_numbers = $full_resource->{alias_numbers};
    my $preferences = $full_resource->{preferences};


    if($subscriber->provisioning_voip_subscriber->is_pbx_pilot && !$self->is_true($resource->{is_pbx_pilot})) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Cannot revoke is_pbx_pilot status from a subscriber.");
        return;
    }


    if($subscriber->status ne $resource->{status}) {
        if($resource->{status} eq 'locked') {
            $resource->{lock} = 4;
        } elsif($subscriber->status eq 'locked' && $resource->{status} eq 'active') {
            $resource->{lock} ||= 0;
        } elsif($resource->{status} eq 'terminated') {
            try {
                NGCP::Panel::Utils::Subscriber::terminate(c => $c, subscriber => $subscriber);
            } catch($e) {
                $c->log->error("failed to terminate subscriber id ".$subscriber->id);
                $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to terminate subscriber");
            }
            return;
        }
    }
    if(defined $resource->{lock}) {
        try {
            NGCP::Panel::Utils::Subscriber::lock_provisoning_voip_subscriber(
                c => $c,
                prov_subscriber => $subscriber->provisioning_voip_subscriber,
                level => $resource->{lock},
            );
        } catch($e) {
            $c->log->error("failed to lock subscriber id ".$subscriber->id." with level ".$resource->{lock});
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to update subscriber lock");
            return;
        };
    }

    my ($profile_set, $profile);
    if($resource->{profile_set}{id}) {
        my $profile_set_rs = $c->model('DB')->resultset('voip_subscriber_profile_sets');
        if($c->user->roles eq "admin") {
        } elsif($c->user->roles eq "reseller") {
            $profile_set_rs = $profile_set_rs->search({
                reseller_id => $c->user->reseller_id,
            });
        }

        $profile_set = $profile_set_rs->find($resource->{profile_set}{id});
        unless($profile_set) {
            $c->log->error("invalid subscriber profile set id '" . $resource->{profile_set}{id} . "'");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Invalid profile_set_id parameter");
            return;
        }
    }

    if($profile_set && $resource->{profile}{id}) {
        $profile = $profile_set->voip_subscriber_profiles->find({
            id => $resource->{profile}{id},
        });
    }
    if($profile_set && !$profile) {
        $profile = $profile_set->voip_subscriber_profiles->find({
            set_default => 1,
        });
    }

    # if the profile changed, clear any preferences which are not in the new profile
    if($subscriber->provisioning_voip_subscriber->voip_subscriber_profile) {
        my %old_profile_attributes = map { $_ => 1 }
            $subscriber->provisioning_voip_subscriber->voip_subscriber_profile
            ->profile_attributes->get_column('attribute_id')->all;
        if($profile) {
            foreach my $attr_id($profile->profile_attributes->get_column('attribute_id')->all) {
                delete $old_profile_attributes{$attr_id};
            }
        }
        if(keys %old_profile_attributes) {
            my $cfs = $c->model('DB')->resultset('voip_preferences')->search({
                id => { -in => [ keys %old_profile_attributes ] },
                attribute => { -in => [qw/cfu cfb cft cfna/] },
            });
            $subscriber->provisioning_voip_subscriber->voip_usr_preferences->search({
                attribute_id => { -in => [ keys %old_profile_attributes ] },
            })->delete;
            $subscriber->provisioning_voip_subscriber->voip_cf_mappings->search({
                type => { -in => [ map { $_->attribute } $cfs->all ] },
            })->delete;
        }
    }

    if($resource->{email}) {
        my $contact = $subscriber->contact;
        if($contact && $contact->email ne $resource->{email}) {
            $contact->update({
                email => $resource->{email},
            });
        } elsif(!$contact) {
            $contact = $c->model('DB')->resultset('contacts')->create({
                reseller_id => $subscriber->contract->contact->reseller_id,
                email => $resource->{email},
            });
        } # else old email == new email, nothing to do
        $resource->{contact_id} = $contact->id;
    } elsif($subscriber->contact) {
        $subscriber->contact->delete;
        $resource->{contact_id} = undef; # mark for clearance
    }
    delete $resource->{email};

    NGCP::Panel::Utils::Subscriber::update_subscriber_numbers(
        schema => $c->model('DB'),
        primary_number => $resource->{e164},
        alias_numbers => $alias_numbers,
        reseller_id => $customer->contact->reseller_id,
        subscriber_id => $subscriber->id,
    );

    my $billing_res = {
        external_id => $resource->{external_id},
        status => $resource->{status},
        contact_id => $resource->{contact_id},
    };
    my $provisioning_res = {
        password => $resource->{password},
        webusername => $resource->{webusername},
        webpassword => $resource->{webpassword},
        admin => $resource->{administrative} // 0,
        is_pbx_pilot => $resource->{is_pbx_pilot} // 0,
        is_pbx_group => $resource->{is_pbx_group} // 0,
        pbx_group_id => $resource->{pbx_group_id},
        modify_timestamp => NGCP::Panel::Utils::DateTime::current_local,
        profile_set_id => $profile_set ? $profile_set->id : undef,
        profile_id => $profile ? $profile->id : undef,
    };
    if($self->is_true($resource->{is_pbx_group})) {
        $provisioning_res->{pbx_hunt_policy} = $resource->{pbx_hunt_policy};
        $provisioning_res->{pbx_hunt_timeout} = $resource->{pbx_hunt_timeout};
        $provisioning_res->{pbx_group_id} = undef;
    }

    $subscriber->update($billing_res);
    $subscriber->provisioning_voip_subscriber->update($provisioning_res);
    $subscriber->discard_changes;
    NGCP::Panel::Utils::Subscriber::update_preferences(
        c => $c, 
        prov_subscriber => $subscriber->provisioning_voip_subscriber,
        preferences => $preferences,
    );

    # TODO: status handling (termination, ...)

    return $subscriber;
}

1;
# vim: set tabstop=4 expandtab:
