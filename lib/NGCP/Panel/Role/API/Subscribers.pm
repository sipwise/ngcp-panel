package NGCP::Panel::Role::API::Subscribers;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use JSON::Types;
use Test::More;
use POSIX qw(ceil);
use NGCP::Panel::Form;
use NGCP::Panel::Utils::XMLDispatcher;
use NGCP::Panel::Utils::Prosody;
use NGCP::Panel::Utils::Subscriber;
use NGCP::Panel::Utils::Events;
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Contract qw();
use NGCP::Panel::Utils::Encryption qw();
use NGCP::Panel::Utils::Auth qw();

sub resource_name{
    return 'subscribers';
}

sub dispatch_path{
    return '/api/subscribers/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-subscribers';
}

sub get_form {
    my ($self, $c) = @_;

    if ($c->user->roles eq "admin" || $c->user->roles eq "reseller" ||
        $c->user->roles eq "ccareadmin" || $c->user->roles eq "ccare") {
        return (NGCP::Panel::Form::get("NGCP::Panel::Form::Subscriber::SubscriberAPI", $c));
    } elsif ($c->user->roles eq "subscriberadmin" || $c->user->roles eq "subscriber") {
        return (NGCP::Panel::Form::get("NGCP::Panel::Form::Subscriber::SubscriberSubAdminAPI", $c));
    }
}

sub resource_from_item {
    my ($self, $c, $item, $form) = @_;
    my $pref;

    my $bill_resource = { $item->get_inflated_columns };
    my $prov_resource = { $item->provisioning_voip_subscriber->get_inflated_columns };
    my $customer = $self->get_customer($c, $item->contract_id);
    delete $prov_resource->{domain_id};
    delete $prov_resource->{account_id};
    my %resource = %{ merge($bill_resource, $prov_resource) };
    $resource{administrative} = delete $resource{admin};

    unless($customer->product->class eq 'pbxaccount') {
        delete $resource{is_pbx_group};
        delete $resource{is_pbx_pilot};
        delete $resource{pbx_extension};
    }
    unless(is_true($resource{is_pbx_group})) {
        delete $resource{pbx_hunt_policy};
        delete $resource{cloud_pbx_hunt_policy};
        delete $resource{pbx_hunt_timeout};
        delete $resource{cloud_pbx_hunt_timeout};
    }
    delete $resource{contact_id};
    if($item->contact) {
        $resource{email} = $item->contact->email;
        $resource{timezone} = $item->contact->timezone;
    } else {
        $resource{email} = undef;
        $resource{timezone} = undef;
    }
    my $sippassword = $resource{password};
    my $webpassword = $resource{webpassword};
    # if the webpassword length is 54 or 56 chars and it contains $,
    # we assume that the password is encrypted,
    # as we do not have an explicit flag for the password field
    # whether it's encrypted or not, there is a chance that
    # if somebody manages to create a 54 chars password containing
    # '$', it will be detected as false positive, but
    #  - all webpasswords from mr8.5+ are meant to be encrypted
    #  - in case of the false positive result, the worse that happens
    #    the password is not returned to the user in plain-text
    if ($change_passwords &&
        $resource{webpassword} && (length $resource{webpassword}) =~ /^(54|56)$/ &&
        $resource{webpassword} =~ /\$/) {
            delete $resource{webpassword};
    }
    if(!$form){
        ($form) = $self->get_form($c);
    }
    last unless $self->validate_form(
        c => $c,
        resource => \%resource,
        form => $form,
        run => 0,
    );
    $resource{_password} = $sippassword;
    $resource{_webpassword} = $webpassword;

    if($customer->product->class eq 'pbxaccount') {
        if ($resource{administrative} == 1) {
            $resource{ext_range_min} = $customer->voip_contract_preferences->search(
                {
                    'attribute.attribute' => 'ext_range_min'
                },
                {
                    join => 'attribute',
                }
            )->get_column('value')->first;

            $resource{ext_range_max} = $customer->voip_contract_preferences->search(
                {
                    'attribute.attribute' => 'ext_range_max'
                },
                {
                    join => 'attribute',
                }
            )->get_column('value')->first;
        }
        $resource{pbx_group_ids} = [];
        foreach my $group($item->provisioning_voip_subscriber->voip_pbx_groups->search_rs(undef,{'order_by' => 'me.id'})->all) {
            push @{ $resource{pbx_group_ids} }, int($group->group->voip_subscriber->id);
        }
        if($item->provisioning_voip_subscriber->is_pbx_group) {
            $resource{pbx_groupmember_ids} = [];
            foreach my $member($item->provisioning_voip_subscriber->voip_pbx_group_members->search_rs(undef,{'order_by' => 'me.id'})->all) {
                push @{ $resource{pbx_groupmember_ids} }, int($member->subscriber->voip_subscriber->id);
            }
        }
    }

    if($item->primary_number) {
        $resource{primary_number}->{cc} = $item->primary_number->cc;
        $resource{primary_number}->{ac} = $item->primary_number->ac;
        $resource{primary_number}->{sn} = $item->primary_number->sn;
        $resource{primary_number}->{number_id} = int($item->primary_number->id);
    }
    if($item->voip_numbers->count) {
         $resource{alias_numbers} = [];
        foreach my $n($item->voip_numbers->all) {
            my $alias = {
                cc => $n->cc,
                ac => $n->ac,
                sn => $n->sn,
                number_id => int($n->id),
            };
            next if($resource{primary_number} &&
               compare($resource{primary_number}, $alias));
            if (defined $n->voip_dbalias) {
                $alias->{is_devid} = bool $n->voip_dbalias->is_devid;
            }
            push @{ $resource{alias_numbers} }, $alias;
        }
    }

    $pref = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
        c => $c, attribute => 'display_name',
        prov_subscriber => $item->provisioning_voip_subscriber);
    if($pref->first && $pref->first->value) {
        $resource{display_name} = $pref->first->value;
    } else {
        $resource{display_name} = undef;
    }

    $resource{id} = int($item->id);
    $resource{domain} = $item->domain->domain;

    # don't leak internal info to subscribers via API for those fields
    # not filtered via forms
    my $contract_id = int(delete $resource{contract_id});
    if ($c->user->roles eq "admin" || $c->user->roles eq "reseller" ||
        $c->user->roles eq "ccareadmin" || $c->user->roles eq "ccare") {
        $resource{customer_id} = $contract_id;
        $resource{uuid} = $item->uuid;

        my $pref = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
            c => $c, attribute => 'lock',
            prov_subscriber => $item->provisioning_voip_subscriber);
        $resource{lock} = 0;
        if($pref->first and length($pref->first->value) > 0) {
            #cast to Numeric accordingly to the form field type and customer note in the ticket #10313
            $resource{lock} = $pref->first->value;
        }else{
            $resource{lock} = undef;
        }
        if ($c->user->show_passwords) {
            foreach my $k(qw/password webpassword/) {
                eval {
                    if (not NGCP::Panel::Utils::Auth::is_salted_hash($resource{$k})) {
                        $resource{'_' . $k} = NGCP::Panel::Utils::Encryption::encrypt_rsa($c,$resource{$k});
                    } else {
                        delete $resource{'_' . $k};
                    }
                };
                if ($@) {
                    $c->log->error("Failed to encrypt $k: " . $@);
                    delete $resource{'_' . $k};
                }
            }
        } else {
            foreach my $k(qw/password webpassword/) {
                delete $resource{'_' . $k};
            }
        }
    } else {
        if ($c->user->roles eq "subscriberadmin" && !$self->subscriberadmin_write_access($c)) {
            # fields we never want to see
            foreach my $k(qw/domain_id status profile_id profile_set_id external_id/) {
                delete $resource{$k};
            }

            # TODO: make custom filtering configurable!
            foreach my $k (qw/password webpassword/) {
                delete $resource{'_' . $k};
            }
        }
        if ($c->user->roles eq "subscriberadmin") {
            $resource{customer_id} = $contract_id;
            if ($item->id != $c->user->voip_subscriber->id) {
                if (!$c->config->{security}->{password_sip_expose_subadmin}) {
                    delete $resource{_password};
                }
                if (!$c->config->{security}->{password_web_expose_subadmin}) {
                    delete $resource{_webpassword};
                }
            }
        }
    }

    return \%resource;
}

sub hal_from_item {
    my ($self, $c, $item, $resource, $form) = @_;
    my $is_sub = 1;
    if ($c->user->roles eq "admin" || $c->user->roles eq "reseller" ||
        $c->user->roles eq "ccareadmin" || $c->user->roles eq "ccare") {
        $is_sub = 0;
    }
    my $is_subadm = 1;
    if($c->user->roles eq "subscriber") {
        $is_subadm = 0;
    }

    delete $resource->{password};
    delete $resource->{webpassword};
    $resource->{password} = delete $resource->{_password} if exists $resource->{_password};
    $resource->{webpassword} = delete $resource->{_webpassword} if exists $resource->{_webpassword};

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

            # available also to subscribers
            Data::HAL::Link->new(relation => 'ngcp:subscriberpreferences', href => sprintf("/api/subscriberpreferences/%d", $item->id)),
            Data::HAL::Link->new(relation => 'ngcp:voicemailsettings', href => sprintf("/api/voicemailsettings/%d", $item->id)),
            Data::HAL::Link->new(relation => 'ngcp:reminders', href => sprintf("/api/reminders/?subscriber_id=%d", $item->id)),
            Data::HAL::Link->new(relation => 'ngcp:callforwards', href => sprintf("/api/callforwards/%d", $item->id)),

            # only available to admins/resellers
            ($is_sub ? () : (
                ($item->provisioning_voip_subscriber && $item->provisioning_voip_subscriber->profile_set_id) ? (Data::HAL::Link->new(relation => 'ngcp:subscriberprofilesets', href => sprintf("/api/subscriberprofilesets/%d", $item->provisioning_voip_subscriber->profile_set_id))) : (),
                ($item->provisioning_voip_subscriber && $item->provisioning_voip_subscriber->profile_id) ? (Data::HAL::Link->new(relation => 'ngcp:subscriberprofiles', href => sprintf("/api/subscriberprofiles/%d", $item->provisioning_voip_subscriber->profile_id))) : (),
                Data::HAL::Link->new(relation => 'ngcp:domains', href => sprintf("/api/domains/%d", $item->domain->id)),
                Data::HAL::Link->new(relation => 'ngcp:calls', href => sprintf("/api/calls/?subscriber_id=%d", $item->id)),
                Data::HAL::Link->new(relation => 'ngcp:subscriberregistrations', href => sprintf("/api/subscriberregistrations/?subscriber_id=%d", $item->id)),
                #Data::HAL::Link->new(relation => 'ngcp:trustedsources', href => sprintf("/api/trustedsources/%d", $item->contract->id)),
                $self->get_journal_relation_link($c, $item->id),
            )),
            # only available to admins/resellers/subscriberadmins
            (!$is_subadm ? () : (
                Data::HAL::Link->new(relation => 'ngcp:customers', href => sprintf("/api/customers/%d", $item->contract_id)),
            )),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $self->expand_fields($c, $resource);
    $hal->resource($resource);
    return $hal;
}

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs;
    $item_rs = $c->model('DB')->resultset('voip_subscribers')
        ->search({ 'me.status' => { '!=' => 'terminated' } });
    if ($c->user->roles eq "admin" || $c->user->roles eq "ccareadmin") {
        $item_rs = $item_rs->search(undef,
        {
            join => { 'contract' => 'contact' }, #for filters
        });
    } elsif ($c->user->roles eq "reseller" || $c->user->roles eq "ccare") {
        $item_rs = $item_rs->search({
            'contact.reseller_id' => $c->user->reseller_id,
        }, {
            join => { 'contract' => 'contact' },
        });
    } elsif ($c->user->roles eq "subscriberadmin") {
        $item_rs = $item_rs->search({
            'contract_id' => $c->user->account_id,
        });
    } elsif ($c->user->roles eq "subscriber") {
        $item_rs = $item_rs->search({
            #voip_subscriber is a provisioning.voip_subscribers relation
            #$c->user is provisioning.voip_subscribers, so we use ->voip_subscriber->id and compare to billing.voip-subscribers.
            'me.id' => $c->user->voip_subscriber->id,
        });
    } else {
        $self->error($c, HTTP_FORBIDDEN, "Invalid authentication role");
        return;
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

    my $customer_rs = NGCP::Panel::Utils::Contract::get_contract_rs(
        schema => $c->model('DB'),
        contract_id => $customer_id,
    );
    $customer_rs = $customer_rs->search({
            'contact.reseller_id' => { '-not' => undef },
            'me.id' => $customer_id,
        },{
            join => 'contact',
        });
    my @product_ids = map { $_->id; } $c->model('DB')->resultset('products')->search_rs({ 'class' => ['sipaccount','pbxaccount'] })->all;
    $customer_rs = $customer_rs->search({
        'product_id' => { -in => [ @product_ids ] },
    });
    if ($c->user->roles eq "admin" || $c->user->roles eq "ccareadmin") {
    } elsif($c->user->roles eq "reseller" || $c->user->roles eq "ccare") {
        $customer_rs = $customer_rs->search({
            'contact.reseller_id' => $c->user->reseller_id,
        });
    }
    my $customer = $customer_rs->first;
    unless($customer) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'customer_id', doesn't exist.");
        return;
    }
    return $customer;
}

sub prepare_resource {
    my ($self, $c, $schema, $resource, $item) = @_;

    return NGCP::Panel::Utils::Subscriber::prepare_resource(
        c => $c,
        schema => $c->model('DB'),
        resource => $resource,
        item => $item,
        err_code => sub {
            my ($code,$msg) = @_;
            $self->error($c, $code, $msg);
        },
        validate_code => sub {
            my ($r) = @_;
            my ($form) = $self->get_form($c);
            return $self->validate_form(
                c => $c,
                resource => $r,
                form => $form,
            );
        },
        getcustomer_code => sub {
            my ($cid) = @_;
            my $contract = $self->get_customer($c, $cid);
            NGCP::Panel::Utils::Contract::acquire_contract_rowlocks(
                schema => $c->model('DB'), contract_id => $contract->id) if $contract;
            return $contract;
        },
    );

}

sub update_item {
    my ($self, $c, $schema, $item, $full_resource, $resource, $form) = @_;

    return unless $self->check_write_access($c, $item->id);

    my $subscriber = $item;
    my $customer = $full_resource->{customer};
    my $alias_numbers = $full_resource->{alias_numbers};
    my $preferences = $full_resource->{preferences};
    my $groups = $full_resource->{groups};
    my $groupmembers = $full_resource->{groupmembers};
    my $prov_subscriber = $subscriber->provisioning_voip_subscriber;

    if($subscriber->provisioning_voip_subscriber->is_pbx_pilot && !is_true($resource->{is_pbx_pilot})) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Cannot revoke is_pbx_pilot status from a subscriber.");
        return;
    }

    if($resource->{customer_id} && ( $resource->{customer_id} != $subscriber->contract->id ) ){
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "customer_id can't be changed.");
        return;
    }

    if ($resource->{timezone} && !NGCP::Panel::Utils::DateTime::is_valid_timezone_name($resource->{timezone})) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "invalid timezone name.");
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
                $c->log->error("failed to terminate subscriber id ".$subscriber->id . ": $e");
                $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to terminate subscriber");
                return;
            }
        }
    }
    try {
        NGCP::Panel::Utils::Subscriber::lock_provisoning_voip_subscriber(
            c => $c,
            prov_subscriber => $prov_subscriber,
            level => $resource->{lock} || 0,
        );
    } catch($e) {
        $c->log->error("failed to lock subscriber id ".$subscriber->id." with level ".$resource->{lock});
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to update subscriber lock");
        return;
    };

    my ($error,$profile_set,$profile) = NGCP::Panel::Utils::Subscriber::check_profile_set_and_profile($c, $resource, $subscriber);
    if ($error) {
        $c->log->error($error->{error});
        $self->error($c, $error->{response_code}, $error->{description});
        return;
    }

    if($resource->{email} || $resource->{timezone}) {
        my $contact = $subscriber->contact;
        unless ($contact) {
            $contact = $schema->resultset('contacts')->create({
                reseller_id => $subscriber->contract->contact->reseller_id,
            });
        }
        if(not $contact->email or ($contact->email ne $resource->{email})) {
            $contact->update({
                email => $resource->{email},
            });
        }
        if(not $contact->timezone or ($contact->timezone ne $resource->{timezone})) {
            $contact->update({
                timezone => $resource->{timezone},
            });
        }
        $resource->{contact_id} = $contact->id;
    } elsif($subscriber->contact) {
        try {
            $c->log->debug("delete contact id ".$subscriber->contact->id);
            $subscriber->contact->delete;
        } catch($e) {
            $c->log->debug("contact still in use: ".$e);
        }
        $resource->{contact_id} = undef; # mark for clearance
    }
    delete $resource->{email};
    delete $resource->{timezone};

    my $aliases_before = NGCP::Panel::Utils::Events::get_aliases_snapshot(
        c => $c,
        schema => $schema,
        subscriber => $subscriber,
    );

    try {
        NGCP::Panel::Utils::Subscriber::update_subscriber_numbers(
            c => $c,
            schema => $schema,
            primary_number => $resource->{e164},
            alias_numbers => $alias_numbers,
            reseller_id => $customer->contact->reseller_id,
            subscriber_id => $subscriber->id,
        );
    } catch(DBIx::Class::Exception $e where { /Duplicate entry '([^']+)' for key 'number_idx'/ }) {
        $e =~ /Duplicate entry '([^']+)' for key 'number_idx'/;
        $c->log->error("failed to update subscriber, number " . $c->qs($1) . " already exists"); # TODO: user, message, trace, ...
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Number '" . $1 . "' already exists.", "Number already exists.");
        return;
    } catch($e where { /alias '([^']+)' already exists/ }) {
        $e =~ /alias '([^']+)' already exists/;
        $c->log->error("failed to update subscriber, alias " . $c->qs($1) . " already exists"); # TODO: user, message, trace, ...
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Number '" . $1 . "' already exists.", "Number already exists.");
        return;
    }

    my $billing_res = {
        external_id => $resource->{external_id},
        status => $resource->{status},
        contact_id => $resource->{contact_id},
    };

    if (exists $resource->{webpassword} and $NGCP::Panel::Utils::Auth::ENCRYPT_SUBSCRIBER_WEBPASSWORDS) {
        $resource->{webpassword} = NGCP::Panel::Utils::Auth::generate_salted_hash($resource->{webpassword});
    }

    my $provisioning_res = {
        webusername => $resource->{webusername},
        is_pbx_pilot => $resource->{is_pbx_pilot} // 0,
        is_pbx_group => $resource->{is_pbx_group} // 0,
        modify_timestamp => NGCP::Panel::Utils::DateTime::current_local,
        profile_set_id => $profile_set ? $profile_set->id : undef,
        profile_id => $profile ? $profile->id : undef,
        pbx_extension => $resource->{pbx_extension},
        $resource->{administrative} ? (admin => $resource->{administrative}) : (),
    };
    $provisioning_res->{password} = $resource->{password} if exists $resource->{password};
    $provisioning_res->{webpassword} = $resource->{webpassword} if exists $resource->{webpassword};
    if(is_true($resource->{is_pbx_group})) {
        $provisioning_res->{pbx_hunt_policy} = $resource->{pbx_hunt_policy};
        $provisioning_res->{pbx_hunt_timeout} = $resource->{pbx_hunt_timeout};
        NGCP::Panel::Utils::Subscriber::update_preferences(
            c => $c,
            prov_subscriber => $prov_subscriber,
            'preferences'   => {
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

    NGCP::Panel::Utils::Events::insert_profile_events(
        c => $c, schema => $schema, subscriber_id => $subscriber->id,
        old => $old_profile, new => $prov_subscriber->profile_id,
        %$aliases_before,
    );

    NGCP::Panel::Utils::Subscriber::update_preferences(
        c => $c,
        prov_subscriber => $prov_subscriber,
        preferences => $preferences,
    );

    NGCP::Panel::Utils::Subscriber::manage_pbx_groups(
        c            => $c,
        schema       => $schema,
        groups       => $groups,
        groupmembers => $groupmembers,
        customer     => $customer,
        subscriber   => $subscriber,
    );

    return $subscriber;
}

sub check_write_access {
    my ( $self, $c, $id ) = @_;

    if ($c->user->roles eq "admin" || $c->user->roles eq "reseller" ||
        $c->user->roles eq "ccareadmin" || $c->user->roles eq "ccare") {
            return 1;
    }
    elsif ($c->user->roles eq "subscriberadmin" && !$self->subscriberadmin_write_access($c)) {
        $self->error($c, HTTP_FORBIDDEN, "Read-only resource for authenticated role");
        return;
    }
    elsif($c->user->roles eq "subscriber") {
        if ( $id != $c->user->voip_subscriber->id ) {
            $self->error($c, HTTP_FORBIDDEN, "Read-only resource for authenticated role");
            return;
        }
    }
    return 1;
}

sub subscriberadmin_write_access {
    my($self,$c) = @_;
    if ( ( $c->config->{privileges}->{subscriberadmin}->{subscribers}
           && $c->config->{privileges}->{subscriberadmin}->{subscribers} =~/write/
         )
         ||
         ( $c->config->{features}->{cloudpbx} #user can disable pbx feature after some time of using it
           && $c->user->contract->product->class eq 'pbxaccount'
         )
        ) {
        return 1;
    }
    return 0;
}

1;
# vim: set tabstop=4 expandtab:
