package NGCP::Panel::Controller::Customer;
use Sipwise::Base;
use namespace::sweep;
BEGIN { extends 'Catalyst::Controller'; }
use NGCP::Panel::Utils::Contract;
use NGCP::Panel::Form::CustomerMonthlyFraud;
use NGCP::Panel::Form::CustomerDailyFraud;
use NGCP::Panel::Form::CustomerBalance;
use NGCP::Panel::Form::Customer::Subscriber;
use NGCP::Panel::Form::Customer::PbxAdminSubscriber;
use NGCP::Panel::Form::Customer::PbxExtensionSubscriber;
use NGCP::Panel::Form::Customer::PbxGroupBase;
use NGCP::Panel::Form::Customer::PbxGroup;
use NGCP::Panel::Form::Customer::PbxFieldDevice;
use NGCP::Panel::Form::Customer::PbxFieldDeviceSync;
use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::Navigation;
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Subscriber;
use Template;

=head1 NAME

NGCP::Panel::Controller::Customer - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) :AllowedRole(subscriberadmin) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub list_customer :Chained('/') :PathPart('customer') :CaptureArgs(0) {
    my ($self, $c) = @_;

    $c->stash->{contract_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => "#" },
        { name => "external_id", search => 1, title => "External #" },
        { name => "contact.reseller.name", search => 1, title => "Reseller" },
        { name => "contact.email", search => 1, title => "Contact Email" },
        { name => "billing_mappings.product.name", search => 1, title => "Product" },
        { name => "billing_mappings.billing_profile.name", search => 1, title => "Billing Profile" },
        { name => "status", search => 1, title => "Status" },
    ]);

    $c->stash(
        template => 'customer/list.tt'
    );
}

sub root :Chained('list_customer') :PathPart('') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
}

sub base :Chained('list_customer') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $contract_id) = @_;

    unless($contract_id && $contract_id->is_integer) {
         $c->flash(messages => [{type => 'error', text => 'Invalid contract id detected!'}]);
         $c->response->redirect($c->uri_for());
         return;
    }

    my $contract = $c->model('DB')->resultset('contracts')
        ->search('me.id' => $contract_id);
    if($c->user->roles eq 'reseller') {
        $contract = $contract->search({
            'contact.reseller_id' => $c->user->reseller_id,
        }, {
            join => 'contact',
        });
    } elsif($c->user->roles eq 'subscriberadmin') {
        $contract = $contract->search({
            'me.id' => $c->user->account_id,
        });
        unless($contract->count) {
            $c->log->error("unauthorized access of subscriber uuid '".$c->user->uuid."' to contract id '$contract_id'");
            $c->detach('/denied_page');
        }
    }

    my $stime = NGCP::Panel::Utils::DateTime::current_local()->truncate(to => 'month');
    my $etime = $stime->clone->add(months => 1);
    my $balance = $contract->first->contract_balances
        ->find({
            start => { '>=' => $stime },
            end => { '<' => $etime },
            });
    unless($balance) {
        try {
            NGCP::Panel::Utils::Contract::create_contract_balance(
                c => $c,
                profile => $contract->first->billing_mappings->search({
                    -and => [
                        -or => [
                            start_date => undef,
                            start_date => { '<=' => NGCP::Panel::Utils::DateTime::current_local },
                        ],
                        -or => [
                            end_date => undef,
                            end_date => { '>=' => NGCP::Panel::Utils::DateTime::current_local },
                        ]
                    ],
                },
                {
                    order_by => { -desc => 'start_time', -desc => 'id' }
                })->first->billing_profile,
                contract => $contract->first,
            );
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => "Failed to create contract balance.",
            );
            $c->response->redirect($c->uri_for());
            return;
        }
        $balance = $contract->first->contract_balances
            ->find({
                start => { '>=' => $stime },
                end => { '<' => $etime },
                });
    }

    my $contract_select_rs = NGCP::Panel::Utils::Contract::get_contract_rs(c => $c);
    $contract_select_rs = $contract_select_rs->search({
        'me.id' => $contract_id,
    });
    my $product_id = $contract_select_rs->search({'me.id' => $contract_id})->first->get_column('product_id');
    NGCP::Panel::Utils::Message->error(
        c => $c,
        error => "No product for customer contract id $contract_id found",
        desc  => "No product for this customer contract found.",
    ) unless($product_id);
    my $product = $c->model('DB')->resultset('products')->find($product_id);
    NGCP::Panel::Utils::Message->error(
        c => $c,
        error => "No product with id $product_id for customer contract id $contract_id found",
        desc  => "Invalid product id for this customer contract.",
    ) unless($product);

    $c->stash->{pbxgroup_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => "#" },
        { name => "name", search => 1, title => "Name" },
        { name => "extension", search => 1, title => "Extension" },
    ]);

    my $subs = NGCP::Panel::Utils::Subscriber::get_custom_subscriber_struct(
        c => $c,
        contract => $contract->first
    );
    $c->stash->{subscribers} = $subs->{subscribers};
    $c->stash->{pbx_groups} = $subs->{pbx_groups};

    my $field_devs = [ $c->model('DB')->resultset('autoprov_field_devices')->search({
        'provisioning_voip_subscriber.account_id' => $contract->first->id
    }, {
        join => 'provisioning_voip_subscriber'
    })->all ];
    $c->stash(pbx_devices => $field_devs);

    $c->stash(product => $product);
    $c->stash(balance => $balance);
    $c->stash(fraud => $contract->first->contract_fraud_preference);
    $c->stash(template => 'customer/details.tt'); 
    $c->stash(contract => $contract->first);
    $c->stash(contract_rs => $contract);
}

