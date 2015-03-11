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
use NGCP::Panel::Utils::Events;

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
    my %resource = %{ merge($bill_resource, $prov_resource) };
    $resource{administrative} = delete $resource{admin};

    unless($customer->get_column('product_class') eq 'pbxaccount') {
        delete $resource{is_pbx_group};
        delete $resource{is_pbx_pilot};
        delete $resource{pbx_extension};
    }
    unless($self->is_true($resource{is_pbx_group})) {
        delete $resource{pbx_hunt_policy};
        delete $resource{cloud_pbx_hunt_policy};
        delete $resource{pbx_hunt_timeout};
        delete $resource{cloud_pbx_hunt_timeout};
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

    if($customer->get_column('product_class') eq 'pbxaccount') {
        $resource{pbx_group_ids} = [];
        foreach my $group($item->provisioning_voip_subscriber->voip_pbx_groups->all) {
            push @{ $resource{pbx_group_ids} }, int($group->group->voip_subscriber->id);
        }
        if($item->provisioning_voip_subscriber->is_pbx_group) {
            $resource{pbx_groupmember_ids} = [];
            foreach my $member($item->provisioning_voip_subscriber->voip_pbx_group_members->all) {
                push @{ $resource{pbx_groupmember_ids} }, int($member->subscriber->voip_subscriber->id);
            }
        }
    }

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
        #cast to Numeric accordingly to the form field type and customer note in the ticket #10313
        $resource{lock} = 0 + $pref->first->value;
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
            Data::HAL::Link->new(relation => 'ngcp:callforwards', href => sprintf("/api/callforwards/%d", $item->id)),
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
    my ($self, $c, $schema, $resource, $item) = @_;
    
    my @groups = ();
    my @groupmembers = ();
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
    my $subscriber_id = $item ? $item->id : 0;

    if(exists $resource->{alias_numbers} && ref $resource->{alias_numbers} ne "ARRAY") {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid alias_numbers parameter, must be array.");
        return;
    }
    $resource->{alias_numbers} = [ map {{ e164 => $_ }} @{ $resource->{alias_numbers} // [] } ];

    my $form = $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        resource => $resource,
        form => $form,
    );

    unless($domain) {
        $domain = $c->model('DB')->resultset('domains')->search({'me.id' => $resource->{domain_id}});
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
    if(!$item && defined $customer->max_subscribers && $customer->voip_subscribers->search({ 
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
        for my $pref(qw/is_pbx_group pbx_extension pbx_hunt_policy pbx_hunt_timeout is_pbx_pilot/) {
            delete $resource->{$pref};
        }
        $admin = $resource->{admin} // 0;
    } elsif($c->config->{features}->{cloudpbx}) {
        $preferences->{cloud_pbx} = 1;
        my $subs = $c->model('DB')->resultset('voip_subscribers')->search({
            contract_id => $customer->id,
            status => { '!=' => 'terminated' },
            'provisioning_voip_subscriber.is_pbx_group' => 0,
        }, {
            join => 'provisioning_voip_subscriber',
        });

        if($pilot && $pilot->id != $subscriber_id) {
            unless(defined $resource->{pbx_extension}) {
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "A pbx_extension is required if customer is PBX and pilot subscriber exists.");
                return;
            }

            my $ext_rs = $pilot->contract->voip_subscribers->search({
                'provisioning_voip_subscriber.pbx_extension' => $resource->{pbx_extension},
            },{
                join => 'provisioning_voip_subscriber',
            });

            if($ext_rs->first && $ext_rs->first->id != $subscriber_id) {
                $c->log->error("trying to add pbx_extension to contract id " . $pilot->contract_id . ", which is already in use by subscriber id " . $ext_rs->first->id);
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "The pbx_extension already exists for this customer.");
                return;
            }

            unless($pilot->primary_number) {
                $c->log->error("trying to add pbx_extension to contract id " . $pilot->contract_id . " without having a primary number on pilot subscriber id  " . $pilot->id);
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "The pilot subscriber does not have a primary number.");
                return;
            }

            $resource->{e164}->{cc} = $pilot->primary_number->cc;
            $resource->{e164}->{ac} = $pilot->primary_number->ac // '';
            $resource->{e164}->{sn} = $pilot->primary_number->sn . $resource->{pbx_extension};

            unless($self->is_true($resource->{is_pbx_group})) {
                if(exists $resource->{pbx_group_ids}) {
                    unless(ref $resource->{pbx_group_ids} eq "ARRAY") {
                        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid pbx_group_ids parameter, must be an array.");
                        return;
                    }
                    foreach my $group_id(@{ $resource->{pbx_group_ids} }) {
                        my $group_subscriber = $c->model('DB')->resultset('voip_subscribers')->find({
                            id => $group_id,
                            contract_id => $resource->{customer_id},
                            'provisioning_voip_subscriber.is_pbx_group' => 1,
                        },{
                            join => 'provisioning_voip_subscriber',
                        });
                        unless($group_subscriber) {
                            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid id '$group_id' in pbx_group_ids, does not exist for this customer.");
                            return;
                        }
                        push @groups, $group_subscriber;
                    }
                }
            } else {
                if(exists $resource->{pbx_groupmember_ids}) {
                    if(ref $resource->{pbx_groupmember_ids} eq "") {
                        $resource->{pbx_groupmember_ids} = [ $resource->{pbx_groupmember_ids} ];
                    }
                    unless(ref $resource->{pbx_groupmember_ids} eq "ARRAY") {
                        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid pbx_groupmember_ids parameter, must be an array.");
                        return;
                    }
                    foreach my $sub_id(@{ $resource->{pbx_groupmember_ids} }) {
                        my $group_subscriber = $c->model('DB')->resultset('voip_subscribers')->find({
                            id => $sub_id,
                            contract_id => $resource->{customer_id},
                            'provisioning_voip_subscriber.is_pbx_group' => 0,
                        },{
                            join => 'provisioning_voip_subscriber',
                        });
                        unless($group_subscriber) {
                            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid id '$sub_id' in pbx_groupmember_ids, does not exist for this customer.");
                            return;
                        }
                        push @groupmembers, $group_subscriber;
                    }
                }
            }
        }

        if($self->is_true($resource->{is_pbx_group})) {
            $preferences->{cloud_pbx_hunt_policy}  = $resource->{cloud_pbx_hunt_policy};
            $preferences->{cloud_pbx_hunt_timeout} = $resource->{cloud_pbx_hunt_timeout};
            $preferences->{cloud_pbx_hunt_policy}  //= $resource->{pbx_hunt_policy};
            $preferences->{cloud_pbx_hunt_timeout} //= $resource->{pbx_hunt_timeout};
        }
        $preferences->{cloud_pbx_ext} = $resource->{pbx_extension};
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
    if($item) { # update
        unless($subscriber) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Subscriber with this username does not exist in the domain.");
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
            push @{ $alias_numbers }, $num;
        }
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
        groups => \@groups,
        groupmembers => \@groupmembers,
    };

    return $r;
}

sub update_item {
    my ($self, $c, $schema, $item, $full_resource, $resource, $form) = @_;

    my $subscriber = $item;
    my $customer = $full_resource->{customer};
    my $alias_numbers = $full_resource->{alias_numbers};
    my $preferences = $full_resource->{preferences};
    my $groups = $full_resource->{groups};
    my $groupmembers = $full_resource->{groupmembers};
    my $prov_subscriber = $subscriber->provisioning_voip_subscriber;

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
                return $subscriber;
            } catch($e) {
                $c->log->error("failed to terminate subscriber id ".$subscriber->id);
                $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to terminate subscriber");
                return;
            }
        }
    }
    try {
        NGCP::Panel::Utils::Subscriber::lock_provisoning_voip_subscriber(
            c => $c,
            prov_subscriber => $subscriber->provisioning_voip_subscriber,
            level => $resource->{lock} || 0,
        );
    } catch($e) {
        $c->log->error("failed to lock subscriber id ".$subscriber->id." with level ".$resource->{lock});
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to update subscriber lock");
        return;
    };

    my ($profile_set, $profile);
    if($resource->{profile_set}{id}) {
        my $profile_set_rs = $schema->resultset('voip_subscriber_profile_sets');
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
    if($prov_subscriber->voip_subscriber_profile) {
        my %old_profile_attributes = map { $_ => 1 }
            $prov_subscriber->voip_subscriber_profile
            ->profile_attributes->get_column('attribute_id')->all;
        if($profile) {
            foreach my $attr_id($profile->profile_attributes->get_column('attribute_id')->all) {
                delete $old_profile_attributes{$attr_id};
            }
        }
        if(keys %old_profile_attributes) {
            my $cfs = $schema->resultset('voip_preferences')->search({
                id => { -in => [ keys %old_profile_attributes ] },
                attribute => { -in => [qw/cfu cfb cft cfna/] },
            });
            $prov_subscriber->voip_usr_preferences->search({
                attribute_id => { -in => [ keys %old_profile_attributes ] },
            })->delete;
            $prov_subscriber->voip_cf_mappings->search({
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
            $contact = $schema->resultset('contacts')->create({
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
        c => $c,
        schema => $schema,
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
        modify_timestamp => NGCP::Panel::Utils::DateTime::current_local,
        profile_set_id => $profile_set ? $profile_set->id : undef,
        profile_id => $profile ? $profile->id : undef,
        pbx_extension => $resource->{pbx_extension},
    };
    if($self->is_true($resource->{is_pbx_group})) {
        $provisioning_res->{pbx_hunt_policy} = $resource->{pbx_hunt_policy};
        $provisioning_res->{pbx_hunt_timeout} = $resource->{pbx_hunt_timeout};
        NGCP::Panel::Utils::Subscriber::update_subscriber_pbx_policy(
            c => $c, 
            prov_subscriber => $prov_subscriber,
            'values'   => {
                cloud_pbx_hunt_policy  => $resource->{cloud_pbx_hunt_policy} // $resource->{pbx_hunt_policy},
                cloud_pbx_hunt_timeout => $resource->{cloud_pbx_hunt_policy} // $resource->{pbx_hunt_timeout},
            }
        );
    }
    my $old_profile = $prov_subscriber->profile_id;

    $subscriber->update($billing_res);
    $subscriber->discard_changes;
    $prov_subscriber->update($provisioning_res);
    $prov_subscriber->discard_changes;

    if(($prov_subscriber->profile_id // 0) != ($old_profile // 0)) {
        my $type;
        if(defined $prov_subscriber->profile_id && defined $old_profile) {
            $type = "update_profile";
        } elsif(defined $prov_subscriber->profile_id) {
            $type = "start_profile";
        } else {
            $type = "end_profile";
        }
        NGCP::Panel::Utils::Events::insert(
            c => $c, schema => $schema, subscriber => $subscriber,
            type => $type, old => $old_profile, new => $prov_subscriber->profile_id
        );
    }

    NGCP::Panel::Utils::Subscriber::update_preferences(
        c => $c, 
        prov_subscriber => $prov_subscriber,
        preferences => $preferences,
    );

    my @old_groups = $prov_subscriber->voip_pbx_groups->get_column('group_id')->all;
    my @new_groups = ();
    foreach my $group(@{ $groups }) {
        push @new_groups, $group->provisioning_voip_subscriber->id;
        unless(grep { $group->provisioning_voip_subscriber->id eq $_ } @old_groups) {
            $prov_subscriber->voip_pbx_groups->create({
                group_id => $group->provisioning_voip_subscriber->id,
            });
            NGCP::Panel::Utils::Subscriber::update_pbx_group_prefs(
                c => $c,
                schema => $schema,
                old_group_id => undef,
                new_group_id => $group->id,
                username => $subscriber->username,
                domain => $subscriber->domain->domain,
                group_rs => $schema->resultset('voip_subscribers')->search({
                    contract_id => $customer->id,
                    status => { '!=' => 'terminated' },
                }),
            );
        }
    }
    foreach my $group_id(@old_groups) {
        # remove subscriber from group if not there anymore
        unless(grep { $group_id eq $_ } @new_groups) {
            my $group = $schema->resultset('provisioning_voip_subscribers')->find($group_id);
            NGCP::Panel::Utils::Subscriber::update_pbx_group_prefs(
                c => $c,
                schema => $schema,
                old_group_id => $group->voip_subscriber->id,
                new_group_id => undef,
                username => $subscriber->username,
                domain => $subscriber->domain->domain,
                group_rs => $schema->resultset('voip_subscribers')->search({
                    contract_id => $customer->id,
                    status => { '!=' => 'terminated' },
                }),
            );
            $prov_subscriber->voip_pbx_groups->search({
                group_id => $group_id,
                subscriber_id => $prov_subscriber->id,
            })->delete;
        }
    }

    my @old_members = $prov_subscriber->voip_pbx_group_members->get_column('subscriber_id')->all;
    my @new_members = ();
    my $grp_pref_rs = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
        c => $c, attribute => 'cloud_pbx_hunt_group', 
        prov_subscriber => $prov_subscriber,
    );
    foreach my $member(@{ $groupmembers }) {
        my $uri = 'sip:' . $member->username . '@' . $member->domain->domain;
        push @new_members, $member->provisioning_voip_subscriber->id;
        unless($prov_subscriber->voip_pbx_group_members->find({
            subscriber_id => $member->provisioning_voip_subscriber->id,
        })) {
            $prov_subscriber->voip_pbx_group_members->create({
                subscriber_id => $member->provisioning_voip_subscriber->id,
            });
            $grp_pref_rs->create({ value => $uri });
        }
    }
    foreach my $old_member_id(@old_members) {
        unless(grep { $old_member_id eq $_ } @new_members) {
            my $grp = $prov_subscriber->voip_pbx_group_members
                ->find({ subscriber_id => $old_member_id });
            my $oldsub = $grp->subscriber;
            $grp->delete;
            $grp_pref_rs->find(
                { value => 'sip:' . $oldsub->username . '@' . $oldsub->domain->domain }
            )->delete;
        }
    }

    return $subscriber;
}

1;
# vim: set tabstop=4 expandtab:
