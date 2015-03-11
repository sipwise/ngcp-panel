package NGCP::Panel::Controller::Customer;
use Sipwise::Base;
use namespace::sweep;
BEGIN { extends 'Catalyst::Controller'; }
use JSON qw(decode_json encode_json);
use IPC::System::Simple qw/capturex EXIT_ANY $EXITVAL/;
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
use NGCP::Panel::Form::Customer::PbxFieldDeviceSync;
use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::Navigation;
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Subscriber;
use NGCP::Panel::Utils::Sounds;
use NGCP::Panel::Utils::Contract;
use NGCP::Panel::Utils::DeviceBootstrap;
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
        { name => "billing_mappings_actual.billing_mappings.product.name", search => 1, title => $c->loc("Product") },
        { name => "billing_mappings_actual.billing_mappings.billing_profile.name", search => 1, title => $c->loc("Billing Profile") },
        { name => "status", search => 1, title => $c->loc("Status") },
        { name => "max_subscribers", search => 1, title => $c->loc("Max Number of Subscribers") },
    ]);
    my $rs = NGCP::Panel::Utils::Contract::get_customer_rs(c => $c);

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
        { name => "billing_mappings_actual.billing_mappings.product.name", search => 1, title => $c->loc("Product") },
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
                   'billing_profile.create'  => $c->uri_for('/billing/create'),
                   'subscriber_email_template.create'  => $c->uri_for('/emailtemplate/create'),
                   'passreset_email_template.create'  => $c->uri_for('/emailtemplate/create'),
                   'invoice_template.create'  => $c->uri_for('/invoicetemplate/create'),
        },
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                foreach(qw/contact subscriber_email_template passreset_email_template invoice_email_template invoice_template/){
                    $form->values->{$_.'_id'} = $form->values->{$_}{id} || undef;
                    delete $form->values->{$_};
                }
                my $bprof_id = $form->values->{billing_profile}{id};
                delete $form->values->{billing_profile};
                $form->values->{create_timestamp} = $form->values->{modify_timestamp} = NGCP::Panel::Utils::DateTime::current_local;
                $form->values->{external_id} = $form->field('external_id')->value;
                my $product_id = $form->values->{product}{id};
                delete $form->values->{product};
                unless($product_id) {
                    $product_id = $c->model('DB')->resultset('products')->find({ class => 'sipaccount' })->id;
                }
                unless($form->values->{max_subscribers} && length($form->values->{max_subscribers})) {
                    delete $form->values->{max_subscribers};
                }
                my $contract = $schema->resultset('contracts')->create($form->values);
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
                NGCP::Panel::Utils::Message->info(
                    c => $c,
                    cname => 'create',
                    desc  => $c->loc('Customer #[_1] successfully created', $contract->id),
                );
            });
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create customer contract'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/contract'));
    }

    $c->stash(create_flag => 1);
    $c->stash(form => $form);
}

sub base :Chained('list_customer') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $contract_id) = @_;
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
    my $etime = $stime->clone->add(months => 1)->subtract(seconds => 1);
   
    my $balance;
    try {
        $balance = NGCP::Panel::Utils::Contract::get_contract_balance(
                    c => $c,
                    profile => $billing_mapping->billing_profile,
                    contract => $contract_rs->first,
                    stime => $stime,
                    etime => $etime
        );
    } catch($e) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => $e,
            desc  => $c->loc('Failed to get contract balance.'),
        );
        $c->response->redirect($c->uri_for());
        return;
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

    $c->stash->{invoice_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => $c->loc("#") },
        { name => "serial", search => 1, title => $c->loc("Serial #") },
        { name => "period_start", search => 1, title => $c->loc("Start") },
        { name => "period_end", search => 1, title => $c->loc("End") },
        { name => "amount_net", search => 1, title => $c->loc("Net Amount") },
        { name => "amount_vat", search => 1, title => $c->loc("VAT Amount") },
        { name => "amount_total", search => 1, title => $c->loc("Total Amount") },
    ]);


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

    my $contract = $c->stash->{contract};
    my $billing_mapping = $c->stash->{billing_mapping};
    my $posted = ($c->request->method eq 'POST');
    my $form;
    my $params = { $contract->get_inflated_columns };
    foreach(qw/contact subscriber_email_template passreset_email_template invoice_email_template invoice_template/){
        $params->{$_}{id} = delete $params->{$_.'_id'};
    }
    $params->{product}{id} = $billing_mapping->product_id;
    $params->{billing_profile}{id} = $billing_mapping->billing_profile_id;
    $params = $params->merge($c->session->{created_objects});
    $c->log->debug('customer/edit');
    if($c->config->{features}->{cloudpbx}) {
        $c->log->debug('ProductSelect');
        $form = NGCP::Panel::Form::Contract::ProductSelect->new(ctx => $c);
    } else {
        $c->log->debug('Basic');
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
                   'billing_profile.create'  => $c->uri_for('/billing/create'),
                   'subscriber_email_template.create'  => $c->uri_for('/emailtemplate/create'),
                   'passreset_email_template.create'  => $c->uri_for('/emailtemplate/create'),
                   'invoice_email_template.create'  => $c->uri_for('/emailtemplate/create'),
                   'invoice_template.create'  => $c->uri_for('/invoicetemplate/create'),
        },
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                foreach(qw/contact subscriber_email_template passreset_email_template invoice_email_template invoice_template/){
                    $form->values->{$_.'_id'} = $form->values->{$_}{id} || undef;
                    delete $form->values->{$_};
                }
                my $bprof_id = $form->values->{billing_profile}{id};
                delete $form->values->{billing_profile};
                $form->{modify_timestamp} = NGCP::Panel::Utils::DateTime::current_local;
                my $product_id = $form->values->{product}{id} || $billing_mapping->product_id;
                delete $form->values->{product};
                $form->values->{external_id} = $form->field('external_id')->value;
                unless($form->values->{max_subscribers} && length($form->values->{max_subscribers})) {
                    $form->values->{max_subscribers} = undef;
                }
                my $old_bprof_id = $billing_mapping->billing_profile_id;
                my $old_prepaid = $billing_mapping->billing_profile->prepaid;
                my $old_ext_id = $contract->external_id // '';
                my $old_status = $contract->status;
                $contract->update($form->values);
                my $new_ext_id = $contract->external_id // '';

                # if status changed, populate it down the chain
                if($contract->status ne $old_status) {
                    NGCP::Panel::Utils::Contract::recursively_lock_contract(
                        c => $c,
                        contract => $contract,
                    );
                }

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
            });
            NGCP::Panel::Utils::Message->info(
                c => $c,
                data => { $contract->get_inflated_columns },
                desc => $c->loc('Customer #[_1] successfully updated', $contract->id),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                data  => { $contract->get_inflated_columns },
                desc  => $c->loc('Failed to update customer contract'),
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
        NGCP::Panel::Utils::Message->error(
            c => $c,
            desc  => $c->loc('Cannot terminate contract with the id 1'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/contract'));
    }

    try {
        my $old_status = $contract->status;
        my $schema = $c->model('DB');
        $schema->txn_do(sub {
            $contract->voip_contract_preferences->delete;
            $contract->update({ 
                status => 'terminated',
                terminate_timestamp => NGCP::Panel::Utils::DateTime::current_local,
            });
            # if status changed, populate it down the chain
            if($contract->status ne $old_status) {
                NGCP::Panel::Utils::Contract::recursively_lock_contract(
                    c => $c,
                    contract => $contract,
                    schema => $schema,
                );
            }
        });
        NGCP::Panel::Utils::Message->info(
            c => $c,
            data => { $contract->get_inflated_columns },
            desc => $c->loc('Customer successfully terminated'),
        );
    } catch ($e) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => $e,
            data  => { $contract->get_inflated_columns },
            desc  => $c->loc('Failed to terminate contract'),
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
    $c->stash->{pilot} = $c->stash->{subscribers}->search({
        'provisioning_voip_subscriber.is_pbx_pilot' => 1,
    })->first;

    
    my $params = {};

    if($c->config->{features}->{cloudpbx} && $pbx) {
        $c->stash(customer_id => $c->stash->{contract}->id);
        # we need to create a pilot subscriber first
        unless($c->stash->{pilot}) {
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
                subscriber => $c->stash->{pilot},
                params => $params,
                unselect => 1, # no numbers assigned yet, keep selection list empty
            );
            NGCP::Panel::Utils::Subscriber::prepare_group_select(
                c => $c,
                subscriber => $c->stash->{pilot},
                params => $params,
                unselect => 1, # no groups assigned yet, keep selection list empty
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
                my $pbxgroups = [];
                if($pbx && !$pbxadmin) {
                    my $pilot = $c->stash->{pilot};
                    $form->params->{domain}{id} = $pilot->domain_id;
                    if ($form->value->{group_select}) {
                        $pbxgroups = decode_json($form->value->{group_select});
                    }
                    my $base_number = $pilot->primary_number;
                    if($base_number) {
                        $preferences->{cloud_pbx_base_cli} = $base_number->cc . $base_number->ac . $base_number->sn;
                        if(defined $form->params->{pbx_extension}) {
                            $form->params->{e164}{cc} = $base_number->cc;
                            $form->params->{e164}{ac} = $base_number->ac;
                            $form->params->{e164}{sn} = $base_number->sn . $form->params->{pbx_extension};
                        }
                    }
                }
                if($pbx) {
                    $form->params->{is_pbx_pilot} = 1 if $pbxadmin;
                    $preferences->{cloud_pbx} = 1;
                    $preferences->{cloud_pbx_ext} = $form->params->{pbx_extension};
                    if($pbxadmin && $form->params->{e164}{cc} && $form->params->{e164}{sn}) {
                        $preferences->{cloud_pbx_base_cli} = $form->params->{e164}{cc} . 
                                                             ($form->params->{e164}{ac} // '') . 
                                                             $form->params->{e164}{sn};
                    }

                    if($c->stash->{pilot}) {
                        my $profile_set = $c->stash->{pilot}->provisioning_voip_subscriber->voip_subscriber_profile_set;
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
                    admin_default => 0,
                    preferences => $preferences,
                );

                if($pbx && !$pbxadmin && $form->value->{alias_select}) {
                    NGCP::Panel::Utils::Subscriber::update_subadmin_sub_aliases(
                        c => $c,
                        schema => $schema,
                        subscriber => $billing_subscriber,
                        contract_id => $billing_subscriber->contract_id,
                        alias_selected => decode_json($form->value->{alias_select}),
                        sadmin => $c->stash->{pilot},
                    );

                    foreach my $group_id(@{ $pbxgroups }) {
                        my $group = $c->model('DB')->resultset('voip_subscribers')->find($group_id);
                        next unless($group && $group->provisioning_voip_subscriber && $group->provisioning_voip_subscriber->is_pbx_group);
                        $billing_subscriber->provisioning_voip_subscriber->voip_pbx_groups->create({
                            group_id => $group->provisioning_voip_subscriber->id,
                        });
                        NGCP::Panel::Utils::Subscriber::update_pbx_group_prefs(
                            c => $c,
                            schema => $schema,
                            old_group_id => undef,
                            new_group_id => $group_id,
                            username => $billing_subscriber->username,
                            domain => $billing_subscriber->domain->domain,
                        );
                    }
                }

            });

            delete $c->session->{created_objects}->{domain};
            delete $c->session->{created_objects}->{group};
            NGCP::Panel::Utils::Message->info(
                c => $c,
                desc => $c->loc('Subscriber successfully created'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create subscriber'),
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
        NGCP::Panel::Utils::Message->info(
            c => $c,
            data => { $fraud_prefs->get_inflated_columns },
            desc => $c->loc('Fraud settings successfully changed!'),
        );
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
                data  => { $fraud_prefs->get_inflated_columns },
                desc  => $c->loc('Failed to clear fraud interval'),
            );
            $c->response->redirect($c->uri_for_action("/customer/details", [$c->stash->{contract}->id]));
            return;
        }
    }
    NGCP::Panel::Utils::Message->info(
        c => $c,
        data => { $fraud_prefs->get_inflated_columns },
        desc => $c->loc('Successfully cleared fraud interval!'),
    );
    $c->response->redirect($c->uri_for_action("/customer/details", [$c->stash->{contract}->id]));
    return;
}

sub edit_balance :Chained('base') :PathPart('balance/edit') :Args(0) {
    my ($self, $c) = @_;

    my $balance = $c->stash->{balance};
    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::CustomerBalance->new;
    my $params = { $balance->get_inflated_columns };
#        cash_balance => $balance->cash_balance,
#        free_time_balance => $balance->free_time_balance,
#    };

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
            $balance->update($form->values); 
            NGCP::Panel::Utils::Message->info(
                c => $c,
                desc => $c->loc('Account balance successfully changed!'),
            );
        }
        catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc => $c->loc('Failed to change account balance!'),
            );
        }
        $c->response->redirect($c->uri_for_action("/customer/details", [$c->stash->{contract}->id]));
        return;
    }

    $c->stash(close_target => $c->uri_for_action("/customer/details", [$c->stash->{contract}->id]));
    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
}
sub subscriber_ajax :Chained('base') :PathPart('subscriber/ajax') :Args(0) {
    my ($self, $c) = @_;
    my $res = $c->stash->{contract}->voip_subscribers->search({
        'provisioning_voip_subscriber.is_pbx_group' => 0,
        'me.status' => { '!=' => 'terminated' },

    },{
        join => 'provisioning_voip_subscriber',
    });
    NGCP::Panel::Utils::Datatables::process($c, $res, $c->stash->{subscriber_dt_columns});
    $c->detach( $c->view("JSON") );
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
    $c->stash->{pilot} = $c->stash->{subscribers}->search({
        'provisioning_voip_subscriber.is_pbx_pilot' => 1,
    })->first;
    unless($c->stash->{pilot}) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => 'cannot create pbx group without having a pilot subscriber',
            desc  => $c->loc("Can't create a PBX group without having a pilot subscriber."),
        );
        NGCP::Panel::Utils::Navigation::back_or($c,
            $c->uri_for_action('/customer/details', [$c->stash->{contract}->id])
        );
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
                my $pilot = $c->stash->{pilot};

                my $base_number = $pilot->primary_number;
                if($base_number) {
                    $preferences->{cloud_pbx_base_cli} = $base_number->cc . $base_number->ac . $base_number->sn;
                    if(defined $form->params->{pbx_extension}) {
                        $form->params->{e164}{cc} = $base_number->cc;
                        $form->params->{e164}{ac} = $base_number->ac;
                        $form->params->{e164}{sn} = $base_number->sn . $form->params->{pbx_extension};
                    }

                }
                $form->params->{is_pbx_pilot} = 0;
                $form->params->{is_pbx_group} = 1;
                $form->params->{domain}{id} = $pilot->domain_id;
                $form->params->{status} = 'active';
                $preferences->{cloud_pbx} = 1;
                $preferences->{cloud_pbx_hunt_policy} = $form->params->{pbx_hunt_policy};
                $preferences->{cloud_pbx_hunt_timeout} = $form->params->{pbx_hunt_timeout};
                $preferences->{cloud_pbx_ext} = $form->params->{pbx_extension};
                my $billing_subscriber = NGCP::Panel::Utils::Subscriber::create_subscriber(
                    c => $c,
                    schema => $schema,
                    contract => $c->stash->{contract},
                    params => $form->params,
                    admin_default => 0,
                    preferences => $preferences,
                );
                NGCP::Panel::Utils::Events::insert(
                    c => $c, schema => $schema, type => 'start_huntgroup',
                    subscriber => $billing_subscriber, old_status => undef, 
                    new_status => $billing_subscriber->provisioning_voip_subscriber->profile_id,
                );
                $c->session->{created_objects}->{group} = { id => $billing_subscriber->id };
            });
            NGCP::Panel::Utils::Message->info(
                c => $c,
                desc => $c->loc('PBX group successfully created'),
            );
        } catch ($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create PBX group'),
            );
        }

        NGCP::Panel::Utils::Navigation::back_or($c, 
            $c->uri_for_action('/customer/details', [$c->stash->{contract}->id])
        );
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
        NGCP::Panel::Utils::Navigation::back_or($c, 
            $c->uri_for_action('/customer/details', [$c->stash->{contract}->id])
        );
    }
    $c->stash->{pilot} = $c->stash->{subscribers}->search({
        'provisioning_voip_subscriber.is_pbx_pilot' => 1,
    })->first;

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
                my $old_extension = $c->stash->{pbx_group}->provisioning_voip_subscriber->pbx_extension;
                $c->stash->{pbx_group}->provisioning_voip_subscriber->update($form->params);
                NGCP::Panel::Utils::Subscriber::update_subscriber_pbx_policy(
                    c => $c, 
                    prov_subscriber => $c->stash->{pbx_group}->provisioning_voip_subscriber,
                    'values'   => {
                        cloud_pbx_hunt_policy  => $form->params->{pbx_hunt_policy},
                        cloud_pbx_hunt_timeout => $form->params->{pbx_hunt_timeout},
                    }
                );
                if(defined $form->params->{pbx_extension} &&
                        $form->params->{pbx_extension} ne $old_extension) {
                    my $sub = $c->stash->{pbx_group};
                    my $base_number = $c->stash->{pilot}->primary_number;
                    my $e164 = {
                        cc => $sub->primary_number->cc,
                        ac => $sub->primary_number->ac,
                        sn => $base_number->sn . $form->params->{pbx_extension},
                    };
                    NGCP::Panel::Utils::Subscriber::update_subscriber_numbers(
                        c => $c,
                        schema => $schema,
                        subscriber_id => $sub->id,
                        reseller_id => $sub->contract->contact->reseller_id,
                        primary_number => $e164,
                    );
                }
            });
            NGCP::Panel::Utils::Message->info(
                c => $c,
                desc  => $c->loc('PBX group successfully updated'),
            );
        } catch ($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update PBX group'),
            );
        }

        NGCP::Panel::Utils::Navigation::back_or($c, 
            $c->uri_for_action('/customer/details', [$c->stash->{contract}->id])
        );
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
            my $err;
            my $schema = $c->model('DB');
            $schema->txn_do( sub {
                my $station_name = $form->params->{station_name};
                my $identifier = lc $form->params->{identifier};
                if($identifier =~ /^([a-f0-9]{2}:){5}[a-f0-9]{2}$/) {
                    $identifier =~ s/\://g;
                }
                my $profile_id = $form->params->{profile_id};
                my $fdev = $c->stash->{contract}->autoprov_field_devices->create({
                    profile_id => $profile_id,
                    identifier => $identifier,
                    station_name => $station_name,
                });
                if($fdev->profile->config->device->bootstrap_method eq "redirect_yealink") {
                    my @chars = ("A".."Z", "a".."z", "0".."9");
                    my $device_key = "";
                    $device_key .= $chars[rand @chars] for 0 .. 15;
                    $fdev->update({ encryption_key => $device_key });
                }

                $err = NGCP::Panel::Utils::DeviceBootstrap::dispatch(
                    $c, 'register', $fdev);
                unless($err) {
                    my $err_lines = $c->forward('pbx_device_lines_update', [$schema, $fdev, [$form->field('line')->fields]]);
                    !$err and ( $err = $err_lines );
                }

            });
            unless($err) {
                NGCP::Panel::Utils::Message->info(
                    c => $c,
                    desc => $c->loc('PBX device successfully created'),
                );
            } else {
                die $err;
            }
        } catch ($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create PBX device'),
            );
        }

        NGCP::Panel::Utils::Navigation::back_or($c, 
            $c->uri_for_action('/customer/details', [$c->stash->{contract}->id])
        );
    }

    $c->stash(
        device_flag => 1,
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
        NGCP::Panel::Utils::Navigation::back_or($c, 
            $c->uri_for_action('/customer/details', [$c->stash->{contract}->id])
        );
    }
    if($dev->contract->id != $c->stash->{contract}->id) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => "invalid voip pbx device id $dev_id for customer id '".$c->stash->{contract}->id."'",
            desc  => $c->loc('PBX device with id [_1] does not exist for this customer.',$dev_id),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, 
            $c->uri_for_action('/customer/details', [$c->stash->{contract}->id])
        );
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
    my $form = NGCP::Panel::Form::Customer::PbxFieldDevice->new(ctx => $c);
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
                if($identifier =~ /^([a-f0-9]{2}:){5}[a-f0-9]{2}$/) {
                    $identifier =~ s/\://g;
                }
                my $old_identifier = $fdev->identifier;
                my $profile_id = $form->params->{profile_id};
                $fdev->update({
                    profile_id => $profile_id,
                    identifier => $identifier,
                    station_name => $station_name,
                });

                unless($fdev->identifier eq $old_identifier) {
                    $err = NGCP::Panel::Utils::DeviceBootstrap::dispatch(
                        $c, 'register', $fdev, $old_identifier);
                }

                unless($err) {
                    $fdev->autoprov_field_device_lines->delete_all;
                    my $err_lines = $c->forward('pbx_device_lines_update', [$schema, $fdev, [$form->field('line')->fields]]);
                    !$err and ( $err = $err_lines );
                }

            });
            unless($err) {
                NGCP::Panel::Utils::Message->info(
                    c => $c,
                    desc  => $c->loc('PBX device successfully updated'),
                );
            } else {
                die $err;
            }
        } catch ($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update PBX device'),
            );
        }

        NGCP::Panel::Utils::Navigation::back_or($c, 
            $c->uri_for_action('/customer/details', [$c->stash->{contract}->id])
        );
        return;
    }

    $c->stash(
        device_flag => 1,
        edit_flag => 1,
        form => $form,
        description => $c->loc('PBX Device'),
    );
}
sub pbx_device_lines_update :Private{
    my($self, $c, $schema, $fdev, $lines) = @_;
    my $err = 0;
    foreach my $line(@$lines) {
        next unless($line->field('subscriber_id')->value);
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
        } else {
            my ($range_id, $key_num) = split /\./, $line->field('line')->value;
            my $type = $line->field('type')->value;
            my $unit = $line->field('extension_unit')->value;
            $fdev->autoprov_field_device_lines->create({
                subscriber_id  => $prov_subscriber->id,
                linerange_id   => $range_id,
                key_num        => $key_num,
                line_type      => $type,
                extension_unit => $unit,
            });
        }
    }
    return $err;
}
sub pbx_device_delete :Chained('pbx_device_base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;

    try {
        my $fdev = $c->stash->{pbx_device};
        NGCP::Panel::Utils::DeviceBootstrap::dispatch(
            $c, 'unregister', $fdev, $fdev->identifier
        );
        $fdev->delete;
        NGCP::Panel::Utils::Message->info(
            c => $c,
            data => { $c->stash->{pbx_device}->get_inflated_columns },
            desc => $c->loc('PBX Device successfully deleted'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => "failed to delete PBX device with id '".$c->stash->{pbx_device}->id."': $e",
            data => { $c->stash->{pbx_device}->get_inflated_columns },
            desc => $c->loc('Failed to delete PBX device'),
        );
    }

    NGCP::Panel::Utils::Navigation::back_or($c, 
        $c->uri_for_action('/customer/details', [$c->stash->{contract}->id])
    );
}

sub pbx_device_sync :Chained('pbx_device_base') :PathPart('sync') :Args(0) {
    my ($self, $c) = @_;

    my $form = NGCP::Panel::Form::Customer::PbxFieldDeviceSync->new;
    my $posted = ($c->req->method eq 'POST');

    my $dev = $c->stash->{pbx_device};
    foreach my $line($dev->autoprov_field_device_lines->search({
        line_type => 'private',
        })->all) {

        my $sub = $line->provisioning_voip_subscriber;
        next unless($sub);
        my $reg_rs = $c->model('DB')->resultset('location')->search({
            username => $sub->username,
        });
        if($c->config->{features}->{multidomain}) {
            $reg_rs = $reg_rs->search({
                domain => $sub->domain->domain,
            });
        }
        my $uri = $sub->username . '@' . $sub->domain->domain;
        if($reg_rs->count) {
            $c->log->debug("trigger device resync for $uri as it is registered");

            my $proxy_rs = $c->model('DB')->resultset('xmlgroups')
                ->search_rs({name => 'proxy'})
                ->search_related('xmlhostgroups')->search_related('host');
            my $proxy = $proxy_rs->first;
            unless($proxy) {
                    NGCP::Panel::Utils::Message->error(
                        c => $c,
                        desc => $c->loc('Failed to trigger config reload via SIP'),
                        error => 'Failed to load proxy from xmlhosts',
                    );
                    NGCP::Panel::Utils::Navigation::back_or($c, 
                        $c->uri_for_action('/customer/details', [$c->stash->{contract}->id])
                    );
                    return;
            }

            my @cmd_args = ($c->config->{cloudpbx}->{sync}, 
                $sub->username, $sub->domain->domain, 
                $sub->password, $proxy->ip . ":" . $proxy->sip_port);
            my @out = capturex(EXIT_ANY, "/bin/sh", @cmd_args);
            if($EXITVAL != 0) {
                use Data::Dumper;
                NGCP::Panel::Utils::Message->error(
                    c => $c,
                    desc => $c->loc('Failed to trigger config reload via SIP'),
                    error => 'Result: ' . Dumper \@out,
                );
            } else {
                NGCP::Panel::Utils::Message->info(
                    c => $c,
                    desc => $c->loc('Successfully triggered config reload via SIP'),
                );
            }
            NGCP::Panel::Utils::Navigation::back_or($c, 
                $c->uri_for_action('/customer/details', [$c->stash->{contract}->id])
            );
            return;
        }
    }


    my $params = {};

    $form->process(
        posted => $posted,
        params => $c->req->params,
        item => $params,
    );

    if($posted && $form->validated) {
        NGCP::Panel::Utils::Message->info(
            c => $c,
            desc => $c->loc('Successfully redirected request to device'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, 
            $c->uri_for_action('/customer/details', [$c->stash->{contract}->id])
        );
    }

    my $schema = $c->config->{deviceprovisioning}->{secure} ? 'https' : 'http';
    my $host = $c->config->{deviceprovisioning}->{host} // $c->req->uri->host;
    my $port = $c->config->{deviceprovisioning}->{port} // 1444;

    my $t = Template->new;
    my $conf = {
        client => {
            ip => '__NGCP_CLIENT_IP__',
            
        },
        server => {
            uri => "$schema://$host:$port/device/autoprov/config",
        },
    };
    my $sync_params_rs = $dev->profile->config->device->autoprov_sync->search_rs({
        'autoprov_sync_parameters.bootstrap_method'  => 'http',
    },{
        join   => 'autoprov_sync_parameters',
        select => ['me.parameter_value'],
    });
    my ($sync_uri, $real_sync_uri) = ("", "");
    $sync_uri = $sync_params_rs->search({
        'autoprov_sync_parameters.parameter_name' => 'sync_uri',
    });
    if($sync_uri && $sync_uri->first){
        $sync_uri = $sync_uri->first->parameter_value;
    }
    $t->process(\$sync_uri, $conf, \$real_sync_uri);

    my ($sync_params_field, $real_sync_params) = ("", "");
    $sync_params_field = $sync_params_rs->search({
        'autoprov_sync_parameters.parameter_name' => 'sync_params',
    });
    if($sync_params_field && $sync_params_field->first){
        $sync_params_field = $sync_params_field->first->parameter_value;
    }
    my ($sync_method) = "";
    $sync_method = $sync_params_rs->search({
        'autoprov_sync_parameters.parameter_name' => 'sync_method',
    });
    if($sync_method && $sync_method->first){
        $sync_method = $sync_method->first->parameter_value;
    }
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
        autoprov_method => $sync_method,
        autoprov_params => \@sync_params,
    );
}

sub preferences :Chained('base') :PathPart('preferences') :Args(0) {
    my ($self, $c) = @_;

    $self->load_preference_list($c);
    $c->stash(template => 'customer/preferences.tt');
}


sub preferences_base :Chained('base') :PathPart('preferences') :CaptureArgs(1) {
    my ($self, $c, $pref_id) = @_;

    $self->load_preference_list($c);

    $c->stash->{preference_meta} = $c->model('DB')
        ->resultset('voip_preferences')
        ->single({id => $pref_id});
    if($c->user->roles eq 'subscriberadmin' && !$c->stash->{preference_meta}->expose_to_customer) {
        $c->log->error("invalid access to pref_id '$pref_id' by provisioning subscriber id '".$c->user->id."'");
        $c->detach('/denied_page');
    } 

    $c->stash->{preference} = $c->model('DB')
        ->resultset('voip_contract_preferences')
        ->search({
            attribute_id => $pref_id,
            contract_id => $c->stash->{contract}->id,
        });
    my @values = $c->stash->{preference}->get_column("value")->all;
    $c->stash->{preference_values} = \@values;
    $c->stash(template => 'customer/preferences.tt');
}

sub preferences_edit :Chained('preferences_base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;
   
    $c->stash(edit_preference => 1);

    my @enums = $c->stash->{preference_meta}
        ->voip_preferences_enums
        ->search({contract_pref => 1})
        ->all;
    
    my $pref_rs = $c->stash->{contract}->voip_contract_preferences;

    NGCP::Panel::Utils::Preferences::create_preference_form( c => $c,
        pref_rs => $pref_rs,
        enums   => \@enums,
        base_uri => $c->uri_for_action('/customer/preferences', [$c->stash->{contract}->id]),
        edit_uri => $c->uri_for_action('/customer/preferences_edit', [$c->stash->{contract}->id]),
    );
}

sub load_preference_list :Private {
    my ($self, $c) = @_;
    
    my $contract_pref_values = $c->model('DB')
        ->resultset('voip_preferences')
        ->search({
                contract_id => $c->stash->{contract}->id,
            },{
                prefetch => 'voip_contract_preferences',
            });
        
    my %pref_values;
    foreach my $value($contract_pref_values->all) {
    
        $pref_values{$value->attribute} = [
            map {$_->value} $value->voip_contract_preferences->all
        ];
    }

    my $reseller_id = $c->stash->{contract}->contact->reseller_id;

    my $ncos_levels_rs = $c->model('DB')
        ->resultset('ncos_levels')
        ->search_rs({ reseller_id => $reseller_id, });
    $c->stash(ncos_levels_rs => $ncos_levels_rs,
              ncos_levels    => [$ncos_levels_rs->all]);

    NGCP::Panel::Utils::Preferences::load_preference_list( c => $c,
        pref_values => \%pref_values,
        contract_pref => 1,
        customer_view => ($c->user->roles eq 'subscriberadmin' ? 1 : 0),
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