sub details :Chained('base') :PathPart('details') :Args(0) {
    my ($self, $c) = @_;

    $c->stash->{contact_hash} = { $c->stash->{contract}->contact->get_inflated_columns };
}

sub subscriber_create :Chained('base') :PathPart('subscriber/create') :Args(0) {
    my ($self, $c) = @_;

    my $pbx = 0; my $pbxadmin = 0;
    $pbx = 1 if $c->stash->{product}->class eq 'pbxaccount';
    my $form;
    my $posted = ($c->request->method eq 'POST');
    my $admin_subscribers = NGCP::Panel::Utils::Subscriber::get_admin_subscribers(
        voip_subscribers => $c->stash->{subscribers});

    if($c->config->{features}->{cloudpbx} && $pbx) {
        $c->stash(customer_id => $c->stash->{contract}->id);
        # we need to create an admin subscriber first
        unless(@{ $admin_subscribers }) {
            $pbxadmin = 1;
            $form = NGCP::Panel::Form::Customer::PbxAdminSubscriber->new(ctx => $c);
        } else {
            $form = NGCP::Panel::Form::Customer::PbxExtensionSubscriber->new(ctx => $c);
        }
    } else {
        $form = NGCP::Panel::Form::Customer::Subscriber->new;
    }

    my $params = {};
    $params = $params->merge($c->session->{created_objects});
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params,
    );
    my $fields = {
            'domain.create' => $c->uri_for('/domain/create'),
            'group.create' => $c->uri_for_action('/customer/pbx_group_create', $c->req->captures),
    };
    if($pbxadmin) {
        $fields->{'domain.create'} = $c->uri_for_action('/domain/create', 
            $c->stash->{contract}->contact->reseller_id, 'pbx');
    }
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => $fields,
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        my $billing_subscriber;
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                my $preferences = {};
                if($pbx && !$pbxadmin) {
                    my $admin = $admin_subscribers->[0];
                    $form->params->{domain}{id} = $admin->{domain_id};
                    # TODO: make DT selection multi-select capable
                    $form->params->{pbx_group_id} = $form->params->{group}{id};
                    delete $form->params->{group};
                    my $base_number = $admin->{primary_number};
                    if($base_number) {
                        $preferences->{cloud_pbx_base_cli} = $base_number->{cc} . $base_number->{ac} . $base_number->{sn};
                        if($form->params->{extension}) {
                            $form->params->{e164}{cc} = $base_number->{cc};
                            $form->params->{e164}{ac} = $base_number->{ac};
                            $form->params->{e164}{sn} = $base_number->{sn} . $form->params->{extension};
                        }
                    }
                }
                if($pbx) {
                    $preferences->{cloud_pbx} = 1;
                    # TODO: only if it's not a fax/conf extension:
                    $preferences->{shared_buddylist_visibility} = 1;
                    $preferences->{display_name} = $form->params->{display_name}
                        if($form->params->{display_name});
                }
                use Data::Printer; p $preferences;
                $billing_subscriber = NGCP::Panel::Utils::Subscriber::create_subscriber(
                    c => $c,
                    schema => $schema,
                    contract => $c->stash->{contract},
                    params => $form->params,
                    admin_default => $pbxadmin,
                    preferences => $preferences,
                );

                NGCP::Panel::Utils::Subscriber::update_pbx_group_prefs(
                    c => $c,
                    schema => $schema,
                    old_group_id => undef,
                    new_group_id => $form->params->{pbx_group_id},
                    username => $form->params->{username},
                    domain => $billing_subscriber->domain->domain,
                ) if($pbx && !$pbxadmin && $form->params->{pbx_group_id});
            });

            delete $c->session->{created_objects}->{domain};
            delete $c->session->{created_objects}->{group};
            $c->flash(messages => [{type => 'success', text => 'Subscriber successfully created.'}]);
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => "Failed to create subscriber.",
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, 
            $c->uri_for_action('/customer/details', [$c->stash->{contract}->id])
        );
    }

    $c->stash(create_flag => 1);
    $c->stash(form => $form)
}

sub edit_fraud :Chained('base') :PathPart('fraud/edit') :Args(1) {
    my ($self, $c, $type) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form;
    if($type eq "month") {
        $form = NGCP::Panel::Form::CustomerMonthlyFraud->new;
    } elsif($type eq "day") {
        $form = NGCP::Panel::Form::CustomerDailyFraud->new;
    } else {
        $c->flash(messages => [{type => 'error', text => "Invalid fraud interval '$type'!"}]);
        $c->response->redirect($c->uri_for_action("/customer/details", [$c->stash->{contract}->id]));
        return;
    }

    my $fraud_prefs = $c->stash->{fraud} ||
        $c->model('DB')->resultset('contract_fraud_preferences')
            ->new_result({ contract_id => $c->stash->{contract}->id});
    $form->process(
        posted => $posted,
        params => $c->request->params,
        action => $c->uri_for_action("/customer/edit_fraud", $c->stash->{contract}->id, $type),
        item => $fraud_prefs,
    );
    if($posted && $form->validated) {
        $c->flash(messages => [{type => 'success', text => 'Fraud settings successfully changed!'}]);
        $c->response->redirect($c->uri_for_action("/customer/details", [$c->stash->{contract}->id]));
        return;
    }

    $c->stash(close_target => $c->uri_for_action("/customer/details", [$c->stash->{contract}->id]));
    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
}

sub delete_fraud :Chained('base') :PathPart('fraud/delete') :Args(1) {
    my ($self, $c, $type) = @_;

    if($type eq "month") {
        $type = "interval";
    } elsif($type eq "day") {
        $type = "daily";
    } else {
        $c->flash(messages => [{type => 'error', text => "Invalid fraud interval '$type'!"}]);
        $c->response->redirect($c->uri_for_action("/customer/details", [$c->stash->{contract}->id]));
        return;
    }

    my $fraud_prefs = $c->stash->{fraud};
    if($fraud_prefs) {
        try {
            $fraud_prefs->update({
                "fraud_".$type."_limit" => undef,
                "fraud_".$type."_lock" => undef,
                "fraud_".$type."_notify" => undef,
            });
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => "Failed to clear fraud interval.",
            );
            $c->response->redirect($c->uri_for_action("/customer/details", [$c->stash->{contract}->id]));
            return;
        }
    }
    $c->flash(messages => [{type => 'success', text => "Successfully cleared fraud interval!"}]);
    $c->response->redirect($c->uri_for_action("/customer/details", [$c->stash->{contract}->id]));
    return;
}

sub edit_balance :Chained('base') :PathPart('balance/edit') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::CustomerBalance->new;

    $form->process(
        posted => $posted,
        params => $c->request->params,
        action => $c->uri_for_action("/customer/edit_balance", [$c->stash->{contract}->id]),
        item => $c->stash->{balance},
    );
    if($posted && $form->validated) {
        $c->flash(messages => [{type => 'success', text => 'Account balance successfully changed!'}]);
        $c->response->redirect($c->uri_for_action("/customer/details", [$c->stash->{contract}->id]));
        return;
    }

    $c->stash(close_target => $c->uri_for_action("/customer/details", [$c->stash->{contract}->id]));
    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
}

sub pbx_group_ajax :Chained('base') :PathPart('pbx/group/ajax') :Args(0) {
    my ($self, $c) = @_;
    my $res = $c->model('DB')->resultset('voip_pbx_groups')->search({
        contract_id => $c->stash->{contract}->id,
    });
    NGCP::Panel::Utils::Datatables::process($c, $res, $c->stash->{pbxgroup_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub pbx_group_create :Chained('base') :PathPart('pbx/group/create') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $admin_subscribers = NGCP::Panel::Utils::Subscriber::get_admin_subscribers(
          voip_subscribers => $c->stash->{subscribers});
    unless(@{ $admin_subscribers }) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => 'cannot create pbx group without having an admin subscriber',
            desc  => "Can't create a PBX group without having an administrative subscriber.",
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action('/customer/details', $c->req->captures));
    }
    my $form;
    $form = NGCP::Panel::Form::Customer::PbxGroup->new;
    my $params = {};
    $params = $params->merge($c->session->{created_objects});
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do( sub {
                my $preferences = {};
                my $admin = $admin_subscribers->[0];

                my $base_number = $admin->{primary_number};
                if($base_number) {
                    $preferences->{cloud_pbx_base_cli} = $base_number->{cc} . $base_number->{ac} . $base_number->{sn};
                    if($form->params->{extension}) {
                        $form->params->{e164}{cc} = $base_number->{cc};
                        $form->params->{e164}{ac} = $base_number->{ac};
                        $form->params->{e164}{sn} = $base_number->{sn} . $form->params->{extension};
                    }

                }

                $form->params->{is_pbx_group} = 1;
                $form->params->{domain}{id} = $admin->{domain_id};
                $form->params->{status} = 'active';
                $form->params->{username} = lc $form->params->{name};
                $form->params->{username} =~ s/\s+/_/g;
                $preferences->{cloud_pbx} = 1;
                $preferences->{cloud_pbx_hunt_policy} = $form->params->{hunt_policy};
                $preferences->{cloud_pbx_hunt_timeout} = $form->params->{hunt_policy_timeout};
                my $billing_subscriber = NGCP::Panel::Utils::Subscriber::create_subscriber(
                    c => $c,
                    schema => $schema,
                    contract => $c->stash->{contract},
                    params => $form->params,
                    admin_default => 0,
                    preferences => $preferences,
                );
                foreach my $k(qw/is_pbx_group username password e164 pbx_group domain status/) {
                    delete $form->params->{$k};
                }
                $form->params->{subscriber_id} = $billing_subscriber->provisioning_voip_subscriber->id;
                my $group = $c->stash->{contract}->voip_pbx_groups->create($form->params);
                $c->session->{created_objects}->{group} = { id => $group->id };
            });

            $c->flash(messages => [{type => 'success', text => 'PBX group successfully created.'}]);
        } catch ($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => "Failed to create PBX group.",
            );
        }

        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action('/customer/details', $c->req->captures));
    }

    $c->stash(
        create_flag => 1,
        form => $form,
        description => 'PBX Group',
    );
}

sub pbx_group_base :Chained('base') :PathPart('pbx/group') :CaptureArgs(1) {
    my ($self, $c, $group_id) = @_;

    my $group = $c->model('DB')->resultset('voip_pbx_groups')->find($group_id);
    unless($group) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => "invalid voip pbx group id $group_id",
            desc  => "PBX group with id $group_id does not exist.",
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action('/customer/details', [$c->req->captures->[0]]));
    }

    $c->stash(
        pbx_group => $group,
    );
}

sub pbx_group_edit :Chained('pbx_group_base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form;
    $form = NGCP::Panel::Form::Customer::PbxGroupBase->new;
    my $params = { $c->stash->{pbx_group}->get_inflated_columns };
    $params = $params->merge($c->session->{created_objects});
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                $c->stash->{pbx_group}->update($form->params);
                my $hunt_policy = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                    c => $c, 
                    prov_subscriber => $c->stash->{pbx_group}->provisioning_voip_subscriber,
                    attribute => 'cloud_pbx_hunt_policy'
                );
                if($hunt_policy->first) {
                    $hunt_policy->first->update({ value => $form->params->{hunt_policy} });
                } else {
                    $hunt_policy->create({ value => $form->params->{hunt_policy} });
                }
                my $hunt_timeout = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                    c => $c, 
                    prov_subscriber => $c->stash->{pbx_group}->provisioning_voip_subscriber,
                    attribute => 'cloud_pbx_hunt_timeout'
                );
                if($hunt_timeout->first) {
                    $hunt_timeout->first->update({ value => $form->params->{hunt_policy_timeout} });
                } else {
                    $hunt_timeout->create({ value => $form->params->{hunt_policy_timeout} });
                }
            });

            $c->flash(messages => [{type => 'success', text => 'PBX group successfully updated.'}]);
        } catch ($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => "Failed to update PBX group.",
            );
        }

        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action('/customer/details', [$c->req->captures->[0]]));
    }

    $c->stash(
        edit_flag => 1,
        form => $form
    );
}

sub pbx_device_create :Chained('base') :PathPart('pbx/device/create') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    $c->stash->{autoprov_profile_rs} = $c->model('DB')->resultset('autoprov_profiles')
        ->search({
            'device.reseller_id' => $c->stash->{contract}->contact->reseller_id,
        },{
            join => { 'config' => 'device' }, 
        });
    my $form = NGCP::Panel::Form::Customer::PbxFieldDevice->new(ctx => $c);
    my $params = {};
    $params = $params->merge($c->session->{created_objects});
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do( sub {
                my $prov_subscriber = $schema->resultset('provisioning_voip_subscribers')->find({
                    id => $form->params->{subscriber_id},
                    account_id => $c->stash->{contract}->id,
                });
                unless($prov_subscriber) {
                    NGCP::Panel::Utils::Message->error(
                        c => $c,
                        error => "invalid provisioning subscriber_id '".$form->params->{subscriber_id}.
                            "' for contract id '".$c->stash->{contract}->id."'",
                        desc  => "Invalid provisioning subscriber id detected.",
                    );
                }
                else {
                    $form->params->{identifier} = lc $form->params->{identifier};
                    $prov_subscriber->autoprov_field_devices->create($form->params);
                }
            });

            $c->flash(messages => [{type => 'success', text => 'PBX device successfully created'}]);
        } catch ($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => "Failed to create PBX device",
            );
        }

        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action('/customer/details', $c->req->captures));
    }

    $c->stash(
        create_flag => 1,
        form => $form,
        description => 'PBX Device',
    );
}

sub pbx_device_base :Chained('base') :PathPart('pbx/device') :CaptureArgs(1) {
    my ($self, $c, $dev_id) = @_;

    my $dev = $c->model('DB')->resultset('autoprov_field_devices')->find($dev_id);
    unless($dev) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => "invalid voip pbx device id $dev_id",
            desc  => "PBX device with id $dev_id does not exist.",
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action('/customer/details', [$c->req->captures->[0]]));
    }

    # TODO: in groups, devices etc, check for reseller-id!

    $c->stash(
        pbx_device => $dev,
    );
}

sub pbx_device_edit :Chained('pbx_device_base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    $c->stash->{autoprov_profile_rs} = $c->model('DB')->resultset('autoprov_profiles')
        ->search({
            'device.reseller_id' => $c->stash->{contract}->contact->reseller_id,
        },{
            join => { 'config' => 'device' }, 
        });
    my $form = NGCP::Panel::Form::Customer::PbxFieldDevice->new(ctx => $c);
    my $params = { $c->stash->{pbx_device}->get_inflated_columns };
    $params = $params->merge($c->session->{created_objects});
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do( sub {
                $form->params->{identifier} = lc $form->params->{identifier};
                $c->stash->{pbx_device}->update($form->params);
            });

            $c->flash(messages => [{type => 'success', text => 'PBX device successfully updated'}]);
        } catch ($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => "Failed to update PBX device",
            );
        }

        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action('/customer/details', $c->req->captures));
    }

    $c->stash(
        edit_flag => 1,
        form => $form,
        description => 'PBX Device',
    );
}

sub pbx_device_delete :Chained('pbx_device_base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;

    try {
        $c->stash->{pbx_device}->delete;
        $c->flash(messages => [{type => 'success', text => 'PBX Device successfully deleted' }]);
    } catch($e) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => "failed to delete PBX device with id '".$c->stash->{pbx_device}->id."': $e",
            desc => "Failed to delete PBX device",
        );
    }

    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action('/customer/details', $c->req->captures));
}

sub pbx_device_sync :Chained('pbx_device_base') :PathPart('sync') :Args(0) {
    my ($self, $c) = @_;

    my $form = NGCP::Panel::Form::Customer::PbxFieldDeviceSync->new;
    my $posted = ($c->req->method eq 'POST');

    # TODO: if registered, we could try taking the ip from location?
    my $params = {};

    $form->process(
        posted => $posted,
        params => $c->req->params,
        item => $params,
    );

    if($posted && $form->validated) {
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action('/customer/details', $c->req->captures));
    }
    my $dev = $c->stash->{pbx_device};

    my $t = Template->new;
    my $conf = {
        client => {
            ip => '__NGCP_CLIENT_IP__',
            
        },
        server => {
            uri => $c->uri_for_action('/device/dev_field_config'),
        },
    };
    my ($sync_uri, $real_sync_uri) = ("", "");
    $sync_uri = $dev->profile->config->device->sync_uri;
    $t->process(\$sync_uri, $conf, \$real_sync_uri);

    my ($sync_params_field, $real_sync_params) = ("", "");
    $sync_params_field = $dev->profile->config->device->sync_params;
    my @sync_params = ();
    if($sync_params_field) {
        $t->process(\$sync_params_field, $conf, \$real_sync_params);
        foreach my $p(split /\s*\,\s*/, $real_sync_params) {
            my ($k, $v) = split /=/, $p;
            if(defined $k && defined $v) {
                push @sync_params, { key => $k, value => $v };
            } elsif(defined $k) {
                push @sync_params, { key => $k, value => 0 };
            }
        }
    }

    $c->stash(
        form => $form,
        devsync_flag => 1,
        autoprov_uri => $real_sync_uri,
        autoprov_method => $dev->profile->config->device->sync_method,
        autoprov_params => \@sync_params,
    );
}

=head1 AUTHOR

Andreas Granig,,,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;

# vim: set tabstop=4 expandtab:
