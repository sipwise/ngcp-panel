package NGCP::Panel::Controller::Contract;
use Sipwise::Base;

BEGIN { extends 'Catalyst::Controller'; }
use NGCP::Panel::Form::Contract::Basic;
use NGCP::Panel::Form::Contract::PeeringReseller;
use NGCP::Panel::Form::Contract::ProductSelect;
use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::Navigation;
use NGCP::Panel::Utils::Contract;
use NGCP::Panel::Utils::Subscriber;
use NGCP::Panel::Utils::DateTime;

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub contract_list :Chained('/') :PathPart('contract') :CaptureArgs(0) {
    my ($self, $c) = @_;

    $c->stash->{contract_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => $c->loc("#") },
        { name => "external_id", search => 1, title => $c->loc("External #") },
        { name => "contact.email", search => 1, title => $c->loc("Contact Email") },
        { name => "billing_mappings.product.name", search => 1, title => $c->loc("Product") },
        { name => "billing_mappings.billing_profile.name", search => 1, title => $c->loc("Billing Profile") },
        { name => "status", search => 1, title => $c->loc("Status") },
    ]);

    my $rs = NGCP::Panel::Utils::Contract::get_contract_rs(
        schema => $c->model('DB'));
    unless($c->user->is_superuser) {
        $rs = $rs->search({
            'contact.reseller_id' => $c->user->reseller_id,
        }, {
            join => 'contact',
        });
    }
    $rs = $rs->search({
            '-or' => [
                'product.class' => 'pstnpeering',
                'product.class' => 'sippeering',
                'product.class' => 'reseller',
            ],
        }, {
            'join' => {'billing_mappings' => 'product'},
        });
    $c->stash(contract_select_rs => $rs);

    $c->stash(ajax_uri => $c->uri_for_action("/contract/ajax"));
    $c->stash(template => 'contract/list.tt');
}

sub root :Chained('contract_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub base :Chained('contract_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $contract_id) = @_;

    unless($contract_id && $contract_id->is_integer) {
        NGCP::Panel::Utils::Message->error(
            c     => $c,
            log   => 'Invalid contract id detected!',
            desc  => $c->loc('Invalid contract id detected!'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/contract'));
    }

    my $res = $c->stash->{contract_select_rs};
    $res = $res->search(undef, {
            '+select' => 'billing_mappings.id',
            '+as' => 'bmid',
        })
        ->find($contract_id);

    unless(defined($res)) {
        NGCP::Panel::Utils::Message->error(
            c     => $c,
            log   => 'Contract does not exist',
            desc  => $c->loc('Contract does not exist'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/contract'));
    }

    my $billing_mapping = $res->billing_mappings->find($res->get_column('bmid'));
    if (! defined ($billing_mapping->product) || (
        $billing_mapping->product->handle ne 'VOIP_RESELLER' &&
        $billing_mapping->product->handle ne 'SIP_PEERING' &&
        $billing_mapping->product->handle ne 'PSTN_PEERING')) {

    }
    
    $c->stash(contract => {$res->get_inflated_columns});
    $c->stash(contract_result => $res);
    return;
}

sub edit :Chained('base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    
    my $contract = $c->stash->{contract_result};
    my $billing_mapping = $contract->billing_mappings->find($contract->get_column('bmid'));
    my $params = {};
    unless($posted) {
        $params->{billing_profile}{id} = $billing_mapping->billing_profile->id
            if($billing_mapping->billing_profile);
        $params->{contact}{id} = $contract->contact_id;
        $params->{external_id} = $contract->external_id;
        $params->{status} = $contract->status;
    }
    $params = $params->merge($c->session->{created_objects});
    my ($form, $is_peering_reseller);
    if (defined $billing_mapping->product &&
        grep {$billing_mapping->product->handle eq $_}
            ("SIP_PEERING", "PSTN_PEERING", "VOIP_RESELLER") ) {
        $form = NGCP::Panel::Form::Contract::PeeringReseller->new;
        $is_peering_reseller = 1;
    } else {
        $form = NGCP::Panel::Form::Contract::Basic->new;
        $is_peering_reseller = 0;
    }
    $form->process(
        posted => $posted,
        params => $c->req->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c, form => $form,
        fields => {
            'contact.create' => ( $is_peering_reseller
                ? $c->uri_for('/contact/create/noreseller')
                : $c->uri_for('/contact/create')),
                   'billing_profile.create'  => $c->uri_for('/billing/create')},
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                if($form->values->{billing_profile}{id} != $billing_mapping->billing_profile->id) {
                    $contract->billing_mappings->create({
                        start_date => NGCP::Panel::Utils::DateTime::current_local,
                        billing_profile_id => $form->values->{billing_profile}{id},
                        product_id => $billing_mapping->product_id,
                    });
                }
                my $old_status = $contract->status;
                delete $form->values->{billing_profile};
                $form->values->{contact_id} = $form->values->{contact}{id};
                delete $form->values->{contact};
                $form->{modify_timestamp} = NGCP::Panel::Utils::DateTime::current_local;
                $contract->update($form->values);

                if ($is_peering_reseller &&
                    defined $contract->contact->reseller_id) {
                    die( ["Cannot use this contact for peering or reseller contracts.", "showdetails"] );
                }

                # if status changed, populate it down the chain
                if($contract->status ne $old_status) {
                    NGCP::Panel::Utils::Contract::recursively_lock_contract(
                        c => $c,
                        contract => $contract,
                    );
                }

                delete $c->session->{created_objects}->{contact};
                delete $c->session->{created_objects}->{billing_profile};
            });
            $c->flash(messages => [{type => 'success', text => $c->loc("Contract successfully changed!")}]);
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc("Failed to update contract."),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/contract'));
    }

    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
}

sub terminate :Chained('base') :PathPart('terminate') :Args(0) {
    my ($self, $c) = @_;
    my $contract = $c->stash->{contract_result};

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
        $c->flash(messages => [{type => 'success', text => $c->loc('Contract successfully terminated')}]);
    } catch ($e) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => $e,
            desc  => $c->loc("Failed to terminate contract."),
        );
    };
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/contract'));
}

sub ajax :Chained('contract_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    
    my $res = $c->stash->{contract_select_rs};
    NGCP::Panel::Utils::Datatables::process($c, $res, $c->stash->{contract_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub peering_list :Chained('contract_list') :PathPart('peering') :CaptureArgs(0) {
    my ($self, $c) = @_;

    my $base_rs = $c->stash->{contract_select_rs};
    $c->stash->{peering_rs} = $base_rs->search({
            'product.class' => 'sippeering',
        }, {
            'join' => {'billing_mappings' => 'product'},
        });
   
    $c->stash(ajax_uri => $c->uri_for_action("/contract/peering_ajax"));
}

sub peering_root :Chained('peering_list') :PathPart('') :Args(0) {

}

sub peering_ajax :Chained('peering_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
   
    my $rs = $c->stash->{peering_rs}; 
    NGCP::Panel::Utils::Datatables::process($c, $rs,  $c->stash->{contract_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub peering_create :Chained('peering_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $params = {};
    $params = $params->merge($c->session->{created_objects});
    unless ($self->is_valid_noreseller_contact($c, $params->{contact}{id})) {
        delete $params->{contact};
    }
    my $form = NGCP::Panel::Form::Contract::PeeringReseller->new;
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {'contact.create' => $c->uri_for('/contact/create/noreseller'),
                   'billing_profile.create'  => $c->uri_for('/billing/create/noreseller')},
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                $form->params->{contact_id} = $form->params->{contact}{id};
                delete $form->params->{contract};
                my $bprof_id = $form->params->{billing_profile}{id};
                delete $form->params->{billing_profile};
                $form->params->{external_id} = $form->field('external_id')->value;
                $form->{create_timestamp} = $form->{modify_timestamp} = NGCP::Panel::Utils::DateTime::current_local;
                my $contract = $schema->resultset('contracts')->create($form->params);
                my $billing_profile = $schema->resultset('billing_profiles')->find($bprof_id);
                my $product = $schema->resultset('products')->find({ class => 'sippeering' }); 
                $contract->billing_mappings->create({
                    billing_profile_id => $bprof_id,
                    product_id => $product->id,
                });
                
                NGCP::Panel::Utils::Contract::create_contract_balance(
                    c => $c,
                    profile => $billing_profile,
                    contract => $contract,
                );

                if (defined $contract->contact->reseller_id) {
                    my $contact_id = $contract->contact->id;
                    die( ["Cannot use this contact (#$contact_id) for peering contracts.", "showdetails"] );
                }

                $c->session->{created_objects}->{contract} = { id => $contract->id };
                delete $c->session->{created_objects}->{contact};
                delete $c->session->{created_objects}->{billing_profile};
                my $contract_id = $contract->id;
                $c->flash(messages => [{type => 'success', text => $c->loc("Contract #[_1] successfully created",$contract_id)}]);
            });
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc("Failed to create contract."),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/contract'));
    } 

    $c->stash(create_flag => 1);
    $c->stash(form => $form);
}

sub reseller_list :Chained('contract_list') :PathPart('reseller') :CaptureArgs(0) {
    my ($self, $c) = @_;

    my $base_rs = $c->stash->{contract_select_rs};
    $c->stash->{reseller_rs} = $base_rs->search({
            'product.class' => 'reseller',
        }, {
            'join' => {'billing_mappings' => 'product'},
        });
   
    $c->stash(ajax_uri => $c->uri_for_action("/contract/reseller_ajax"));
}

sub reseller_root :Chained('reseller_list') :PathPart('') :Args(0) {

}

sub reseller_ajax :Chained('reseller_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    
    my $rs = $c->stash->{reseller_rs}; 
    NGCP::Panel::Utils::Datatables::process($c, $rs,  $c->stash->{contract_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub reseller_ajax_contract_filter :Chained('reseller_list') :PathPart('ajax/contract') :Args(1) {
    my ($self, $c, $contract_id) = @_;

    unless($contract_id && $contract_id->is_int) {
        $c->flash(messages => [{type => 'error', text => }]);
        NGCP::Panel::Utils::Message->error(
            c     => $c,
            log   => 'Invalid contract id detected',
            desc  => $c->loc('Invalid contract id detected'),
        );
        $c->response->redirect($c->uri_for());
        return;
    }

    my $rs = NGCP::Panel::Utils::Contract::get_contract_rs(
            schema => $c->model('DB'))
        ->search_rs({
            'me.id' => $contract_id,
        });
    my $contract_columns = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => $c->loc("#") },
        { name => "external_id", search => 1, title => $c->loc("External #") },
        { name => "contact.email", search => 1, title => $c->loc("Contact Email") },
        { name => "billing_mappings.billing_profile.name", search => 1, title => $c->loc("Billing Profile") },
        { name => "status", search => 1, title => $c->loc("Status") },
    ]);
    NGCP::Panel::Utils::Datatables::process($c, $rs,  $contract_columns);
    $c->detach( $c->view("JSON") );
}

sub reseller_create :Chained('reseller_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $params = {};
    $params = $params->merge($c->session->{created_objects});
    unless ($self->is_valid_noreseller_contact($c, $params->{contact}{id})) {
        delete $params->{contact};
    }
    my $form = NGCP::Panel::Form::Contract::PeeringReseller->new;
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {'contact.create' => $c->uri_for('/contact/create/noreseller'),
                   'billing_profile.create'  => $c->uri_for('/billing/create/noreseller')},
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                $form->params->{contact_id} = $form->params->{contact}{id};
                delete $form->params->{contract};
                my $bprof_id = $form->params->{billing_profile}{id};
                delete $form->params->{billing_profile};
                $form->params->{external_id} = $form->field('external_id')->value;
                $form->{create_timestamp} = $form->{modify_timestamp} = NGCP::Panel::Utils::DateTime::current_local;
                my $contract = $schema->resultset('contracts')->create($form->params);
                my $billing_profile = $schema->resultset('billing_profiles')->find($bprof_id);
                my $product = $schema->resultset('products')->find({ class => 'reseller' }); 
                $contract->billing_mappings->create({
                    billing_profile_id => $bprof_id,
                    product_id => $product->id,
                });
                
                NGCP::Panel::Utils::Contract::create_contract_balance(
                    c => $c,
                    profile => $billing_profile,
                    contract => $contract,
                );

                if (defined $contract->contact->reseller_id) {
                    my $contact_id = $contract->contact->id;
                    die( ["Cannot use this contact (#$contact_id) for reseller contracts.", "showdetails"] );
                }

                $c->session->{created_objects}->{contract} = { id => $contract->id };
                delete $c->session->{created_objects}->{contact};
                delete $c->session->{created_objects}->{billing_profile};
                my $contract_id = $contract->id;
                $c->flash(messages => [{type => 'success', text => $c->loc('Contract #[_1] successfully created',$contract_id)}]);
            });
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc("Failed to create contract."),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/contract'));
    } 

    $c->stash(create_flag => 1);
    $c->stash(form => $form);
}

sub is_valid_noreseller_contact {
    my ($self, $c, $contact_id) = @_;
    my $contact = $c->model('DB')->resultset('contacts')->search_rs({
        'id' => $contact_id,
        'reseller_id' => undef,
        })->first;
    if( $contact ) {
        return 1;
    } else {
        return 0;
    }
}

__PACKAGE__->meta->make_immutable;

1;

=head1 NAME

NGCP::Panel::Controller::Contract - Catalyst Controller

=head1 DESCRIPTION

View and edit Contracts. Optionally filter them by only peering contracts.

=head1 METHODS

=head2 contract_list

Basis for contracts.

=head2 root

Display contracts through F<contract/list.tt> template.

=head2 create

Show modal dialog to create a new contract.

=head2 base

Capture id of existing contract. Used for L</edit> and L</delete>. Stash "contract" and "contract_result".

=head2 edit

Show modal dialog to edit a contract.

=head2 delete

Delete a contract.

=head2 ajax

Get contracts from the database and output them as JSON.
The output format is meant for parsing with datatables.

The selected rows should be billing.billing_mappings JOIN billing.contracts with only one billing_mapping per contract (the one that fits best with the time).

=head2 peering_list

Basis for peering_contracts.

=head2 peering_root

Display contracts through F<contract/list.tt> template. Use L</peering_ajax> as data source.

=head2 peering_ajax

Similar to L</ajax>. Only select contracts, where billing.product is of class "sippeering".

=head2 peering_create

Similar to L</create> but sets product_id of billing_mapping to match the
product of class "sippeering".

=head1 AUTHOR

Andreas Granig,,,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
