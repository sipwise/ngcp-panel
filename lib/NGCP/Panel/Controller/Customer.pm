package NGCP::Panel::Controller::Customer;
use NGCP::Panel::Utils::Generic qw(:all);
use Sipwise::Base;
use parent 'Catalyst::Controller';

use NGCP::Panel::Form;
use JSON qw(decode_json encode_json);
use IPC::System::Simple qw/capturex EXIT_ANY $EXITVAL/;
use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::Navigation;
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Subscriber;
use NGCP::Panel::Utils::Sounds;
use NGCP::Panel::Utils::Contract;
use NGCP::Panel::Utils::ProfilePackages;
use NGCP::Panel::Utils::BillingMappings qw();
use NGCP::Panel::Utils::DeviceBootstrap;
use NGCP::Panel::Utils::Voucher;
use NGCP::Panel::Utils::ContractLocations qw();
use NGCP::Panel::Utils::Events qw();
use NGCP::Panel::Utils::Phonebook;
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

    my $now = NGCP::Panel::Utils::DateTime::current_local;
    $c->stash->{contract_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => $c->loc("#") },
        { name => "external_id", search => 1, title => $c->loc("External #") },
        { name => "contact.reseller.name", search => 1, title => $c->loc("Reseller") },
        { name => "contact.email", search => 1, title => $c->loc("Contact Email") },
        { name => "contact.firstname", search => 1, title => '' },
        { name => "contact.lastname", search => 1, title => $c->loc("Name"),
            custom_renderer => 'function ( data, type, full ) { var sep = (full.contact_firstname && full.contact_lastname) ? " " : ""; return (full.contact_firstname || "") + sep + (full.contact_lastname || ""); }' },
        { name => "product.name", search => 1, title => $c->loc("Product") },
        { name => 'billing_profile_name', accessor => "billing_profile_name", search => 0, title => $c->loc('Billing Profile'),
          literal_sql => '""' },
        { name => "status", search => 1, title => $c->loc("Status") },
        { name => "max_subscribers", search => 1, title => $c->loc("Max. Subscribers") },
    ]);

    my $rs = NGCP::Panel::Utils::Contract::get_customer_rs(c => $c); #, now => $now);
    my $rs_all = NGCP::Panel::Utils::Contract::get_contract_rs(
        schema => $c->model('DB'),
        #now => $now,
        include_terminated => 1,
    );
    $c->stash(
        contract_select_rs => $rs,
        contract_select_all_rs => $rs_all,
        template => 'customer/list.tt',
        now => $now
    );
}

sub root :Chained('list_customer') :PathPart('') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
}

sub ajax :Chained('list_customer') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    my $now = NGCP::Panel::Utils::DateTime::current_local; #uniform ts
    my $res = $c->stash->{contract_select_rs};
    NGCP::Panel::Utils::Datatables::process($c, $res, $c->stash->{contract_dt_columns}, sub {
        my $item = shift;
        my %contact = $item->contact->get_inflated_columns;
        my %result = map { (ref $contact{$_}) ? () : ('contact_'.$_ => $contact{$_}); } keys %contact;
        my $bm_actual = NGCP::Panel::Utils::BillingMappings::get_actual_billing_mapping(c => $c, contract => $item, now => $now, );
        $result{'billing_profile_name'} = $bm_actual->billing_profile->name if $bm_actual;
        return %result;
    },);
    $c->detach( $c->view("JSON") );
}

sub ajax_reseller_filter :Chained('list_customer') :PathPart('ajax/reseller') :Args(1) {
    my ($self, $c, $reseller_id) = @_;

    unless($reseller_id && is_int($reseller_id)) {
        NGCP::Panel::Utils::Message::error(
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
        { name => "product.name", search => 1, title => $c->loc("Product") },
        { name => "contact.email", search => 1, title => $c->loc("Contact Email") },
        { name => "status", search => 1, title => $c->loc("Status") },
    ]);
    NGCP::Panel::Utils::Datatables::process($c, $rs,  $reseller_customer_columns);
    $c->detach( $c->view("JSON") );
}

sub ajax_package_filter :Chained('list_customer') :PathPart('ajax/package') :Args(1) {
    my ($self, $c, $package_id) = @_;

    unless($package_id && is_int($package_id)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Invalid profile package id detected',
            desc  => $c->loc('Invalid profile package id detected'),
        );
        $c->response->redirect($c->uri_for());
        return;
    }

    my $rs = $c->stash->{contract_select_rs}->search_rs({
        'profile_package_id' => $package_id,
    },undef);
    my $package_customer_columns = NGCP::Panel::Utils::Datatables::set_columns($c, [
        NGCP::Panel::Utils::ProfilePackages::get_customer_datatable_cols($c)
    ]);
    NGCP::Panel::Utils::Datatables::process($c, $rs,  $package_customer_columns);
    $c->detach( $c->view("JSON") );
}

sub ajax_pbx_only :Chained('list_customer') :PathPart('ajax_pbx_only') :Args(0) {
    my ($self, $c) = @_;
    my $now = NGCP::Panel::Utils::DateTime::current_local; #uniform ts
    my $res = $c->stash->{contract_select_rs}->search_rs({'product.class' => 'pbxaccount'});
    NGCP::Panel::Utils::Datatables::process($c, $res, $c->stash->{contract_dt_columns}, sub {
        my $item = shift;
        my %contact = $item->contact->get_inflated_columns;
        my %result = map { (ref $contact{$_}) ? () : ('contact_'.$_ => $contact{$_}); } keys %contact;
        my $bm_actual = NGCP::Panel::Utils::BillingMappings::get_actual_billing_mapping(c => $c, contract => $item, now => $now, );
        $result{'billing_profile_name'} = $bm_actual->billing_profile->name if $bm_actual;
        return %result;
    },);
    $c->detach( $c->view("JSON") );
}

sub create :Chained('list_customer') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    if($c->user->roles eq "subscriberadmin") {
        $c->detach('/denied_page');
    }
    my $posted = ($c->request->method eq 'POST');
    my $form;
    my $params = {};
    $params = merge($params, $c->session->{created_objects});

    unless ($self->is_valid_contact($c, $params->{contact}{id})) {
        delete $params->{contact};
    }

    if($c->config->{features}->{cloudpbx}) {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Contract::ProductSelect", $c);
    } else {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Contract::Customer", $c);
        $c->stash->{type} = 'sipaccount';
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
                   'billing_profiles.profile.create'  => $c->uri_for('/billing/create'),
                   'billing_profiles.network.create'  => $c->uri_for('/network/create'),
                   'profile_package.create'  => $c->uri_for('/package/create'),
                   'subscriber_email_template.create'  => $c->uri_for('/emailtemplate/create'),
                   'passreset_email_template.create'  => $c->uri_for('/emailtemplate/create'),
                   'invoice_template.create'  => $c->uri_for('/invoicetemplate/create'),
        },
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->set_transaction_isolation('READ COMMITTED');
            $schema->txn_do(sub {
                foreach(qw/contact billing_profile profile_package product subscriber_email_template passreset_email_template invoice_email_template invoice_template/){
                    $form->values->{$_.'_id'} = $form->values->{$_}{id} || undef;
                    delete $form->values->{$_};
                }
                #$form->values->{profile_package_id} = undef unless NGCP::Panel::Utils::ProfilePackages::ENABLE_PROFILE_PACKAGES;
                $form->values->{create_timestamp} = $form->values->{modify_timestamp} = NGCP::Panel::Utils::DateTime::current_local;
                $form->values->{external_id} = $form->field('external_id')->value;
                $form->values->{product_id} //= $schema->resultset('products')->search_rs({ class => $c->stash->{type} })->first->id;
                unless($form->values->{max_subscribers} && length($form->values->{max_subscribers})) {
                    delete $form->values->{max_subscribers};
                }

                my $mappings_to_create = [];
                NGCP::Panel::Utils::BillingMappings::prepare_billing_mappings(
                    c => $c,
                    resource => $form->values,
                    mappings_to_create => $mappings_to_create,
                    err_code => sub {
                        my ($err,@fields) = @_;
                        die( [$err, "showdetails"] );
                    });

                my $contract = $schema->resultset('contracts')->create($form->values);
                NGCP::Panel::Utils::BillingMappings::append_billing_mappings(c => $c,
                    contract => $contract,
                    mappings_to_create => $mappings_to_create,
                );

                NGCP::Panel::Utils::ProfilePackages::create_initial_contract_balances(c => $c,
                    contract => $contract,
                );

                $c->session->{created_objects}->{contract} = { id => $contract->id };
                delete $c->session->{created_objects}->{contact};
                delete $c->session->{created_objects}->{billing_profile};
                delete $c->session->{created_objects}->{network};
                delete $c->session->{created_objects}->{profile_package};
                my $uri = $c->uri_for_action("/customer/details", [$contract->id]);
                NGCP::Panel::Utils::Message::info(
                    c => $c,
                    cname => 'create',
                    desc  => $c->loc('Customer #[_1] successfully created', $contract->id) . ' - <a href="' . $uri . '">' . $c->loc('Details') . '</a>',
                );
            });
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create customer contract'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/customer')); #/contract?
    }

    $c->stash(create_flag => 1);
    $c->stash(form => $form);
}

sub base :Chained('list_customer') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $contract_id) = @_;
    unless($contract_id && is_int($contract_id)) {
        NGCP::Panel::Utils::Message::error(
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
        },undef);
    my $contract_terminated_rs = $c->stash->{contract_select_all_rs}
        ->search({
            'me.id' => $contract_id,
        },undef);

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
    my $contract_first = $contract_rs->first;
    unless(defined($contract_first)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Customer was not found',
            desc  => $c->loc('Customer was not found'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/customer'));
    }


    my $now = $c->stash->{now};
    my $billing_mapping = NGCP::Panel::Utils::BillingMappings::get_actual_billing_mapping(c => $c, contract => $contract_first, now => $now, );
    my $billing_mappings_ordered = NGCP::Panel::Utils::BillingMappings::billing_mappings_ordered($contract_first->billing_mappings,$now,$billing_mapping);
    my $future_billing_mappings = NGCP::Panel::Utils::BillingMappings::billing_mappings_ordered(NGCP::Panel::Utils::BillingMappings::future_billing_mappings($contract_first->billing_mappings,$now));

    my $balance;
    try {
        my $schema = $c->model('DB');
        $schema->set_transaction_isolation('READ COMMITTED');
        $schema->txn_do(sub {
            $balance = NGCP::Panel::Utils::ProfilePackages::get_contract_balance(c => $c,
                        contract => $contract_rs->first,
                        now => $now);
        });
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            desc  => $c->loc('Failed to get contract balance.'),
        );
        $c->response->redirect($c->uri_for());
        return;
    }

    $c->stash->{balanceinterval_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        NGCP::Panel::Utils::ProfilePackages::get_balanceinterval_datatable_cols($c),
    ]);

    $c->stash->{topuplog_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        NGCP::Panel::Utils::ProfilePackages::get_topuplog_datatable_cols($c),
    ]);

    my $product = $contract_first->product;
    NGCP::Panel::Utils::Message::error(
        c => $c,
        error => "No product for customer contract id $contract_id found",
        desc  => $c->loc('No product for this customer contract found.'),
    ) unless($product);

    #my $product = $c->model('DB')->resultset('products')->find($product_id);
    #NGCP::Panel::Utils::Message::error(
    #    c => $c,
    #    error => "No product with id $product_id for customer contract id $contract_id found",
    #    desc  => $c->loc('Invalid product id for this customer contract.'),
    #) unless($product);

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
        $c->stash->{pbx_groups} = NGCP::Panel::Utils::Subscriber::get_pbx_subscribers_rs(
            c => $c,
            schema => $c->model('DB'),
            customer_id => $contract_id,
            is_group => 1,
        );
    }

    my $field_devs = [ $c->model('DB')->resultset('autoprov_field_devices')->search({
        'contract_id' => $contract_rs->first->id
    })->all ];

    # contents of details page:
    NGCP::Panel::Utils::Sounds::stash_soundset_list(c => $c, contract => $contract_first);
    $c->stash->{contact_hash} = { $contract_first->contact->get_inflated_columns };
    if(defined $contract_first->max_subscribers) {
       $c->stash->{subscriber_count} = $contract_first->voip_subscribers
        ->search({ status => { -not_in => ['terminated'] } })
        ->count;
    }

    my $locations = $contract_rs->first->voip_contract_locations->search_rs(
                undef,
                { join => 'voip_contract_location_blocks',
                  group_by => 'me.id' });

    $c->stash->{invoice_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => $c->loc("#") },
        { name => "serial", search => 1, title => $c->loc("Serial #") },
        { name => "period_start", search => 1, title => $c->loc("Start") },
        { name => "period_end", search => 1, title => $c->loc("End") },
        { name => "amount_net", search => 1, title => $c->loc("Net Amount") },
        { name => "amount_vat", search => 1, title => $c->loc("VAT Amount") },
        { name => "amount_total", search => 1, title => $c->loc("Total Amount") },
    ]);

    $c->stash->{location_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => $c->loc("#") },
        { name => "name", search => 1, title => $c->loc("Name") },
        { name => "description", search => 1, title => $c->loc("Description") },
        NGCP::Panel::Utils::ContractLocations::get_datatable_cols($c),
    ]);

    $c->stash->{phonebook_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => $c->loc("#") },
        { name => "name", search => 1, title => $c->loc("Name") },
        { name => "number", search => 1, title => $c->loc("Number") },
    ]);

    my ($is_timely,$timely_start,$timely_end) = NGCP::Panel::Utils::ProfilePackages::get_timely_range(
        package => $contract_first->profile_package,
        contract => $contract_first,
        balance => $balance,
        now => $now);
    my $notopup_expiration = NGCP::Panel::Utils::ProfilePackages::get_notopup_expiration(
        package => $contract_first->profile_package,
        contract => $contract_first,
        balance => $balance);

    $c->stash(pbx_devices => $field_devs);

    $c->stash(product => $product);
    $c->stash(balance => $balance);
    $c->stash(package => $contract_first->profile_package);
    $c->stash(timely_topup_start => $timely_start);
    $c->stash(timely_topup_end => $timely_end);
    $c->stash(notopup_expiration => $notopup_expiration);
    $c->stash(fraud => $contract_first->contract_fraud_preference);
    $c->stash(template => 'customer/details.tt');
    $c->stash(contract => $contract_first);
    $c->stash(contract_rs => $contract_rs);
    $c->stash(contract_terminated_rs => $contract_terminated_rs);
    $c->stash(billing_mapping => $billing_mapping );
    #$c->stash(now => $now );
    $c->stash(billing_mappings_ordered_result => $billing_mappings_ordered );
    $c->stash(future_billing_mappings => $future_billing_mappings );
    $c->stash(locations => $locations );
    $c->stash(phonebook => $contract_first->phonebook );
}

sub base_restricted :Chained('base') :PathPart('') :CaptureArgs(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
}

sub edit :Chained('base_restricted') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;

    my $contract = $c->stash->{contract};
    my $billing_mapping = $c->stash->{billing_mapping};
    my $now = $c->stash->{now};
    my $billing_profile = $billing_mapping->billing_profile;
    my $posted = ($c->request->method eq 'POST');
    my $form;
    my $params = { $contract->get_inflated_columns };
    foreach(qw/contact profile_package product subscriber_email_template passreset_email_template invoice_email_template invoice_template/){
        $params->{$_}{id} = delete $params->{$_.'_id'};
    }
    $params->{billing_profiles} = [ map { { $_->get_inflated_columns }; } $c->stash->{future_billing_mappings}->all ];
    $params->{billing_profile}->{id} = $billing_profile->id;
    $params = merge($params, $c->session->{created_objects}); # TODO: created billing profiles/networks will not be pre-selected
    #$c->log->debug('customer/edit');
    if($c->config->{features}->{cloudpbx}) {
        #$c->log->debug('ProductSelect');
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Contract::ProductSelect", $c);
    } else {
        #$c->log->debug('Basic');
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Contract::Customer", $c);
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
                   'billing_profiles.profile.create'  => $c->uri_for('/billing/create'),
                   'billing_profiles.network.create'  => $c->uri_for('/network/create'),
                   'profile_package.create'  => $c->uri_for('/package/create'),
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
            $schema->set_transaction_isolation('READ COMMITTED');
            $schema->txn_do(sub {
                foreach(qw/contact billing_profile profile_package product subscriber_email_template passreset_email_template invoice_email_template invoice_template/){
                    $form->values->{$_.'_id'} = $form->values->{$_}{id} || undef;
                    delete $form->values->{$_};
                }
                #$form->values->{profile_package_id} = undef unless NGCP::Panel::Utils::ProfilePackages::ENABLE_PROFILE_PACKAGES;
                $form->values->{modify_timestamp} = $now; #problematic for ON UPDATE current_timestamp columns
                $form->values->{external_id} = $form->field('external_id')->value;
                unless($form->values->{max_subscribers} && length($form->values->{max_subscribers})) {
                    $form->values->{max_subscribers} = undef;
                }
                my $mappings_to_create = [];
                my $delete_mappings = 0;
                my $set_package = ($form->values->{billing_profile_definition} // 'id') eq 'package';
                NGCP::Panel::Utils::BillingMappings::prepare_billing_mappings(
                    c => $c,
                    resource => $form->values,
                    old_resource => { $contract->get_inflated_columns },
                    mappings_to_create => $mappings_to_create,
                    now => $now,
                    delete_mappings => \$delete_mappings,
                    err_code => sub {
                        my ($err,@fields) = @_;
                        die( [$err, "showdetails"] );
                    });
                delete $form->values->{product_id};

                my $old_prepaid = $billing_mapping->billing_profile->prepaid;
                my $old_ext_id = $contract->external_id // '';
                my $old_status = $contract->status;
                my $old_package = $contract->profile_package;

                $contract->update($form->values);
                NGCP::Panel::Utils::BillingMappings::append_billing_mappings(c => $c,
                    contract => $contract,
                    mappings_to_create => $mappings_to_create,
                    now => $now,
                    delete_mappings => $delete_mappings,
                );

                my $balance = NGCP::Panel::Utils::ProfilePackages::catchup_contract_balances(c => $c,
                    contract => $contract,
                    old_package => $old_package,
                    now => $now);
                $balance = NGCP::Panel::Utils::ProfilePackages::resize_actual_contract_balance(c => $c,
                    contract => $contract,
                    old_package => $old_package,
                    balance => $balance,
                    now => $now,
                    profiles_added => ($set_package ? scalar @$mappings_to_create : 0),
                    );

                $billing_mapping = NGCP::Panel::Utils::BillingMappings::get_actual_billing_mapping(contract => $contract, schema => $schema, now => $now, );
                $billing_profile = $billing_mapping->billing_profile;

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

                NGCP::Panel::Utils::Subscriber::switch_prepaid_contract(c => $c,
                    prepaid => $billing_profile->prepaid,
                    contract => $contract,
                );
                if ($contract->status eq 'terminated') {
                    delete $c->stash->{close_target};
                }

                delete $c->session->{created_objects}->{contact};
                delete $c->session->{created_objects}->{network};
                delete $c->session->{created_objects}->{billing_profile};
                delete $c->session->{created_objects}->{profile_package};
            });
            NGCP::Panel::Utils::Message::info(
                c => $c,
                data => { $contract->get_inflated_columns },
                desc => $c->loc('Customer #[_1] successfully updated', $contract->id),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
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

sub terminate :Chained('base_restricted') :PathPart('terminate') :Args(0) {
    my ($self, $c) = @_;
    my $contract = $c->stash->{contract};

    if ($contract->id == 1) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            desc  => $c->loc('Cannot terminate contract with the id 1'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/customer')); #/contract?
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
            $contract = $c->stash->{contract_terminated_rs}->first;
            # if status changed, populate it down the chain
            if($contract->status ne $old_status) {
                NGCP::Panel::Utils::Contract::recursively_lock_contract(
                    c => $c,
                    contract => $contract,
                    schema => $schema,
                );
            }
        });
        NGCP::Panel::Utils::Message::info(
            c => $c,
            data => { $contract->get_inflated_columns },
            desc => $c->loc('Customer successfully terminated'),
        );
    } catch ($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            data  => { $contract->get_inflated_columns },
            desc  => $c->loc('Failed to terminate contract'),
        );
    };
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/customer')); #/contract?
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

        NGCP::Panel::Utils::Message::error(
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
            $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Customer::PbxAdminSubscriber", $c);
        } else {
            if($c->user->roles eq "subscriberadmin") {
                $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Customer::PbxExtensionSubscriberSubadmin", $c);
            } else {
                #1 means here that we will recreate form. For edit we disabled password field
                #Here we will get newly created form with all original fields
                $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Customer::PbxExtensionSubscriber", $c, 1);
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
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Customer::Subscriber", $c);
    }

    $params = merge($params, $c->session->{created_objects});
    if($c->stash->{pilot} && !$params->{domain}{id}) {
      $params->{domain}{id} = $c->stash->{pilot}->domain_id;
    }

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
            $schema->set_transaction_isolation('READ COMMITTED');
            $schema->txn_do(sub {
                my $preferences = {};
                my $pbx_group_ids = [];
                if($pbx && !$pbxadmin) {
                    my $pilot = $c->stash->{pilot};
                    $form->values->{domain}{id} ||= $pilot->domain_id;
                    if ($form->values->{group_select}) {
                        $pbx_group_ids = decode_json($form->values->{group_select});
                    }
                    my $base_number = $pilot->primary_number;
                    if($base_number) {
                        $preferences->{cloud_pbx_base_cli} = $base_number->cc . $base_number->ac . $base_number->sn;
                        if(defined $form->values->{pbx_extension}) {
                            $form->values->{e164}{cc} = $base_number->cc;
                            $form->values->{e164}{ac} = $base_number->ac;
                            $form->values->{e164}{sn} = $base_number->sn . $form->values->{pbx_extension};
                        }
                    }
                }
                if($pbx) {
                    $form->values->{is_pbx_pilot} = 1 if $pbxadmin;
                    $preferences->{cloud_pbx} = 1;
                    $preferences->{cloud_pbx_ext} = $form->values->{pbx_extension};
                    if($pbxadmin && $form->values->{e164}{cc} && $form->values->{e164}{sn}) {
                        $preferences->{cloud_pbx_base_cli} = $form->values->{e164}{cc} .
                                                             ($form->values->{e164}{ac} // '') .
                                                             $form->values->{e164}{sn};
                    }

                    if($c->stash->{pilot}) {
                        my $profile_set = $c->stash->{pilot}->provisioning_voip_subscriber->voip_subscriber_profile_set;
                        if($profile_set) {
                            $form->values->{profile_set}{id} = $profile_set->id;
                        }
                    }

                    # TODO: if number changes, also update cloud_pbx_base_cli

                    # TODO: only if it's not a fax/conf extension:
                    $preferences->{shared_buddylist_visibility} = 1;
                    $preferences->{display_name} = $form->values->{display_name}
                        if($form->values->{display_name});
                }
                if($c->stash->{contract}->external_id) {
                    $preferences->{ext_contract_id} = $c->stash->{contract}->external_id;
                }
                if(defined $form->values->{external_id}) {
                    $preferences->{ext_subscriber_id} = $form->values->{external_id};
                }
                my @events_to_create = ();
                my $event_context = { events_to_create => \@events_to_create };

                if($form->values->{lock} && ( $form->values->{lock} > 0 ) ){
                    $form->values->{status} = 'locked';
                }

                $billing_subscriber = NGCP::Panel::Utils::Subscriber::create_subscriber(
                    c => $c,
                    schema => $schema,
                    contract => $c->stash->{contract},
                    params => $form->values,
                    admin_default => 0,
                    preferences => $preferences,
                    event_context => $event_context,
                );

                if($billing_subscriber->status eq 'locked') {
                    $form->values->{lock} ||= 4;
                } else {
                    $form->values->{lock} = 0;
                }

                NGCP::Panel::Utils::Subscriber::lock_provisoning_voip_subscriber(
                    c => $c,
                    prov_subscriber => $billing_subscriber->provisioning_voip_subscriber,
                    level => $form->values->{lock},
                ) if ($billing_subscriber->provisioning_voip_subscriber);

                NGCP::Panel::Utils::ProfilePackages::underrun_lock_subscriber(c => $c, subscriber => $billing_subscriber);

                if($pbx && !$pbxadmin && $form->value->{alias_select}) {
                    NGCP::Panel::Utils::Subscriber::update_subadmin_sub_aliases(
                        c => $c,
                        schema => $schema,
                        subscriber => $billing_subscriber,
                        contract_id => $billing_subscriber->contract_id,
                        alias_selected => decode_json($form->value->{alias_select}),
                        sadmin => $c->stash->{pilot},
                    );
                    NGCP::Panel::Utils::Subscriber::manage_pbx_groups(
                        c            => $c,
                        schema       => $schema,
                        group_ids    => $pbx_group_ids,
                        customer     => $c->stash->{contract},
                        subscriber   => $billing_subscriber,
                    );
                }
                NGCP::Panel::Utils::Events::insert_deferred(
                    c => $c, schema => $schema,
                    events_to_create => \@events_to_create,
                );
            });

            delete $c->session->{created_objects}->{domain};
            delete $c->session->{created_objects}->{group};
            NGCP::Panel::Utils::Message::info(
                c => $c,
                desc => $c->loc('Subscriber successfully created'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
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
    $c->stash(form => $form);
    return;
}

sub edit_fraud :Chained('base_restricted') :PathPart('fraud/edit') :Args(1) {
    my ($self, $c, $type) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form;
    if($type eq "month") {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::CustomerFraudPreferences::CustomerMonthlyFraud", $c);
    } elsif($type eq "day") {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::CustomerFraudPreferences::CustomerDailyFraud", $c);
    } else {
        NGCP::Panel::Utils::Message::error(
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
        NGCP::Panel::Utils::Message::info(
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

sub delete_fraud :Chained('base_restricted') :PathPart('fraud/delete') :Args(1) {
    my ($self, $c, $type) = @_;

    if($type eq "month") {
        $type = "interval";
    } elsif($type eq "day") {
        $type = "daily";
    } else {
        NGCP::Panel::Utils::Message::error(
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
                "fraud_${type}_limit" => undef,
                "fraud_${type}_lock" => undef,
                "fraud_${type}_notify" => undef,
            });
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                data  => { $fraud_prefs->get_inflated_columns },
                desc  => $c->loc('Failed to clear fraud interval'),
            );
            $c->response->redirect($c->uri_for_action("/customer/details", [$c->stash->{contract}->id]));
            return;
        }
    }
    NGCP::Panel::Utils::Message::info(
        c => $c,
        data => { $fraud_prefs->get_inflated_columns },
        desc => $c->loc('Successfully cleared fraud interval!'),
    );
    $c->response->redirect($c->uri_for_action("/customer/details", [$c->stash->{contract}->id]));
    return;
}

sub edit_balance :Chained('base_restricted') :PathPart('balance/edit') :Args(0) {
    my ($self, $c) = @_;

    my $balance = $c->stash->{balance};
    my $contract = $c->stash->{contract};
    my $now = $c->stash->{now};
    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Balance::CustomerBalance", $c);
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
        my $entities = { contract => $contract, };
        my $log_vals = {};
        try {
            my $schema = $c->model('DB');
            $schema->set_transaction_isolation('READ COMMITTED');
            $schema->txn_do(sub {
                $balance = NGCP::Panel::Utils::ProfilePackages::get_contract_balance(c => $c,
                            contract => $contract,
                            now => $now);
                $balance = NGCP::Panel::Utils::ProfilePackages::set_contract_balance(
                    c => $c,
                    balance => $balance,
                    cash_balance => $form->values->{cash_balance},
                    free_time_balance => $form->values->{free_time_balance},
                    now => $now,
                    log_vals => $log_vals);

                my $topup_log = NGCP::Panel::Utils::ProfilePackages::create_topup_log_record(
                    c => $c,
                    now => $now,
                    entities => $entities,
                    log_vals => $log_vals,
                    request_token => NGCP::Panel::Utils::ProfilePackages::PANEL_TOPUP_REQUEST_TOKEN,
                );
            });
            NGCP::Panel::Utils::Message::info(
                c => $c,
                desc => $c->loc('Account balance successfully changed!'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc => $c->loc('Failed to change account balance!'),
            );
        }
        $c->response->redirect($c->uri_for_action("/customer/details", [$contract->id]));
        return;
    }

    $c->stash(close_target => $c->uri_for_action("/customer/details", [$contract->id]));
    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
}

sub topup_cash :Chained('base_restricted') :PathPart('balance/topupcash') :Args(0) {
    my ($self, $c) = @_;

    my $contract = $c->stash->{contract};
    my $now = $c->stash->{now};
    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Topup::Cash", $c);
    my $params = {};

    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {
            'package.create'  => $c->uri_for('/package/create'),
        },
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        my $success = 0;
        my $entities = {};
        my $log_vals = {};
        try {
            my $schema = $c->model('DB');
            $schema->set_transaction_isolation('READ COMMITTED');
            $schema->txn_do(sub {

                NGCP::Panel::Utils::Voucher::check_topup(c => $c,
                    now => $now,
                    contract => $contract,
                    package_id => $form->values->{package}{id},
                    resource => $form->values,
                    entities => $entities,
                    err_code => sub {
                        my ($err) = @_;
                        die([$err, "showdetails"]);
                        },
                    );

                my $balance = NGCP::Panel::Utils::ProfilePackages::topup_contract_balance(c => $c,
                    contract => $contract,
                    package => $entities->{package},
                    log_vals => $log_vals,
                    #old_package => $customer->profile_package,
                    amount => $form->values->{amount},
                    now => $now,
                    request_token => NGCP::Panel::Utils::ProfilePackages::PANEL_TOPUP_REQUEST_TOKEN,
                );

                delete $c->session->{created_objects}->{package};
            });
            $success = 1;
            NGCP::Panel::Utils::Message::info(
                c => $c,
                desc => $c->loc('Top-up using cash performed successfully!'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc => $c->loc('Failed to top-up using cash!'),
            );
        }

        try {
            $c->model('DB')->txn_do(sub {
                my $topup_log = NGCP::Panel::Utils::ProfilePackages::create_topup_log_record(
                    c => $c,
                    is_cash => 1,
                    now => $now,
                    entities => $entities,
                    log_vals => $log_vals,
                    resource => $form->values,
                    is_success => $success,
                    request_token => NGCP::Panel::Utils::ProfilePackages::PANEL_TOPUP_REQUEST_TOKEN,
                );
            });
        } catch($e) {
            $c->log->error("failed to create topup log record: $e");
        }

        $c->response->redirect($c->uri_for_action("/customer/details", [$contract->id]));
        return;
    }

    $c->stash(close_target => $c->uri_for_action("/customer/details", [$contract->id]));
    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
}

sub topup_voucher :Chained('base_restricted') :PathPart('balance/topupvoucher') :Args(0) {
    my ($self, $c) = @_;

    my $contract = $c->stash->{contract};
    my $now = $c->stash->{now};
    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Topup::Voucher", $c);
    my $params = {};

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
        my $success = 0;
        my $entities = {};
        my $log_vals = {};
        try {
            my $schema = $c->model('DB');
            $schema->set_transaction_isolation('READ COMMITTED');
            $schema->txn_do(sub {

                NGCP::Panel::Utils::Voucher::check_topup(c => $c,
                    now => $now,
                    contract => $contract,
                    voucher_id => $form->values->{voucher}{id},
                    resource => $form->values,
                    entities => $entities,
                    err_code => sub {
                        my ($err) = @_;
                        die([$err, "showdetails"]);
                        },
                    );

                my $balance = NGCP::Panel::Utils::ProfilePackages::topup_contract_balance(c => $c,
                    contract => $contract,
                    voucher => $entities->{voucher},
                    log_vals => $log_vals,
                    now => $now,
                    request_token => NGCP::Panel::Utils::ProfilePackages::PANEL_TOPUP_REQUEST_TOKEN,
                );

                $entities->{voucher}->update({
                    #used_by_subscriber_id => $resource->{subscriber_id},
                    used_at => $now,
                });

            });
            $success = 1;
            NGCP::Panel::Utils::Message::info(
                c => $c,
                desc => $c->loc('Top-up using voucher performed successfully!'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc => $c->loc('Failed to top-up using voucher!'),
            );
        }

        try {
            $c->model('DB')->txn_do(sub {
                my $topup_log = NGCP::Panel::Utils::ProfilePackages::create_topup_log_record(
                    c => $c,
                    is_cash => 0,
                    now => $now,
                    entities => $entities,
                    log_vals => $log_vals,
                    resource => $form->values,
                    is_success => $success,
                    request_token => NGCP::Panel::Utils::ProfilePackages::PANEL_TOPUP_REQUEST_TOKEN,
                );
            });
        } catch($e) {
            $c->log->error("failed to create topup log record: $e");
        }

        $c->response->redirect($c->uri_for_action("/customer/details", [$contract->id]));
        return;
    }

    $c->stash(close_target => $c->uri_for_action("/customer/details", [$contract->id]));
    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
}

sub billingmappings_ajax :Chained('base') :PathPart('billingmappings/ajax') :Args(0) {
    my ($self, $c) = @_;
    $c->stash(timeline_data => {
        contract => { $c->stash->{contract}->get_columns },
        events => NGCP::Panel::Utils::BillingMappings::get_billingmappings_timeline_data($c,$c->stash->{contract}),
    });
    $c->detach( $c->view("JSON") );
}

sub balanceinterval_ajax :Chained('base') :PathPart('balanceinterval/ajax') :Args(0) {
    my ($self, $c) = @_;
    my $res = $c->stash->{contract}->contract_balances;
    NGCP::Panel::Utils::Datatables::process($c, $res, $c->stash->{balanceinterval_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub topuplog_ajax :Chained('base') :PathPart('topuplog/ajax') :Args(0) {
    my ($self, $c) = @_;
    my $res = $c->stash->{contract}->topup_log;
    NGCP::Panel::Utils::Datatables::process($c, $res, $c->stash->{topuplog_dt_columns});
    $c->detach( $c->view("JSON") );
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
    my $subscriber_id = $c->req->params->{subscriber_id} // 0;

    my $subscriber;
    if($subscriber_id && is_int($subscriber_id)) {
        $subscriber = $c->model('DB')->resultset('voip_subscribers')->search({
            'me.status' => { '!=' => 'terminated' },
        })->find( { id => $subscriber_id } );
    }
    my $res = $c->stash->{contract}->voip_subscribers->search({
        'provisioning_voip_subscriber.is_pbx_group' => 1,
    },{
        'join' => 'provisioning_voip_subscriber',
        ( defined $subscriber ? (
            '+select' => [
                {'' => \['select voip_pbx_groups.id from provisioning.voip_pbx_groups where voip_pbx_groups.group_id=provisioning_voip_subscriber.id and subscriber_id=?', [ {} => $subscriber->provisioning_voip_subscriber->id ] ], '-as' => 'sort_field' },
                {'' => \['(select voip_pbx_groups.id from provisioning.voip_pbx_groups where voip_pbx_groups.group_id=provisioning_voip_subscriber.id and subscriber_id=?) is null', [ {} => $subscriber->provisioning_voip_subscriber->id ] ], '-as' => 'sort_field_is_null' },
            ],
            '+as' => ['sort_field','sort_field_is_null'],
            'order_by' => ['sort_field_is_null','sort_field'], )
            : (),
        ),
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

        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => "tried to exceed max number of subscribers of " . $c->stash->{contract}->max_subscribers,
            desc  => $c->loc('Maximum number of subscribers for this customer reached'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c,
            $c->uri_for_action('/customer/details', [$c->stash->{contract}->id])
        );
    }

    my $posted = ($c->request->method eq 'POST');
    my $pilot = $c->stash->{subscribers}->search({
        'provisioning_voip_subscriber.is_pbx_pilot' => 1,
    })->first;
    unless($pilot) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => 'cannot create pbx group without having a pilot subscriber',
            desc  => $c->loc("Can't create a PBX group without having a pilot subscriber."),
        );
        NGCP::Panel::Utils::Navigation::back_or($c,
            $c->uri_for_action('/customer/details', [$c->stash->{contract}->id])
        );
    }
    my $form;
    $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Customer::PbxGroup", $c);
    my $params = {};
    $params = merge($params, $c->session->{created_objects});
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
            $schema->set_transaction_isolation('READ COMMITTED');
            $schema->txn_do( sub {
                my $preferences = {};

                my $base_number = $pilot->primary_number;
                if($base_number) {
                    $preferences->{cloud_pbx_base_cli} = $base_number->cc . $base_number->ac . $base_number->sn;
                    if(defined $form->values->{pbx_extension}) {
                        $form->values->{e164}{cc} = $base_number->cc;
                        $form->values->{e164}{ac} = $base_number->ac;
                        $form->values->{e164}{sn} = $base_number->sn . $form->values->{pbx_extension};
                    }

                }
                $form->values->{is_pbx_pilot} = 0;
                $form->values->{is_pbx_group} = 1;
                $form->values->{domain}{id} = $pilot->domain_id;
                $form->values->{status} = 'active';
                $preferences->{cloud_pbx} = 1;
                $preferences->{cloud_pbx_hunt_policy} = $form->values->{pbx_hunt_policy};
                $preferences->{cloud_pbx_hunt_timeout} = $form->values->{pbx_hunt_timeout};
                $preferences->{cloud_pbx_ext} = $form->values->{pbx_extension};
                $preferences->{display_name} = ucfirst($form->values->{username});
                my @events_to_create = ();
                my $event_context = { events_to_create => \@events_to_create };
                my $billing_subscriber = NGCP::Panel::Utils::Subscriber::create_subscriber(
                    c => $c,
                    schema => $schema,
                    contract => $c->stash->{contract},
                    params => $form->values,
                    admin_default => 0,
                    preferences => $preferences,
                    event_context => $event_context,
                );
                NGCP::Panel::Utils::ProfilePackages::underrun_lock_subscriber(c => $c, subscriber => $billing_subscriber);
                NGCP::Panel::Utils::Events::insert_deferred(
                    c => $c, schema => $schema,
                    events_to_create => \@events_to_create,
                );
                $c->session->{created_objects}->{group} = { id => $billing_subscriber->id };
            });
            NGCP::Panel::Utils::Message::info(
                c => $c,
                desc => $c->loc('PBX group successfully created'),
            );
        } catch ($e) {
            NGCP::Panel::Utils::Message::error(
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
        NGCP::Panel::Utils::Message::error(
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
    $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Customer::PbxGroupEdit", $c);
    my $params = { $c->stash->{pbx_group}->provisioning_voip_subscriber->get_inflated_columns };
    $params = merge($params, $c->session->{created_objects});

    unless ($posted) {
        NGCP::Panel::Utils::Subscriber::prepare_alias_select(
            c => $c,
            subscriber => $c->stash->{pbx_group},
            params => $params,
        );
    }

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
                $c->stash->{pbx_group}->provisioning_voip_subscriber->update({
                        pbx_extension => $form->values->{pbx_extension},
                        pbx_hunt_policy => $form->values->{pbx_hunt_policy},
                        pbx_hunt_timeout => $form->values->{pbx_hunt_timeout},
                    });
                NGCP::Panel::Utils::Subscriber::update_preferences(
                    c => $c,
                    prov_subscriber => $c->stash->{pbx_group}->provisioning_voip_subscriber,
                    'preferences'   => {
                        cloud_pbx_hunt_policy  => $form->values->{pbx_hunt_policy},
                        cloud_pbx_hunt_timeout => $form->values->{pbx_hunt_timeout},
                    }
                );
                my $e164;
                my $sub = $c->stash->{pbx_group};
                my $base_number = $c->stash->{pilot}->primary_number;
                if(defined $form->values->{pbx_extension} &&
                        $form->values->{pbx_extension} ne $old_extension &&
                        $base_number) {
                    $e164 = {
                        cc => $base_number->cc,
                        ac => $base_number->ac,
                        sn => $base_number->sn . $form->values->{pbx_extension},
                    };
                }
                my $aliases_before = NGCP::Panel::Utils::Events::get_aliases_snapshot(
                    c => $c,
                    schema => $schema,
                    subscriber => $sub,
                );
                NGCP::Panel::Utils::Subscriber::update_subscriber_numbers(
                    c => $c,
                    schema => $schema,
                    subscriber_id => $sub->id,
                    reseller_id => $sub->contract->contact->reseller_id,
                    $e164 ? (primary_number => $e164) : (),
                    $c->user->roles eq 'subscriberadmin' ? () : (alias_numbers  => $form->values->{alias_number}),
                );
                if(exists $form->values->{alias_select} && $c->stash->{pilot}) {
                    NGCP::Panel::Utils::Subscriber::update_subadmin_sub_aliases(
                        c => $c,
                        schema => $schema,
                        subscriber => $sub,
                        contract_id => $sub->contract_id,
                        alias_selected => decode_json($form->values->{alias_select}),
                        sadmin => $c->stash->{pilot},
                    );
                }
                #ready for number change events here
            });
            NGCP::Panel::Utils::Message::info(
                c => $c,
                desc  => $c->loc('PBX group successfully updated'),
            );
        } catch ($e) {
            NGCP::Panel::Utils::Message::error(
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
            order_by => { -asc => 'name' },
            join => { 'config' => 'device' },
        });
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Customer::PbxFieldDevice", $c);
    my $params = {};
    $params = merge($params, $c->session->{created_objects});
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
                my $station_name = $form->values->{station_name};
                my $identifier = lc $form->values->{identifier};
                if($identifier =~ /^([a-f0-9]{2}:){5}[a-f0-9]{2}$/) {
                    $identifier =~ s/\://g;
                }
                my $profile_id = $form->values->{profile_id};
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
                    $err = $c->forward('pbx_device_lines_update', [$schema, $fdev, [$form->field('line')->fields]]);
                }

            });
            unless($err) {
                NGCP::Panel::Utils::Message::info(
                    c => $c,
                    desc => $c->loc('PBX device successfully created'),
                );
            } else {
                die $err;
            }
        } catch ($e) {
            NGCP::Panel::Utils::Message::error(
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
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => "invalid voip pbx device id $dev_id",
            desc  => $c->loc('PBX device with id [_1] does not exist.',$dev_id),
        );
        NGCP::Panel::Utils::Navigation::back_or($c,
            $c->uri_for_action('/customer/details', [$c->stash->{contract}->id])
        );
    }
    if($dev->contract->id != $c->stash->{contract}->id) {
        NGCP::Panel::Utils::Message::error(
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
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Customer::PbxFieldDevice", $c);
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
    $params = merge($params, $c->session->{created_objects});
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
                my $station_name = $form->values->{station_name};
                my $identifier = lc $form->values->{identifier};
                if($identifier =~ /^([a-f0-9]{2}:){5}[a-f0-9]{2}$/) {
                    $identifier =~ s/\://g;
                }
                my $old_identifier = $fdev->identifier;
                my $profile_id = $form->values->{profile_id};
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
                    $err = $c->forward('pbx_device_lines_update', [$schema, $fdev, [$form->field('line')->fields]]);
                }

            });
            unless($err) {
                NGCP::Panel::Utils::Message::info(
                    c => $c,
                    desc  => $c->loc('PBX device successfully updated'),
                );
            } else {
                die $err;
            }
        } catch ($e) {
            NGCP::Panel::Utils::Message::error(
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
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => "invalid provisioning subscriber_id '".$line->field('subscriber_id')->value.
                    "' for contract id '".$c->stash->{contract}->id."'",
                desc  => $c->loc('Invalid provisioning subscriber id detected.'),
            );
            # TODO: throw exception here!
            $err = 1;
            last;
        } else {
            my ($range_id, $key_num, $unit_short) = split /\./, $line->field('line')->value;
            my $type = $line->field('type')->value;
            my $unit = $line->field('extension_unit')->value ||  $unit_short || 0;
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
        NGCP::Panel::Utils::Message::info(
            c => $c,
            data => { $c->stash->{pbx_device}->get_inflated_columns },
            desc => $c->loc('PBX Device successfully deleted'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
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

    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Customer::PbxFieldDeviceSync", $c);
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
                    NGCP::Panel::Utils::Message::error(
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
                NGCP::Panel::Utils::Message::error(
                    c => $c,
                    desc => $c->loc('Failed to trigger config reload via SIP'),
                    error => 'Result: ' . Dumper \@out,
                );
            } else {
                NGCP::Panel::Utils::Message::info(
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
        NGCP::Panel::Utils::Message::info(
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

sub pbx_device_preferences_list :Chained('pbx_device_base') :PathPart('preferences') :CaptureArgs(0) {
    my ($self, $c) = @_;
    my $fdev = $c->stash->{pbx_device};
    my $devmod = $fdev->profile->config->device;
    $c->stash->{devmod} = $devmod;
    my $dev_pref_rs = NGCP::Panel::Utils::Preferences::get_preferences_rs(
        c => $c,
        type => 'fielddev',
        id => $fdev->id,
    );

    my $pref_values = get_inflated_columns_all($dev_pref_rs,'hash' => 'attribute', 'column' => 'value', 'force_array' => 1);

    NGCP::Panel::Utils::Preferences::load_preference_list(
        c => $c,
        pref_values => $pref_values,
        fielddev_pref => 1,
        search_conditions => [{
            'attribute' =>
                [ -or =>
                    { 'like' => 'vnd_'.lc($devmod->vendor).'%' },
                    {'-not_like' => 'vnd_%' },
                ],
            #relation type is defined by preference flag dev_pref,
            #so here we select only linked to the current model, or not linked to any model at all
            '-or' => [
                    'voip_preference_relations.autoprov_device_id' => $devmod->id,
                    'voip_preference_relations.reseller_id'        => $devmod->reseller_id,
                    'voip_preference_relations.voip_preference_id' => undef
                ],
            },{
                join => {'voip_preferences' => 'voip_preference_relations'},
            }
        ]
    );

    $c->stash(template => 'customer/pbx_fdev_preferences.tt');
    return;
}

sub pbx_device_preferences_root :Chained('pbx_device_preferences_list') :PathPart('') :Args(0) {
    return;
}

sub pbx_device_preferences_base :Chained('pbx_device_preferences_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $pref_id) = @_;

    $c->stash->{preference_meta} = $c->model('DB')
        ->resultset('voip_preferences')
        ->search({
            -or => [
                'voip_preferences_enums.fielddev_pref' => 1,
                'voip_preferences_enums.fielddev_pref' => undef
            ],
        },{
            prefetch => 'voip_preferences_enums',
        })
        ->find({id => $pref_id});

    $c->stash->{preference} = $c->model('DB')
        ->resultset('voip_fielddev_preferences')
        ->search({
            'attribute_id' => $pref_id,
            'device_id'    => $c->stash->{pbx_device}->id,
        });
    return;
}

sub pbx_device_preferences_edit :Chained('pbx_device_preferences_base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;

    $c->stash(edit_preference => 1);

    my @enums = $c->stash->{preference_meta}
        ->voip_preferences_enums
        ->all;
    my $devmod = $c->stash->{devmod};
    my $pref_rs = $c->stash->{pbx_device}->voip_fielddev_preferences->search_rs({
            'attribute' =>
                [ -or =>
                    { 'like' => 'vnd_'.lc($devmod->vendor).'%' },
                    {'-not_like' => 'vnd_%' },
                ],
            #relation type is defined by preference flag dev_pref,
            #so here we select only linked to the current model, or not linked to any model at all
            '-or' => [
                    'voip_preference_relations.autoprov_device_id' => $devmod->id,
                    'voip_preference_relations.reseller_id'        => $devmod->reseller_id,
                    'voip_preference_relations.voip_preference_id' => undef
                ],
            },{
                join => {'attribute' => 'voip_preference_relations'},
            });
    NGCP::Panel::Utils::Preferences::create_preference_form(
        c => $c,
        pref_rs => $pref_rs,
        enums   => \@enums,
        base_uri => $c->uri_for_action('/customer/pbx_device_preferences_root', [@{ $c->req->captures }[0,1]] ),
        edit_uri => $c->uri_for_action('/customer/pbx_device_preferences_edit', $c->req->captures ),
    );
    return;
}

sub location_ajax :Chained('base') :PathPart('location/ajax') :Args(0) {
    my ($self, $c) = @_;
    NGCP::Panel::Utils::Datatables::process($c,
        @{$c->stash}{qw(locations location_dt_columns)});
    $c->detach( $c->view("JSON") );
}

sub location_create :Chained('base_restricted') :PathPart('location/create') :Args(0) {
    my ($self, $c) = @_;

    my $contract = $c->stash->{contract};
    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Customer::Location", $c);
    my $params = {};
    $params = merge($params, $c->session->{created_objects});
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            $c->model('DB')->schema->txn_do( sub {
                my $vcl = $c->model('DB')->resultset('voip_contract_locations')->create({
                    contract_id => $c->stash->{contract}->id,
                    name => $form->values->{name},
                    description => $form->values->{description},
                });
                for my $block (@{$form->values->{blocks}}) {
                    $vcl->create_related("voip_contract_location_blocks", $block);
                }
                $c->session->{created_objects}->{network} = { id => $vcl->id };
            });

            NGCP::Panel::Utils::Message::info(
                c => $c,
                desc => $c->loc('Location successfully created'),
            );
        } catch ($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create location.'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action("/customer/details", [$contract->id]));
    }

    $c->stash(
        close_target => $c->uri_for_action("/customer/details", [$contract->id]),
        create_flag => 1,
        form => $form
    );
}

sub location_base :Chained('base_restricted') :PathPart('location') :CaptureArgs(1) {
    my ($self, $c, $location_id) = @_;

    unless($location_id && is_int($location_id)) {
        $location_id //= '';
        NGCP::Panel::Utils::Message::error(
            c => $c,
            data => { id => $location_id },
            desc => $c->loc('Invalid location id detected'),
        );
        $c->response->redirect($c->uri_for());
        $c->detach;
        return;
    }

    my $res = $c->stash->{contract}->voip_contract_locations->find($location_id);
    unless(defined($res)) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            desc => $c->loc('Location does not exist'),
        );
        $c->response->redirect($c->uri_for());
        $c->detach;
        return;
    }

    $c->stash(location => {$res->get_inflated_columns},
              location_blocks => [ map { { $_->get_inflated_columns }; }
                                    $res->voip_contract_location_blocks->all ],
              location_result => $res);
}

sub location_edit :Chained('location_base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;

    my $contract = $c->stash->{contract};
    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Customer::Location", $c);
    my $params = $c->stash->{location};
    $params->{blocks} = $c->stash->{location_blocks};
    $params = merge($params, $c->session->{created_objects});
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params,
    );
    if($posted && $form->validated) {
        try {
            $c->model('DB')->schema->txn_do( sub {

                $c->stash->{'location_result'}->update({
                    name => $form->values->{name},
                    description => $form->values->{description},
                });
                $c->stash->{'location_result'}->voip_contract_location_blocks->delete;
                for my $block (@{$form->values->{blocks}}) {
                    $c->stash->{'location_result'}->create_related("voip_contract_location_blocks", $block);
                }
            });
            NGCP::Panel::Utils::Message::info(
                c => $c,
                desc  => $c->loc('Location successfully updated'),
            );
        } catch ($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update location'),
            );
        }

        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action("/customer/details", [$contract->id]));

    }

    $c->stash(
        close_target => $c->uri_for_action("/customer/details", [$contract->id]),
        edit_flag => 1,
        form => $form
    );
}

sub location_delete :Chained('location_base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;

    my $contract = $c->stash->{contract};
    my $location = $c->stash->{location_result};

    try {
        $location->delete;
        NGCP::Panel::Utils::Message::info(
            c => $c,
            data => $c->stash->{location},
            desc => $c->loc('Location successfully deleted'),
        );
    } catch ($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            data  => $c->stash->{location},
            desc  => $c->loc('Failed to terminate location'),
        );
    };

    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action("/customer/details", [$contract->id]));
}

sub location_preferences :Chained('location_base') :PathPart('preferences') :Args(0) {
    my ($self, $c) = @_;

    $self->load_preference_list($c);
    $c->stash(template => 'customer/preferences.tt');
}

sub location_preferences_base :Chained('location_base') :PathPart('preferences') :CaptureArgs(1) {
    my ($self, $c, $pref_id) = @_;

    $self->preferences_base($c, $pref_id);
}

sub location_preferences_edit :Chained('location_preferences_base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;

    my $contract = $c->stash->{contract};
    my $location = $c->stash->{location};
    my $pref_id  = $c->stash->{pref_id};

    my $base_uri = $c->uri_for($contract->id,
                               'location', $location->{id},
                               'preferences');
    my $edit_uri = $c->uri_for($contract->id,
                               'location', $location->{id},
                               'preferences', $pref_id,
                               'edit');

    $c->stash(edit_preference => 1);

    my @enums = $c->stash->{preference_meta}
        ->voip_preferences_enums
        ->search({contract_pref => 1, contract_location_pref => 1})
        ->all;

    my $pref_rs = $contract->voip_contract_preferences(
                    { location_id => $location->{id} }, undef);

    NGCP::Panel::Utils::Preferences::create_preference_form( c => $c,
        pref_rs => $pref_rs,
        enums   => \@enums,
        base_uri => $base_uri,
        edit_uri => $edit_uri,
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
            location_id => $c->stash->{location}{id} || undef,
        });
    $c->stash->{pref_id} = $pref_id;
    $c->stash(template => 'customer/preferences.tt');
}

sub preferences_edit :Chained('preferences_base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;

    $c->stash(edit_preference => 1);

    my @enums = $c->stash->{preference_meta}
        ->voip_preferences_enums
        ->search({contract_pref => 1})
        ->all;

    my $pref_rs = $c->stash->{contract}->voip_contract_preferences(
                    { location_id => undef }, undef);

    my $base_uri = $c->uri_for_action('/customer/preferences', [$c->stash->{contract}->id]);
    my $edit_uri = $c->uri_for_action('/customer/preferences_edit', [$c->stash->{contract}->id]);

    NGCP::Panel::Utils::Preferences::create_preference_form( c => $c,
        pref_rs => $pref_rs,
        enums   => \@enums,
        base_uri => $base_uri,
        edit_uri => $edit_uri,
    );
}

sub load_preference_list :Private {
    my ($self, $c) = @_;

    my $contract_pref_values = $c->model('DB')
        ->resultset('voip_preferences')
        ->search({
                contract_id => $c->stash->{contract}->id,
                'voip_contract_preferences.location_id' =>
                    $c->stash->{location}{id} || undef,
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

    my $emergency_mapping_containers_rs = $c->model('DB')
        ->resultset('emergency_containers')
        ->search_rs({ reseller_id => $reseller_id, });
    $c->stash(emergency_mapping_containers_rs => $emergency_mapping_containers_rs,
              emergency_mapping_containers    => [$emergency_mapping_containers_rs->all]);

    NGCP::Panel::Utils::Preferences::load_preference_list( c => $c,
        pref_values => \%pref_values,
        contract_pref => 1,
        contract_location_pref => $c->stash->{location}{id} ? 1 : 0,
        customer_view => ($c->user->roles eq 'subscriberadmin' ? 1 : 0),
    );
}

sub is_valid_contact {
    my ($self, $c, $contact_id) = @_;
    my $contact = $c->model('DB')->resultset('contacts')->search_rs({
        'id' => $contact_id,
        #'reseller_id' => { '!=' => undef },
        'status' => { '!=' => 'terminated' },
        })->first;
    if( $contact ) {
        return 1;
    } else {
        return 0;
    }
}

sub phonebook_ajax :Chained('base') :PathPart('phonebook/ajax') :Args(0) {
    my ($self, $c) = @_;
    NGCP::Panel::Utils::Datatables::process($c,
        @{$c->stash}{qw(phonebook phonebook_dt_columns)});
    $c->detach( $c->view("JSON") );
}

sub phonebook_create :Chained('base_restricted') :PathPart('phonebook/create') :Args(0) {
    my ($self, $c) = @_;

    my $contract = $c->stash->{contract};
    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Phonebook::Customer", $c);
    my $params = {};
    $params = merge($params, $c->session->{created_objects});
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            $c->model('DB')->schema->txn_do( sub {
                $c->model('DB')->resultset('contract_phonebook')->create({
                    contract_id => $contract->id,
                    name => $form->values->{name},
                    number => $form->values->{number},
                });
            });

            NGCP::Panel::Utils::Message::info(
                c => $c,
                desc => $c->loc('Phonebook entry successfully created'),
            );
        } catch ($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create phonebook entry.'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action("/customer/details", [$contract->id]));
    }

    $c->stash(
        close_target => $c->uri_for_action("/customer/details", [$contract->id]),
        create_flag => 1,
        form => $form
    );
}

sub phonebook_base :Chained('base_restricted') :PathPart('phonebook') :CaptureArgs(1) {
    my ($self, $c, $phonebook_id) = @_;

    unless($phonebook_id && is_int($phonebook_id)) {
        $phonebook_id //= '';
        NGCP::Panel::Utils::Message::error(
            c => $c,
            data => { id => $phonebook_id },
            desc => $c->loc('Invalid phonebook id detected'),
        );
        $c->response->redirect($c->uri_for());
        $c->detach;
        return;
    }

    my $res = $c->stash->{contract}->phonebook->find($phonebook_id);
    unless(defined($res)) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            desc => $c->loc('Phonebook entry does not exist'),
        );
        $c->response->redirect($c->uri_for());
        $c->detach;
        return;
    }

    $c->stash(phonebook => {$res->get_inflated_columns},
              phonebook_result => $res);
}

sub phonebook_edit :Chained('phonebook_base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;

    my $contract = $c->stash->{contract};
    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Phonebook::Customer", $c);
    my $params = $c->stash->{phonebook};
    $params = merge($params, $c->session->{created_objects});
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params,
    );
    if($posted && $form->validated) {
        try {
            $c->model('DB')->schema->txn_do( sub {
                $c->stash->{'phonebook_result'}->update({
                    name => $form->values->{name},
                    number => $form->values->{number},
                });
            });
            NGCP::Panel::Utils::Message::info(
                c => $c,
                desc  => $c->loc('Phonebook entry successfully updated'),
            );
        } catch ($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update phonebook entry'),
            );
        }

        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action("/customer/details", [$contract->id]));

    }

    $c->stash(
        close_target => $c->uri_for_action("/customer/details", [$contract->id]),
        edit_flag => 1,
        form => $form
    );
}

sub phonebook_delete :Chained('phonebook_base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;

    my $contract = $c->stash->{contract};
    my $phonebook = $c->stash->{phonebook_result};

    try {
        $phonebook->delete;
        NGCP::Panel::Utils::Message::info(
            c => $c,
            data => $c->stash->{phonebook},
            desc => $c->loc('Phonebook entry successfully deleted'),
        );
    } catch ($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            data  => $c->stash->{phonebook},
            desc  => $c->loc('Failed to delete phonebook entry'),
        );
    };

    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action("/customer/details", [$contract->id]));
}

sub phonebook_upload_csv :Chained('base') :PathPart('phonebook_upload_csv') :Args(0) {
    my ($self, $c) = @_;

    my $contract = $c->stash->{contract};
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Phonebook::Upload", $c);
    NGCP::Panel::Utils::Phonebook::ui_upload_csv(
        $c, $c->stash->{phonebook}, $form, 'contract', $contract->id,
        $c->uri_for_action('/customer/phonebook_upload_csv',[$contract->id]),
        $c->uri_for_action('/customer/details',[$contract->id])
    );

    $c->stash(create_flag => 1);
    $c->stash(form => $form);
    return;
}

sub phonebook_download_csv :Chained('base') :PathPart('phonebook_download_csv') :Args(0) {
    my ($self, $c) = @_;

    my $contract = $c->stash->{contract};
    $c->response->header ('Content-Disposition' => 'attachment; filename="customer_phonebook_entries.csv"');
    $c->response->content_type('text/csv');
    $c->response->status(200);
    NGCP::Panel::Utils::Phonebook::download_csv(
        $c, $c->stash->{phonebook}, 'contract', $contract->id
    );
    return;
}

=head1 AUTHOR

Andreas Granig,,,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut


1;

# vim: set tabstop=4 expandtab:
