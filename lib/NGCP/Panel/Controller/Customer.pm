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
use NGCP::Panel::Form::Customer::PbxGroup;
use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::Navigation;
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Subscriber;

=head1 NAME

NGCP::Panel::Controller::Customer - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
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

sub root :Chained('list_customer') :PathPart('') :Args(0) {
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
    unless($c->user->is_superuser) {
        $contract = $contract->search({
            'contact.reseller_id' => $c->user->reseller_id,
        }, {
            join => 'contact',
        });
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

    my @subscribers = ();
    my @pbx_groups = ();
    foreach my $s($contract->first->voip_subscribers->search_rs({ status => 'active' })->all) {
        my $sub = { $s->get_columns };
        if($c->config->{features}->{cloudpbx}) {
            $sub->{voip_pbx_group} = { $s->provisioning_voip_subscriber->voip_pbx_group->get_columns }
                if($s->provisioning_voip_subscriber->voip_pbx_group);
        }
        $sub->{domain} = $s->domain->domain;
        $sub->{admin} = $s->provisioning_voip_subscriber->admin if
            $s->provisioning_voip_subscriber;
        $sub->{primary_number} = {$s->primary_number->get_columns} if(defined $s->primary_number);
        $sub->{locations} = [ map { { $_->get_columns } } $c->model('DB')->resultset('location')->
            search({
                username => $s->username,
                domain => $s->domain->domain,
            })->all ];
        if($c->config->{features}->{cloudpbx} && $s->provisioning_voip_subscriber->is_pbx_group) {
            my $grp = $contract->first->voip_pbx_groups->find({ subscriber_id => $s->provisioning_voip_subscriber->id });
            $sub->{voip_pbx_group} = { $grp->get_columns } if $grp;
            push @pbx_groups, $sub;
        } else {
            push @subscribers, $sub;
        }
    }
    $c->stash->{subscribers} = \@subscribers;
    $c->stash->{pbx_groups} = \@pbx_groups;

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
    my @admin_subscribers = NGCP::Panel::Utils::Subscriber::get_admin_subscribers(
          voip_subscriber_rs => $c->stash->{subscribers});
    my $form;

    my $admin_subscribers = NGCP::Panel::Utils::Subscriber::get_admin_subscribers(
        voip_subscribers => $c->stash->{subscribers});

    if($c->config->{features}->{cloudpbx} && $pbx) {
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
        posted => ($c->request->method eq 'POST'),
        params => $c->request->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {
            'domain.create' => $c->uri_for('/domain/create'),
            'group.create' => $c->uri_for_action('/customer/pbx_group_create', $c->req->captures),
        },
        back_uri => $c->req->uri,
    );
    if($form->validated) {
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
                }
                $billing_subscriber = NGCP::Panel::Utils::Subscriber::create_subscriber(
                    c => $c,
                    schema => $schema,
                    contract => $c->stash->{contract},
                    params => $form->params,
                    admin_default => $pbxadmin,
                    preferences => $preferences,
                );

                # update the corresponding group subscriber preference
                if($pbx && !$pbxadmin && $form->params->{pbx_group_id}) {
                    my $grp_subscriber = $c->model('DB')->resultset('voip_pbx_groups')
                        ->find($form->params->{pbx_group_id})
                        ->provisioning_voip_subscriber;
                    if($grp_subscriber) {
                        my $grp_pref_rs = NGCP::Panel::Utils::Subscriber::get_usr_preference_rs(
                            c => $c, attribute => 'cloud_pbx_hunt_group', prov_subscriber => $grp_subscriber
                        );
                        $grp_pref_rs->create({ value => 'sip:'.$form->params->{username}.'@'.
                            $billing_subscriber->domain->domain });
                    }
                }
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
        close_target => $c->uri_for,
        create_flag => 1,
        form => $form
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
