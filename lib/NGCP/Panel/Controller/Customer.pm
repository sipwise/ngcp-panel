package NGCP::Panel::Controller::Customer;
use Sipwise::Base;
use MIME::Base64 qw(encode_base64);
use namespace::sweep;
BEGIN { extends 'Catalyst::Controller'; }
use JSON qw(decode_json encode_json);
use NGCP::Panel::Utils::Contract;
use NGCP::Panel::Form::CustomerMonthlyFraud;
use NGCP::Panel::Form::CustomerDailyFraud;
use NGCP::Panel::Form::CustomerBalance;
use NGCP::Panel::Form::Customer::Subscriber;
use NGCP::Panel::Form::Customer::PbxAdminSubscriber;
use NGCP::Panel::Form::Customer::PbxExtensionSubscriber;
use NGCP::Panel::Form::Customer::PbxExtensionSubscriberSubadmin;
use NGCP::Panel::Form::Customer::PbxGroupEdit;
use NGCP::Panel::Form::Customer::PbxGroup;
use NGCP::Panel::Form::Customer::PbxFieldDevice;
use NGCP::Panel::Form::Customer::PbxFieldDeviceEdit;
use NGCP::Panel::Form::Customer::PbxFieldDeviceSync;
use NGCP::Panel::Form::Customer::InvoiceTemplate;
use PDF::WebKit;
use NGCP::Panel::Model::DB::InvoiceTemplate;
use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::Navigation;
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Subscriber;
use NGCP::Panel::Utils::Sounds;
use NGCP::Panel::Utils::InvoiceTemplate;
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
        { name => "id", search => 1, title => $c->loc("#") },
        { name => "external_id", search => 1, title => $c->loc("External #") },
        { name => "contact.reseller.name", search => 1, title => $c->loc("Reseller") },
        { name => "contact.email", search => 1, title => $c->loc("Contact Email") },
        { name => "billing_mappings.product.name", search => 1, title => $c->loc("Product") },
        { name => "billing_mappings.billing_profile.name", search => 1, title => $c->loc("Billing Profile") },
        { name => "status", search => 1, title => $c->loc("Status") },
        { name => "max_subscribers", search => 1, title => $c->loc("Max Number of Subscribers") },
    ]);
    my $rs = NGCP::Panel::Utils::Contract::get_contracts_rs_sippbx( c => $c );

    $c->stash(
        contract_select_rs => $rs,
        template => 'customer/list.tt'
    );
}

sub root :Chained('list_customer') :PathPart('') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
}

sub ajax :Chained('list_customer') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    my $res = $c->stash->{contract_select_rs};
    NGCP::Panel::Utils::Datatables::process($c, $res, $c->stash->{contract_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub ajax_reseller_filter :Chained('list_customer') :PathPart('ajax/reseller') :Args(1) {
    my ($self, $c, $reseller_id) = @_;

    unless($reseller_id && $reseller_id->is_int) {
        NGCP::Panel::Utils::Message->error(
            c     => $c,
            log   => 'Invalid reseller id detected',
            desc  => $c->loc('Invalid reseller id detected'),
        );
        $c->response->redirect($c->uri_for());
        return;
    }

    my $rs = $c->stash->{contract_select_rs}->search_rs({
        'contact.reseller_id' => $reseller_id,
    },{
        join => 'contact',
    });
    my $reseller_customer_columns = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => $c->loc("#") },
        { name => "external_id", search => 1, title => $c->loc("External #") },
        { name => "billing_mappings.product.name", search => 1, title => $c->loc("Product") },
        { name => "contact.email", search => 1, title => $c->loc("Contact Email") },
        { name => "status", search => 1, title => $c->loc("Status") },
    ]);
    NGCP::Panel::Utils::Datatables::process($c, $rs,  $reseller_customer_columns);
    $c->detach( $c->view("JSON") );
}

sub create :Chained('list_customer') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form;
    my $params = {};
    $params = $params->merge($c->session->{created_objects});
    if($c->config->{features}->{cloudpbx}) {
        $form = NGCP::Panel::Form::Contract::ProductSelect->new(ctx => $c);
    } else {
        $form = NGCP::Panel::Form::Contract::Basic->new(ctx => $c);
    }
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {'contact.create' => $c->uri_for('/contact/create'),
                   'billing_profile.create'  => $c->uri_for('/billing/create')},
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                $form->params->{contact_id} = $form->params->{contact}{id};
                delete $form->params->{contact};
                $form->params->{subscriber_email_template_id} = $form->params->{subscriber_email_template}{id} || undef;
                delete $form->params->{subscriber_email_template};
                $form->params->{passreset_email_template_id} = $form->params->{passreset_email_template}{id} || undef;
                delete $form->params->{passreset_email_template};
                my $bprof_id = $form->params->{billing_profile}{id};
                delete $form->params->{billing_profile};
                $form->{create_timestamp} = $form->{modify_timestamp} = NGCP::Panel::Utils::DateTime::current_local;
                $form->params->{external_id} = $form->field('external_id')->value;
                my $product_id = $form->params->{product}{id};
                delete $form->params->{product};
                unless($product_id) {
                    $product_id = $c->model('DB')->resultset('products')->find({ class => 'sipaccount' })->id;
                }
                unless($form->params->{max_subscribers} && length($form->params->{max_subscribers})) {
                    delete $form->params->{max_subscribers};
                }
                my $contract = $schema->resultset('contracts')->create($form->params);
                my $billing_profile = $schema->resultset('billing_profiles')->find($bprof_id);
                $contract->billing_mappings->create({
                    billing_profile_id => $bprof_id,
                    product_id => $product_id,
                });

                if(($contract->contact->reseller_id // -1) !=
                    ($billing_profile->reseller_id // -1)) {
                    die( ["Contact and Billing profile should have the same reseller", "showdetails"] );
                }

                NGCP::Panel::Utils::Contract::create_contract_balance(
                    c => $c,
                    profile => $billing_profile,
                    contract => $contract,
                );
                $c->session->{created_objects}->{contract} = { id => $contract->id };
                delete $c->session->{created_objects}->{contact};
                delete $c->session->{created_objects}->{billing_profile};
                my $contract_id = $contract->id;
                $c->flash(messages => [{type => 'success', text => $c->loc('Customer #[_1] successfully created',$contract_id) }]);
            });
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create customer contract.'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/contract'));
    }

    $c->stash(create_flag => 1);
    $c->stash(form => $form);
}

sub base :Chained('list_customer') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $contract_id) = @_;
    $c->log->debug('list_customer => base');
    unless($contract_id && $contract_id->is_integer) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => "customer contract id '$contract_id' is not valid",
            desc  => $c->loc('Invalid customer contract id'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/customer'));
        return;
    }

    my $contract_rs = $c->stash->{contract_select_rs}
        ->search({
            'me.id' => $contract_id,
        },{
            '+select' => 'billing_mappings.id',
            '+as' => 'bmid',
        });

    if($c->user->roles eq 'reseller') {
        $contract_rs = $contract_rs->search({
            'contact.reseller_id' => $c->user->reseller_id,
        }, {
            join => 'contact',
        });
    } elsif($c->user->roles eq 'subscriberadmin') {
        $contract_rs = $contract_rs->search({
            'me.id' => $c->user->account_id,
        });
        unless($contract_rs->count) {
            $c->log->error("unauthorized access of subscriber uuid '".$c->user->uuid."' to contract id '$contract_id'");
            $c->detach('/denied_page');
        }
    }
    unless(defined($contract_rs->first)) {
        NGCP::Panel::Utils::Message->error(
            c     => $c,
            log   => 'Customer was not found',
            desc  => $c->loc('Customer was not found'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/customer'));
    }

    my $billing_mapping = $contract_rs->first->billing_mappings->find($contract_rs->first->get_column('bmid'));

    my $stime = NGCP::Panel::Utils::DateTime::current_local()->truncate(to => 'month');
    my $etime = $stime->clone->add(months => 1);
    
    my $balance = $contract_rs->first->contract_balances
        ->find({
            start => { '>=' => $stime },
            end => { '<' => $etime },
            });
    unless($balance) {
        try {
            NGCP::Panel::Utils::Contract::create_contract_balance(
                c => $c,
                profile => $billing_mapping->billing_profile,
                contract => $contract_rs->first,
            );
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create contract balance.'),
            );
            $c->response->redirect($c->uri_for());
            return;
        }
        $balance = $contract_rs->first->contract_balances
            ->find({
                start => {'>=' => $stime},
                end   => {'<'  => $etime},
            });
    }

    my $product_id = $contract_rs->first->get_column('product_id');
    NGCP::Panel::Utils::Message->error(
        c => $c,
        error => "No product for customer contract id $contract_id found",
        desc  => $c->loc('No product for this customer contract found.'),
    ) unless($product_id);
    
    my $product = $c->model('DB')->resultset('products')->find($product_id);
    NGCP::Panel::Utils::Message->error(
        c => $c,
        error => "No product with id $product_id for customer contract id $contract_id found",
        desc  => $c->loc('Invalid product id for this customer contract.'),
    ) unless($product);

    # only show the extension if it's a pbx extension. otherwise (and in case of a pilot?) show the
    # number

    if($c->config->{features}->{cloudpbx} && $product->class eq "pbxaccount") {
        $c->stash->{subscriber_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
            { name => "id", search => 1, title => $c->loc("#") },
            { name => "username", search => 1, title => $c->loc("Name") },
            { name => "provisioning_voip_subscriber.pbx_extension", search => 1, title => $c->loc("Extension") },
        ]);
    } else {
        $c->stash->{subscriber_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
            { name => "id", search => 1, title => $c->loc("#") },
            { name => "username", search => 1, title => $c->loc("Name") },
            { name => "domain.domain", search => 1, title => $c->loc('Domain') },
            { name => "number", search => 1, title => $c->loc('Number'), literal_sql => "concat(primary_number.cc, primary_number.ac, primary_number.sn)"},
            { name => "primary_number.cc", search => 1, title => "" }, #need this to get the relationship
        ]);
    }

    $c->stash->{pbxgroup_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => $c->loc("#") },
        { name => "username", search => 1, title => $c->loc("Name") },
        { name => "provisioning_voip_subscriber.pbx_extension", search => 1, title => $c->loc("Extension") },
        { name => "provisioning_voip_subscriber.pbx_hunt_policy", search => 1, title => $c->loc("Hunt Policy") },
        { name => "provisioning_voip_subscriber.pbx_hunt_timeout", search => 1, title => $c->loc("Serial Hunt Timeout") },
    ]);
    $c->stash->{subscribers} = $c->model('DB')->resultset('voip_subscribers')->search({
        contract_id => $contract_id,
        status => { '!=' => 'terminated' },
        'provisioning_voip_subscriber.is_pbx_group' => 0,
    }, {
        join => 'provisioning_voip_subscriber',
    });
    if($c->config->{features}->{cloudpbx}) {
        $c->stash->{pbx_groups} = $c->model('DB')->resultset('voip_subscribers')->search({
            contract_id => $contract_id,
            status => { '!=' => 'terminated' },
            'provisioning_voip_subscriber.is_pbx_group' => 1,
        }, {
            join => 'provisioning_voip_subscriber',
        });
    }

    my $field_devs = [ $c->model('DB')->resultset('autoprov_field_devices')->search({
        'contract_id' => $contract_rs->first->id
    })->all ];

    # contents of details page:
    my $contract_first = $contract_rs->first;
    NGCP::Panel::Utils::Sounds::stash_soundset_list(c => $c, contract => $contract_first);
    $c->stash->{contact_hash} = { $contract_first->contact->get_inflated_columns };
    if(defined $contract_first->max_subscribers) {
       $c->stash->{subscriber_count} = $contract_first->voip_subscribers
        ->search({ status => { -not_in => ['terminated'] } })
        ->count;
    }

    $c->stash(pbx_devices => $field_devs);

    $c->stash(product => $product);
    $c->stash(balance => $balance);
    $c->stash(fraud => $contract_rs->first->contract_fraud_preference);
    $c->stash(template => 'customer/details.tt'); 
    $c->stash(contract => $contract_first);
    $c->stash(contract_rs => $contract_rs);
    $c->stash(billing_mapping => $billing_mapping );
}

sub edit :Chained('base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;

    #$fooo = breakme;
    # We now optionally get email templates via the form for subscriber creation
    # and for password reset. Change DB schema to store those ids, and if they are
    # not null, hide webpassword field and let user change pass on first login, and
    # also provide a way to reset a lost password.
    #
    # also provide config option for password policy
    #
    # also provide option whether or not passwords are completely hidden (at least
    # from subscriber(admin)) and let them be generated automatically

    my $contract = $c->stash->{contract};
    my $billing_mapping = $c->stash->{billing_mapping};
    my $posted = ($c->request->method eq 'POST');
    my $form;
    my $params = { $contract->get_inflated_columns };
    $params->{contact}{id} = delete $params->{contact_id};
    $params->{product}{id} = $billing_mapping->product_id;
    $params->{billing_profile}{id} = $billing_mapping->billing_profile_id;
    $params->{subscriber_email_template}{id} = delete $params->{subscriber_email_template_id};
    $params->{passreset_email_template}{id} = delete $params->{passreset_email_template_id};
    $params = $params->merge($c->session->{created_objects});
    if($c->config->{features}->{cloudpbx}) {
        $form = NGCP::Panel::Form::Contract::ProductSelect->new(ctx => $c);
    } else {
        $form = NGCP::Panel::Form::Contract::Basic->new(ctx => $c);
    }
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {'contact.create' => $c->uri_for('/contact/create'),
                   'billing_profile.create'  => $c->uri_for('/billing/create')},
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                $form->params->{contact_id} = $form->params->{contact}{id};
                delete $form->params->{contact};
                $form->params->{subscriber_email_template_id} = $form->params->{subscriber_email_template}{id};
                delete $form->params->{subscriber_email_template};
                $form->params->{passreset_email_template_id} = $form->params->{passreset_email_template}{id};
                delete $form->params->{passreset_email_template};
                my $bprof_id = $form->params->{billing_profile}{id};
                delete $form->params->{billing_profile};
                $form->{modify_timestamp} = NGCP::Panel::Utils::DateTime::current_local;
                my $product_id = $form->params->{product}{id} || $billing_mapping->product_id;
                delete $form->params->{product};
                $form->params->{external_id} = $form->field('external_id')->value;
                unless($form->params->{max_subscribers} && length($form->params->{max_subscribers})) {
                    $form->params->{max_subscribers} = undef;
                }
                my $old_bprof_id = $billing_mapping->billing_profile_id;
                my $old_prepaid = $billing_mapping->billing_profile->prepaid;
                my $old_ext_id = $contract->external_id // '';
                $contract->update($form->params);
                my $new_ext_id = $contract->external_id // '';

                if($old_ext_id ne $new_ext_id) { # undef is '' so we don't bail out here
                    foreach my $sub($contract->voip_subscribers->all) {
                        my $prov_sub = $sub->provisioning_voip_subscriber;
                        next unless($prov_sub);
                        NGCP::Panel::Utils::Subscriber::update_preferences(
                            c => $c, 
                            prov_subscriber => $prov_sub, 
                            preferences => { ext_contract_id => $contract->external_id }
                        );
                    }
                }

                if($bprof_id != $old_bprof_id) {
                    $contract->billing_mappings->create({
                        billing_profile_id => $bprof_id,
                        product_id => $product_id,
                        start_date => NGCP::Panel::Utils::DateTime::current_local,
                    });
                    my $new_billing_profile = $c->model('DB')->resultset('billing_profiles')->find($bprof_id);
                    if($old_prepaid && !$new_billing_profile->prepaid) {
                        foreach my $sub($contract->voip_subscribers->all) {
                            my $prov_sub = $sub->provisioning_voip_subscriber;
                            next unless($prov_sub);
                            my $pref = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                                c => $c, attribute => 'prepaid', prov_subscriber => $prov_sub);
                            if($pref->first) {
                                $pref->first->delete;
                            }
                        }
                    } elsif(!$old_prepaid && $new_billing_profile->prepaid) {
                        foreach my $sub($contract->voip_subscribers->all) {
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

                unless ( defined $schema->resultset('billing_profiles')
                        ->search_rs({
                                id => $bprof_id,
                                reseller_id => $contract->contact->reseller_id,
                            })
                        ->first ) {
                    die( ["Contact and Billing profile should have the same reseller", "showdetails"] );
                }

                delete $c->session->{created_objects}->{contact};
                delete $c->session->{created_objects}->{billing_profile};
                my $contract_id = $contract->id;
                $c->flash(messages => [{type => 'success', text => $c->loc('Customer #[_1] successfully updated',$contract_id) }]);
            });
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update customer contract.'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/customer'));
    }

    $c->stash(template => 'customer/list.tt');
    $c->stash(edit_flag => 1);
    $c->stash(form => $form);
}

sub terminate :Chained('base') :PathPart('terminate') :Args(0) {
    my ($self, $c) = @_;
    my $contract = $c->stash->{contract};

    if ($contract->id == 1) {
        $c->flash(messages => [{type => 'error', text => $c->loc('Cannot terminate contract with the id 1')}]);
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/contract'));
    }

    try {
        my $old_status = $contract->status;
        $contract->update({ status => 'terminated' });
        # if status changed, populate it down the chain
        if($contract->status ne $old_status) {
            NGCP::Panel::Utils::Contract::recursively_lock_contract(
                c => $c,
                contract => $contract,
            );
        }
        $c->flash(messages => [{type => 'success', text => $c->loc('Customer successfully terminated') }]);
    } catch ($e) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => $e,
            desc  => $c->loc('Failed to terminate contract.'),
        );
    };
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/contract'));
}

sub details :Chained('base') :PathPart('details') :Args(0) {
    my ($self, $c) = @_;

    NGCP::Panel::Utils::Sounds::stash_soundset_list(c => $c, contract => $c->stash->{contract});
    $c->stash->{contact_hash} = { $c->stash->{contract}->contact->get_inflated_columns };
    if(defined $c->stash->{contract}->max_subscribers) {
       $c->stash->{subscriber_count} = $c->stash->{contract}->voip_subscribers
        ->search({ status => { -not_in => ['terminated'] } })
        ->count;
    }
    #didn't find a way to make it correct with chain
    $c->forward('invoice_data');
    #$self->invoice_data($c);
}

sub subscriber_create :Chained('base') :PathPart('subscriber/create') :Args(0) {
    my ($self, $c) = @_;

    if(defined $c->stash->{contract}->max_subscribers &&
       $c->stash->{contract}->voip_subscribers
        ->search({ status => { -not_in => ['terminated'] } })
        ->count >= $c->stash->{contract}->max_subscribers) {

        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => "tried to exceed max number of subscribers of " . $c->stash->{contract}->max_subscribers,
            desc  => $c->loc('Maximum number of subscribers for this customer reached'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, 
            $c->uri_for_action('/customer/details', [$c->stash->{contract}->id])
        );
    }

    my $pbx = 0; my $pbxadmin = 0;
    $pbx = 1 if $c->stash->{product}->class eq 'pbxaccount';
    my $form;
    my $posted = ($c->request->method eq 'POST');
    my $admin_subscribers = $c->stash->{subscribers}->search({
        'provisioning_voip_subscriber.admin' => 1,
    });
    $c->stash->{admin_subscriber} = $admin_subscribers->first;

    
    my $params = {};

    if($c->config->{features}->{cloudpbx} && $pbx) {
        $c->stash(customer_id => $c->stash->{contract}->id);
        # we need to create an admin subscriber first
        unless($c->stash->{admin_subscriber}) {
            $pbxadmin = 1;
            $form = NGCP::Panel::Form::Customer::PbxAdminSubscriber->new(ctx => $c);
        } else {
            if($c->user->roles eq "subscriberadmin") {
                $form = NGCP::Panel::Form::Customer::PbxExtensionSubscriberSubadmin->new(ctx => $c);
            } else {
                $form = NGCP::Panel::Form::Customer::PbxExtensionSubscriber->new(ctx => $c);
            }
            NGCP::Panel::Utils::Subscriber::prepare_alias_select(
                c => $c,
                subscriber => $c->stash->{admin_subscriber},
                params => $params,
                unselect => 1, # no numbers assigned yet, keep selection list empty
            );
        }
    } else {
        $form = NGCP::Panel::Form::Customer::Subscriber->new(ctx => $c);
    }

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
                    my $admin = $c->stash->{admin_subscriber};
                    $form->params->{domain}{id} = $admin->domain_id;
                    # TODO: make DT selection multi-select capable
                    $form->params->{pbx_group_id} = $form->params->{group}{id};
                    delete $form->params->{group};
                    my $base_number = $admin->primary_number;
                    if($base_number) {
                        $preferences->{cloud_pbx_base_cli} = $base_number->cc . $base_number->ac . $base_number->sn;
                        if($form->params->{pbx_extension}) {
                            $form->params->{e164}{cc} = $base_number->cc;
                            $form->params->{e164}{ac} = $base_number->ac;
                            $form->params->{e164}{sn} = $base_number->sn . $form->params->{pbx_extension};
                        }
                    }
                }
                if($pbx) {
                    $preferences->{cloud_pbx} = 1;
                    if($pbxadmin && $form->params->{e164}{cc} && $form->params->{e164}{sn}) {
                        $preferences->{cloud_pbx_base_cli} = $form->params->{e164}{cc} . 
                                                             ($form->params->{e164}{ac} // '') . 
                                                             $form->params->{e164}{sn};
                    }

                    if($c->stash->{admin_subscriber}) {
                        my $profile_set = $c->stash->{admin_subscriber}->provisioning_voip_subscriber->voip_subscriber_profile_set;
                        if($profile_set) {
                            $form->params->{profile_set}{id} = $profile_set->id;
                        }
                    }

                    # TODO: if number changes, also update cloud_pbx_base_cli

                    # TODO: only if it's not a fax/conf extension:
                    $preferences->{shared_buddylist_visibility} = 1;
                    $preferences->{display_name} = $form->params->{display_name}
                        if($form->params->{display_name});
                }
                if($c->stash->{contract}->external_id) {
                    $preferences->{ext_contract_id} = $c->stash->{contract}->external_id;
                }
                if(defined $form->params->{external_id}) {
                    $preferences->{ext_subscriber_id} = $form->params->{external_id};
                }
                if($c->stash->{billing_mapping}->billing_profile->prepaid) {
                    $preferences->{prepaid} = 1;
                }
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

                if($pbx && !$pbxadmin) {
                    NGCP::Panel::Utils::Subscriber::update_subadmin_sub_aliases(
                        schema => $schema,
                        subscriber => $billing_subscriber,
                        contract_id => $billing_subscriber->contract_id,
                        alias_selected => decode_json($form->value->{alias_select}),
                        sadmin => $c->stash->{admin_subscriber},
                    );
                }

            });

            delete $c->session->{created_objects}->{domain};
            delete $c->session->{created_objects}->{group};
            $c->flash(messages => [{type => 'success', text => $c->loc('Subscriber successfully created.') }]);
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create subscriber.'),
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
        NGCP::Panel::Utils::Message->error(
            c     => $c,
            log   => "Invalid fraud interval '$type'!",
            desc  => $c->loc("Invalid fraud interval '[_1]'!",$type),
        );
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
        $c->flash(messages => [{type => 'success', text => $c->loc('Fraud settings successfully changed!') }]);
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
        NGCP::Panel::Utils::Message->error(
            c     => $c,
            log   => "Invalid fraud interval '$type'!",
            desc  => $c->loc("Invalid fraud interval '[_1]'!",$type),
        );
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
                desc  => $c->loc('Failed to clear fraud interval.'),
            );
            $c->response->redirect($c->uri_for_action("/customer/details", [$c->stash->{contract}->id]));
            return;
        }
    }
    $c->flash(messages => [{type => 'success', text => $c->loc('Successfully cleared fraud interval!') }]);
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
        $c->flash(messages => [{type => 'success', text => $c->loc('Account balance successfully changed!') }]);
        $c->response->redirect($c->uri_for_action("/customer/details", [$c->stash->{contract}->id]));
        return;
    }

    $c->stash(close_target => $c->uri_for_action("/customer/details", [$c->stash->{contract}->id]));
    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
}
sub invoice_data :Chained('base') :PathPart('invoice') :CaptureArgs(0) {
    my ($self, $c) = @_;
    $c->log->debug('invoice_data');
    my $contract_id = $c->stash->{contract}->id;
    my $stime = NGCP::Panel::Utils::DateTime::current_local()->truncate(to => 'month');
    my $etime = $stime->clone->add(months => 1);

    #look, NGCP::Panel::Utils::Contract - it is kind of backend separation here
    my $invoice_details = NGCP::Panel::Utils::Contract::get_contract_calls_rs(
        c => $c,
        contract_id => $contract_id,
        stime => $stime,
        etime => $etime,
    );
    #TODO: FAKE FAKE FAKE FAKE
    my $invoice_details_raw = $invoice_details;
    $invoice_details = [$invoice_details_raw->all()];
    my $i = 1;
    $invoice_details = [map{[$i++,$_]} (@$invoice_details) x 21];
    $c->stash( invoice_details => $invoice_details );
    $c->stash( invoice_details_raw => $invoice_details_raw );
}
sub invoice_details_ajax :Chained('base') :PathPart('invoice/details/ajax') :Args(0) {
    my ($self, $c) = @_;
    my $dt_columns_json = $c->request->parameters->{dt_columns};
    use JSON;
    #use irka;
    #use Data::Dumper;
    #irka::loglong(Dumper($dt_columns));
    $c->forward( 'invoice_data' );
    my $dt_columns = from_json($dt_columns_json);
    NGCP::Panel::Utils::Datatables::process($c, $c->stash->{invoice_details_raw}, $dt_columns );
    $c->detach( $c->view("JSON") );
}

sub invoice_template_activate :Chained('base') :PathPart('invoice_template/activate') :Args(1) {
    my ($self, $c) = @_;
    $c->log->debug('invoice_template_activate');
    my($validator,$backend,$in,$out);

    (undef,undef,@$in{qw/tt_id/}) = @_;
    #check that this id really belongs to specified contract? or just add contract condition to delete query?
    #checking is more universal
    #this is just copy-paste from method above
    #of course we are chained and we can put in and out to stash
    #input
    $in->{contract_id} = $c->stash->{contract}->id;
    
    #output
    $out={};

    #storage
    #pass scheme here is ugly, and should be moved somehow to DB::Base
    $backend = NGCP::Panel::Model::DB::InvoiceTemplate->new( schema => $c->model('DB') );

    #input checking & simple preprocessing
    $validator = NGCP::Panel::Form::Customer::InvoiceTemplate->new( backend => $backend );
#    $form->schema( $c->model('DB::InvoiceTemplate')->schema );
    #to common form package ? removing is necessary due to FormHandler param presence evaluation - it is based on key presence, not on defined/not defined value
    #in future this method should be called by ControllerBase
    $validator->remove_undef_in($in);
    
    #really, we don't need a form here at all
    #just use as already implemented fields checking and defaults applying  
    #$validator->setup_form(
    $validator->process(
        posted => 1,
        params => $in,
    );
    #$validator->validate_form();
    
    #multi return...
    $c->log->debug("validated=".$validator->validated.";\n");
    if(!$validator->validated){
        return;
    }
    my $in_validated = $validator->fif;

    #dirty hack 1
    #really model logic should recieve validated input, but raw input also should be saved somewhere
    $in = $in_validated;
    #think about it more
    
    $backend->activateCustomerInvoiceTemplate(%$in);
    $c->forward( 'invoice_template_list' );
}
sub invoice_template_delete :Chained('base') :PathPart('invoice_template/delete') :Args(1) {
    my ($self, $c) = @_;
    $c->log->debug('invoice_template_delete');
    my($validator,$backend,$in,$out);

    (undef,undef,@$in{qw/tt_id/}) = @_;
    #check that this id really belongs to specified contract? or just add contract condition to delete query?
    #checking is more universal
    #this is just copy-paste from method above
    #of course we are chained and we can put in and out to stash
    #input
    $in->{contract_id} = $c->stash->{contract}->id;
    
    #output
    $out={};

    #storage
    #pass scheme here is ugly, and should be moved somehow to DB::Base
    $backend = NGCP::Panel::Model::DB::InvoiceTemplate->new( schema => $c->model('DB') );

    #input checking & simple preprocessing
    $validator = NGCP::Panel::Form::Customer::InvoiceTemplate->new( backend => $backend );
#    $form->schema( $c->model('DB::InvoiceTemplate')->schema );
    #to common form package ? removing is necessary due to FormHandler param presence evaluation - it is based on key presence, not on defined/not defined value
    #in future this method should be called by ControllerBase
    $validator->remove_undef_in($in);
    
    #really, we don't need a form here at all
    #just use as already implemented fields checking and defaults applying  
    #$validator->setup_form(
    $validator->process(
        posted => 1,
        params => $in,
    );
    #$validator->validate_form();
    
    #multi return...
    $c->log->debug("validated=".$validator->validated.";\n");
    if(!$validator->validated){
        return;
    }
    my $in_validated = $validator->fif;

    #dirty hack 1
    #really model logic should recieve validated input, but raw input also should be saved somewhere
    $in = $in_validated;
    #think about it more
    
    $backend->deleteCustomerInvoiceTemplate(%$in);
    $c->forward( 'invoice_template_list' );
}

sub invoice_template_list_data :Chained('invoice_data') :PathPart('') :CaptureArgs(0) {
    my ($self, $c) = @_; 
    $c->log->debug('invoice_template_list_data');
    my($validator,$backend,$in,$out);
    $in->{contract_id} = $c->stash->{contract}->id;
    $backend = NGCP::Panel::Model::DB::InvoiceTemplate->new( schema => $c->model('DB') );
    my $records = $backend->getCustomerInvoiceTemplateList( %$in );
    $c->stash( invoice_template_list => $records );
}
sub invoice_template_list :Chained('base') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
    $c->log->debug('invoice_template_list');
    $c->stash( template => 'customer/invoice_template_list.tt' ); 
    $c->forward( 'invoice_template_list_data' );
    $c->detach($c->view('SVG'));#just no wrapper - maybe there is some other way?
}

sub invoice :Chained('invoice_template_list_data') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
    $c->stash(template => 'customer/invoice.tt'); 
}

sub invoice_template :Chained('invoice_data') :PathPart('template') :Args {
    my ($self, $c) = @_;
    $c->log->debug('invoice_template');
    no warnings 'uninitialized';

    my($validator,$backend,$in,$out);

    #input
    (undef,undef,@$in{qw/tt_type tt_viewmode tt_sourcestate tt_output_type tt_id/}) = @_ ;
    $in->{contract_id} = $c->stash->{contract}->id;
    $in->{tt_string} = $c->request->body_parameters->{template} || '';
    foreach(qw/name is_active/){$in->{$_} = $c->request->parameters->{$_};}
    
    #output
    $out={};

    #storage
    #pass scheme here is ugly, and should be moved somehow to DB::Base
    $backend = NGCP::Panel::Model::DB::InvoiceTemplate->new( schema => $c->model('DB') );

    #input checking & simple preprocessing
    $validator = NGCP::Panel::Form::Customer::InvoiceTemplate->new;
#    $form->schema( $c->model('DB::InvoiceTemplate')->schema );
    #to common form package ? removing is necessary due to FormHandler param presence evaluation - it is based on key presence, not on defined/not defined value
    $validator->remove_undef_in($in);
    
    #really, we don't need a form here at all
    #just use as already implemented fields checking and defaults applying  
    #$validator->setup_form(
    $validator->process(
        posted => 1,
        params => $in,
    );
    #$validator->validate_form();
    
    #multi return...
    $c->log->debug("validated=".$validator->validated.";\n");
    if(!$validator->validated){
        return;
    }
    my $in_validated = $validator->fif;

    #dirty hack 1
    #really model logic should recieve validated input, but raw input also should be saved somewhere
    $in = $in_validated;
    
    #model logic
    my $tt_string_default = '';
    my $tt_string_customer = '';
    my $tt_string_force_default = ( $in->{tt_sourcestate} eq 'default' );
    $c->log->debug("force_default=$tt_string_force_default;");
    if(!$in->{tt_string} && !$tt_string_force_default){
        #here we also may be better should contact model, not DB directly. Will return to this separation later
        #at the end - we can figure out rather basic controller behaviour
        ($out->{tt_id},undef,$out->{tt_data}) = $backend->getCustomerInvoiceTemplate( %$in, result => \$tt_string_customer );

        if($out->{tt_data}){
            $out->{json} = {
                tt_data => { 
                    tt_id => $out->{tt_data}->get_column('id'),
                },
            };
            foreach(qw/name is_active/){
                $out->{json}->{tt_data}->{$_} = $out->{tt_data}->get_column($_);
            }
        }
        
    }
    
    #we need to get default to 1) sanitize (if in->tt_string) or 2)if not in->tt_string and no customer->tt_string
    if($in->{tt_string} || !$tt_string_customer || $tt_string_force_default ){
        try{
            #Utils... mmm - if it were model - there would be no necessity in utils using
            NGCP::Panel::Utils::InvoiceTemplate::getDefaultInvoiceTemplate( c => $c, type => $in->{tt_type}, result => \$tt_string_default );
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => 'default invoice template error',
                desc  => $c->loc('There is no one invoice template in the system.'),
            );
        }
        if($in->{tt_string} && !$tt_string_force_default){
            #sanitize
            my $tt_string_sanitized = $in->{tt_string};
            $tt_string_sanitized =~s/<script.*?\/script>//gs;
            my $tokens_re = qr/\[%(.*?)%\]/;
            my $token_shape_re = qr/\s+/;
            my %tokens_valid = map{$_=~s/$token_shape_re//sg; $_ => 1;} ($tt_string_default=~/$tokens_re/sg);
            foreach( $tt_string_sanitized=~/$tokens_re/sg ){
                my $token_shape=$_;
                $token_shape=~s/$token_shape_re//sg;
                if(! exists $tokens_valid{$token_shape}){
                    $c->log->debug('Not allowed token in invoice template:'.$_.";\n");
                    $tt_string_sanitized=~s/(?:\[%)+\s*\Q$_\E\s*(?:%\])+//g;
                }
            }
            #/sanitize - to sub, later

            my($tt_stored) = $backend->storeCustomerInvoiceTemplate( 
                %$in,
                tt_string_sanitized => \$tt_string_sanitized,
            );
            
            $out->{json} = {
                tt_data => { 
                    tt_id => $tt_stored->{tt_id},
                },
            };

            
            $out->{tt_string} = $tt_string_sanitized;
        }elsif(!$tt_string_customer || $tt_string_force_default){
            $out->{tt_string} = $tt_string_default;
            $c->log->debug("apply default;");
        }
    }else{#we have customer template, we don't have dynamic template string, we weren't requested to show default
        $out->{tt_string} = $tt_string_customer;
    }
    #/model logic
    
    #prepare response
    #mess,mess,mess here
    if($in->{tt_output_type} eq 'svg'){
        $c->response->content_type('text/html');
        #multi-svg document (as well as one-svg documet) is shown ok with text/html
#        $c->response->content_type('image/svg+xml');
    }elsif($in->{tt_output_type} eq 'pdf'){
        $c->response->content_type('application/pdf');
    }elsif($in->{tt_output_type} eq 'html'){
        $c->response->content_type('text/html');
    }elsif($in->{tt_output_type} eq 'json'){
        $c->response->content_type('application/json');
    }elsif($in->{tt_output_type}=~m'zip'){
        $c->response->content_type('application/zip');
    }
    
    if($in->{tt_viewmode} eq 'raw'){
        #$c->stash->{VIEW_NO_TT_PROCESS} = 1;
        $c->response->body($out->{tt_string});
        return;
    }else{#parsed

        my $contacts = $c->model('DB')->resultset('contacts')->search({ id => $in->{contract_id} });
        $c->stash( provider => $contacts->first );

        #some preprocessing should be done only before showing. So, there will be:
        #preShowCustomTemplate prerpocessing
        {
            #preShowInvoice
            #even better - to template filters
            #also to model
            $out->{tt_string_prepared}=$out->{tt_string_stored}=$out->{tt_string};
            $out->{tt_string_prepared}=~s/(?:{\s*)?<!--{|}-->(?:\s*})?//gs;
            $out->{tt_string_prepared}=~s/(<g .*?(id *=["' ]+(?:title|bg|mid)page["' ]+)?.*?)(?:display="none")(?(2)(?:.*?>)($2.*?>))/$1$3/gs;
        }

        if( ($in->{tt_output_type} eq 'svg') || ( $in->{tt_output_type} eq 'html') ){
            #$c->response->content_type('image/svg+xml');
            $c->stash( template => \$out->{tt_string_prepared} ); 
            $c->detach( $c->view('SVG') );
        }elsif($in->{tt_output_type} eq 'json'){
        #method
            $c->log->debug('prepare json');
            
            my $aaData = {
                template =>{
                    raw => $out->{tt_string_stored}, 
                    parsed => $c->view('SVG')->getTemplateProcessed($c, \$out->{tt_string_prepared}, $c->stash ),
                },
            };
            #can be empty if we just load default
            if($out->{json} && $out->{json}->{tt_data}){
                $aaData->{form} = $out->{json}->{tt_data};
            }else{
                #if we didn't have tt_data - then we have empty form fields with applied defaults
                $aaData->{form} = $in;
            }
            $c->stash( aaData => $aaData ); 
            $c->detach( $c->view('JSON') );
        }elsif($in->{tt_output_type} eq 'pdf'){
        #method
            $c->response->content_type('application/pdf');
            my $svg = $c->view('SVG')->getTemplateProcessed($c,\$out->{tt_string_prepared}, $c->stash );
            my(@pages) = $svg=~/(<svg.*?(?:\/svg>))/sig;
            
            #$c->log->debug($svg);
            my ($tempdirbase,$tempdir );
            use File::Temp qw/tempfile tempdir/;
            #my($fh, $tempfilename) = tempfile();
            $tempdirbase = join('/',File::Spec->tmpdir,@$in{qw/contract_id tt_type tt_sourcestate/}, $out->{tt_id});
            use File::Path qw( mkpath );
            ! -e $tempdirbase and mkpath( $tempdirbase, 0, 0777 );
            $tempdir = tempdir( DIR =>  $tempdirbase , CLEANUP => 1 );
            $c->log->debug("tempdirbase=$tempdirbase; tempdir=$tempdir;");
            #try{
            #} catch($e){
            #    NGCP::Panel::Utils::Message->error(
            #        c => $c,
            #        error => "Can't create temporary directory at: $tempdirbase;" ,
            #        desc  => $c->loc("Can't create temporary directory."),
            #    );
            #}
            my $pagenum = 1;
            my @pagefiles;
            foreach my $page (@pages){
                my $fh;
                my $pagefile = "$tempdir/$pagenum.svg";
                push @pagefiles, $pagefile;
                open($fh,">",$pagefile);
                #try{
                #} catch($e){
                #    NGCP::Panel::Utils::Message->error(
                #        c => $c,
                #        error => "Can't create temporary page file at: $tempdirbase/$page.svg;" ,
                #        desc  => $c->loc("Can't create temporary file."),
                #    );
                #}
                print $fh $page;
                close $fh;
                $pagenum++;
            }
            
            my $cmd = "rsvg-convert -f pdf ".join(" ", @pagefiles);
            $c->log->debug($cmd);
            #`chmod ugo+rwx $filename`;
            #binmode(STDOUT);
            #binmode(STDIN);
            #$out->{tt_string} = `$cmd`;
            {
                #$cmd = "fc-list";
                open B, "$cmd |"; 
                binmode B; 
                local $/ = undef; 
                $out->{tt_string_pdf} = <B>;
                close B;
            }
            $c->response->body($out->{tt_string_pdf});
            return;
            #$out->{tt_string} = `cat $filename `;
        }

    }
}

sub invoice_template_aux_embedImage :Chained('list_customer') :PathPart('auxembedimage') :Args(0) {
    my ($self, $c) = @_;
    
    #I know somewhere is logging of all visited methods
    $c->log->debug('invoice_template_aux_handleImageUpload');
    my($validator,$backend,$in,$out);
    
    #todo
    #mime-type and type checking in form
    
    $in = $c->request->parameters;
    $in->{svg_file} = $c->request->upload('svg_file');
    if($in->{svg_file}) {
        my $ft = File::Type->new();
        $out->{image_content} = $in->{svg_file}->slurp;
        $out->{image_content_mimetype} = $ft->mime_type($out->{image_content});
        $out->{image_content_base64} = encode_base64($out->{image_content}, '');
    }
    $c->log->debug('mime-type '.$out->{image_content_mimetype});
    $c->stash(out => $out);
    $c->stash(in => $in);
    $c->stash(template => 'customer/invoice_template_aux_embedimage.tt');
    $c->detach( $c->view('SVG') );
    
}
sub pbx_group_ajax :Chained('base') :PathPart('pbx/group/ajax') :Args(0) {
    my ($self, $c) = @_;
    my $res = $c->stash->{contract}->voip_subscribers->search({
        'provisioning_voip_subscriber.is_pbx_group' => 1,

    },{
        join => 'provisioning_voip_subscriber',
    });
    NGCP::Panel::Utils::Datatables::process($c, $res, $c->stash->{pbxgroup_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub pbx_group_create :Chained('base') :PathPart('pbx/group/create') :Args(0) {
    my ($self, $c) = @_;

    if(defined $c->stash->{contract}->max_subscribers &&
       $c->stash->{contract}->voip_subscribers
        ->search({ status => { -not_in => ['terminated'] } })
        ->count >= $c->stash->{contract}->max_subscribers) {

        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => "tried to exceed max number of subscribers of " . $c->stash->{contract}->max_subscribers,
            desc  => $c->loc('Maximum number of subscribers for this customer reached'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, 
            $c->uri_for_action('/customer/details', [$c->stash->{contract}->id])
        );
    }

    my $posted = ($c->request->method eq 'POST');
    my $admin_subscribers = $c->stash->{subscribers}->search({
        'provisioning_voip_subscriber.admin' => 1,
    });
    $c->stash->{admin_subscriber} = $admin_subscribers->first;
    unless($c->stash->{admin_subscriber}) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => 'cannot create pbx group without having an admin subscriber',
            desc  => $c->loc("Can't create a PBX group without having an administrative subscriber."),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action('/customer/details', $c->req->captures));
    }
    my $form;
    $form = NGCP::Panel::Form::Customer::PbxGroup->new(ctx => $c);
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
                my $admin = $c->stash->{admin_subscriber};

                my $base_number = $admin->primary_number;
                if($base_number) {
                    $preferences->{cloud_pbx_base_cli} = $base_number->cc . $base_number->ac . $base_number->sn;
                    if($form->params->{pbx_extension}) {
                        $form->params->{e164}{cc} = $base_number->cc;
                        $form->params->{e164}{ac} = $base_number->ac;
                        $form->params->{e164}{sn} = $base_number->sn . $form->params->{pbx_extension};
                    }

                }
                $form->params->{is_pbx_group} = 1;
                $form->params->{domain}{id} = $admin->domain_id;
                $form->params->{status} = 'active';
                $preferences->{cloud_pbx} = 1;
                $preferences->{cloud_pbx_hunt_policy} = $form->params->{pbx_hunt_policy};
                $preferences->{cloud_pbx_hunt_timeout} = $form->params->{pbx_hunt_timeout};
                my $billing_subscriber = NGCP::Panel::Utils::Subscriber::create_subscriber(
                    c => $c,
                    schema => $schema,
                    contract => $c->stash->{contract},
                    params => $form->params,
                    admin_default => 0,
                    preferences => $preferences,
                );
                $c->session->{created_objects}->{group} = { id => $billing_subscriber->id };
            });

            $c->flash(messages => [{type => 'success', text => $c->loc('PBX group successfully created.')}]);
        } catch ($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create PBX group.'),
            );
        }

        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action('/customer/details', $c->req->captures));
    }

    $c->stash(
        create_flag => 1,
        form => $form,
        description => $c->loc('PBX Group'),
    );
}

sub pbx_group_base :Chained('base') :PathPart('pbx/group') :CaptureArgs(1) {
    my ($self, $c, $group_id) = @_;

    my $group = $c->stash->{pbx_groups}->find($group_id);
    unless($group) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => "invalid voip pbx group id $group_id",
            desc  => $c->loc('PBX group with id [_1] does not exist.',$group_id),
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
    $form = NGCP::Panel::Form::Customer::PbxGroupEdit->new;
    my $params = { $c->stash->{pbx_group}->provisioning_voip_subscriber->get_inflated_columns };
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
                $c->stash->{pbx_group}->provisioning_voip_subscriber->update($form->params);
                my $hunt_policy = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                    c => $c, 
                    prov_subscriber => $c->stash->{pbx_group}->provisioning_voip_subscriber,
                    attribute => 'cloud_pbx_hunt_policy'
                );
                if($hunt_policy->first) {
                    $hunt_policy->first->update({ value => $form->params->{pbx_hunt_policy} });
                } else {
                    $hunt_policy->create({ value => $form->params->{pbx_hunt_policy} });
                }
                my $hunt_timeout = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                    c => $c, 
                    prov_subscriber => $c->stash->{pbx_group}->provisioning_voip_subscriber,
                    attribute => 'cloud_pbx_hunt_timeout'
                );
                if($hunt_timeout->first) {
                    $hunt_timeout->first->update({ value => $form->params->{pbx_hunt_timeout} });
                } else {
                    $hunt_timeout->create({ value => $form->params->{pbx_hunt_timeout} });
                }
            });

            $c->flash(messages => [{type => 'success', text => $c->loc('PBX group successfully updated.') }]);
        } catch ($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update PBX group.'),
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
            my $err = 0;
            my $schema = $c->model('DB');
            $schema->txn_do( sub {
                my $station_name = $form->params->{station_name};
                my $identifier = lc $form->params->{identifier};
                my $profile_id = $form->params->{profile_id};
                my $fdev = $c->stash->{contract}->autoprov_field_devices->create({
                    profile_id => $profile_id,
                    identifier => $identifier,
                    station_name => $station_name,
                });

                my @lines = $form->field('line')->fields;
                foreach my $line(@lines) {
                    my $prov_subscriber = $schema->resultset('provisioning_voip_subscribers')->find({
                        id => $line->field('subscriber_id')->value,
                        account_id => $c->stash->{contract}->id,
                    });
                    unless($prov_subscriber) {
                        NGCP::Panel::Utils::Message->error(
                            c => $c,
                            error => "invalid provisioning subscriber_id '".$line->field('subscriber_id')->value.
                                "' for contract id '".$c->stash->{contract}->id."'",
                            desc  => $c->loc('Invalid provisioning subscriber id detected.'),
                        );
                        # TODO: throw exception here!
                        $err = 1;
                        last;
                    }
                    my ($range_id, $key_num) = split /\./, $line->field('line')->value;
                    my $type = $line->field('type')->value;
                    $fdev->autoprov_field_device_lines->create({
                        subscriber_id => $prov_subscriber->id,
                        linerange_id => $range_id,
                        key_num => $key_num,
                        line_type => $type,
                    });
                }
            });
            unless($err) {
                $c->flash(messages => [{type => 'success', text => $c->loc('PBX device successfully created') }]);
            }
        } catch ($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create PBX device'),
            );
        }

        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action('/customer/details', $c->req->captures));
    }

    $c->stash(
        create_flag => 1,
        form => $form,
        description => $c->loc('PBX Device'),
    );
}

sub pbx_device_base :Chained('base') :PathPart('pbx/device') :CaptureArgs(1) {
    my ($self, $c, $dev_id) = @_;

    my $dev = $c->model('DB')->resultset('autoprov_field_devices')->find($dev_id);
    unless($dev) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => "invalid voip pbx device id $dev_id",
            desc  => $c->loc('PBX device with id [_1] does not exist.',$dev_id),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action('/customer/details', [$c->req->captures->[0]]));
    }
    if($dev->contract->id != $c->stash->{contract}->id) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => "invalid voip pbx device id $dev_id for customer id '".$c->stash->{contract}->id."'",
            desc  => $c->loc('PBX device with id [_1] does not exist for this customer.',$dev_id),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action('/customer/details', [$c->req->captures->[0]]));
    }

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
    my $form = NGCP::Panel::Form::Customer::PbxFieldDeviceEdit->new(ctx => $c);
    my $params = { $c->stash->{pbx_device}->get_inflated_columns };
    my @lines = ();
    foreach my $line($c->stash->{pbx_device}->autoprov_field_device_lines->all) {
        push @lines, {
            subscriber_id => $line->subscriber_id,
            line => $line->linerange_id . '.' . $line->key_num,
            type => $line->line_type,
        };
    }
    $params->{line} = \@lines;
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
            my $err = 0;
            my $schema = $c->model('DB');
            $schema->txn_do( sub {
                my $fdev = $c->stash->{pbx_device};
                my $station_name = $form->params->{station_name};
                my $identifier = lc $form->params->{identifier};
                my $profile_id = $form->params->{profile_id};
                $fdev->update({
                    profile_id => $profile_id,
                    identifier => $identifier,
                    station_name => $station_name,
                });

                $fdev->autoprov_field_device_lines->delete_all;
                my @lines = $form->field('line')->fields;
                foreach my $line(@lines) {
                    my $prov_subscriber = $schema->resultset('provisioning_voip_subscribers')->find({
                        id => $line->field('subscriber_id')->value,
                        account_id => $c->stash->{contract}->id,
                    });
                    unless($prov_subscriber) {
                        NGCP::Panel::Utils::Message->error(
                            c => $c,
                            error => "invalid provisioning subscriber_id '".$line->field('subscriber_id')->value.
                                "' for contract id '".$c->stash->{contract}->id."'",
                            desc  => $c->loc('Invalid provisioning subscriber id detected.'),
                        );
                        # TODO: throw exception here!
                        $err = 1;
                        last;
                    }
                    my ($range_id, $key_num) = split /\./, $line->field('line')->value;
                    my $type = $line->field('type')->value;
                    $fdev->autoprov_field_device_lines->create({
                        subscriber_id => $prov_subscriber->id,
                        linerange_id => $range_id,
                        key_num => $key_num,
                        line_type => $type,
                    });
                }
            });
            unless($err) {
                $c->flash(messages => [{type => 'success', text => $c->loc('PBX device successfully updated') }]);
            }
        } catch ($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update PBX device'),
            );
        }

        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action('/customer/details', $c->req->captures));
    }

    $c->stash(
        edit_flag => 1,
        form => $form,
        description => $c->loc('PBX Device'),
    );
}

sub pbx_device_delete :Chained('pbx_device_base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;

    try {
        $c->stash->{pbx_device}->delete;
        $c->flash(messages => [{type => 'success', text => $c->loc('PBX Device successfully deleted') }]);
    } catch($e) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => "failed to delete PBX device with id '".$c->stash->{pbx_device}->id."': $e",
            desc => $c->loc('Failed to delete PBX device'),
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
        $c->flash(messages => [{type => 'success', text => $c->loc('Successfully redirected request to device') }]);
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action('/customer/details', [ $c->req->captures->[0] ]));
    }
    my $dev = $c->stash->{pbx_device};

    my $t = Template->new;
    my $conf = {
        client => {
            ip => '__NGCP_CLIENT_IP__',
            
        },
        server => {
            uri => 'http://' . $c->req->uri->host . ':' . ($c->config->{web}->{autoprov_plain_port} // '1444') . '/device/autoprov/config',
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
