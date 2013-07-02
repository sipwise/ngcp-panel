package NGCP::Panel::Controller::Contract;
use Sipwise::Base;
use namespace::autoclean;
BEGIN { extends 'Catalyst::Controller'; }
use NGCP::Panel::Form::Contract;
use NGCP::Panel::Utils;
use NGCP::Panel::Utils::Contract;

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    return 1;
}

sub contract_list :Chained('/') :PathPart('contract') :CaptureArgs(0) {
    my ($self, $c) = @_;
    
    my $mapping_rs = $c->model('billing')->resultset('billing_mappings');
    my $rs = $c->model('billing')->resultset('contracts')
        ->search({
            'billing_mappings.id' => {
                '=' => $mapping_rs->search({
                    contract_id => { -ident => 'me.id' },
                    start_date => [ -or =>
                        { '<=' => {-ident => 'now()'}},
                        { -is  => undef },
                    ],
                    end_date => [ -or =>
                        { '>=' => {-ident => 'now()'}},
                        { -is  => undef },
                    ],
                },{
                    alias => 'sub_query',
                    rows => 1,
                    order_by => {-desc => ['start_date', 'id']},
                })->get_column('id')->as_query,
            },
        },{
            'join' => 'billing_mappings',
            '+select' => 'billing_mappings.billing_profile_id',
            '+as' => 'billing_profile',
        });

    $c->stash(contract_select_rs => $rs);
    $c->stash(ajax_uri => $c->uri_for_action("/contract/ajax"));
    $c->stash(template => 'contract/list.tt');

    NGCP::Panel::Utils::check_redirect_chain(c => $c);
}

sub root :Chained('contract_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub create :Chained('contract_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;
    
    my $item = $c->model('billing')->resultset('billing_mappings')->new_result({});

    my $form = NGCP::Panel::Form::Contract->new;
    if($form->process(
        posted => ($c->request->method eq 'POST'),
        params => $c->request->params,
        action => $c->uri_for('create'),
        item => $item,
    )) {
        # insert ok, populate contract_balance table
        try {
            NGCP::Panel::Utils::Contract::create_contract_balance(
                c => $c,
                profile => $item->billing_profile,
                contract => $item->contract,
            );
        } catch($e) {
            # TODO: roll back contract and billing_mappings creation and
            # redirect to correct entry point
            $c->log->error("Failed to create contract balance: $e");
            $c->flash(messages => [{type => 'error', text => 'Failed to create contract balance!'}]);

            if($c->stash->{close_target}) {
                $c->response->redirect($c->stash->{close_target});
                return;
            }
            $c->response->redirect($c->uri_for_action('/contract/root'));
            return;
        }
    } 
    return if NGCP::Panel::Utils::check_form_buttons(
        c => $c, form => $form,
        fields => {'contract.contact.create' => $c->uri_for('/contact/create'),
                   'billing_profile.create'  => $c->uri_for('/billing/create')},
        back_uri => $c->uri_for('create')
    );
    if($form->validated) {
        $c->flash(messages => [{type => 'success', text => 'Contract successfully created!'}]);
        
        if($c->stash->{close_target}) {
            $c->response->redirect($c->stash->{close_target});
            return;
        }
        $c->response->redirect($c->uri_for_action('/contract/root'));
        return;
    }

    $c->stash(create_flag => 1);
    $c->stash(form => $form);
}

sub base :Chained('contract_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $contract_id) = @_;

    unless($contract_id && $contract_id->is_integer) {
        $c->flash(messages => [{type => 'error', text => 'Invalid contract id detected!'}]);
        $c->response->redirect($c->uri_for());
        $c->detach;
        return;
    }

    my $res = $c->stash->{contract_select_rs}
        ->search(undef, {
            '+select' => 'billing_mappings.id',
            '+as' => 'bmid',
        })
        ->find($contract_id);
    
    unless(defined($res)) {
        $c->flash(messages => [{type => 'error', text => 'Contract does not exist!'}]);
        $c->response->redirect($c->uri_for());
        $c->detach;
        return;
    }
    
    $c->stash(contract => {$res->get_inflated_columns});
    $c->stash(contract_result => $res);
    return;
}

sub edit :Chained('base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    
    my $contr = $c->stash->{contract_result};
    my $item = $contr->billing_mappings->find($contr->get_column('bmid'));
    if ($posted) {
        if($item->billing_profile_id != $c->req->params->{'billing_profile.id'}) {
            $item = $c->stash->{contract_result}->billing_mappings->new_result({});
            $item->start_date(time);
        }
    } else {
    }
    
    my $form = NGCP::Panel::Form::Contract->new;
    $form->process(
        posted => $posted,
        params => $c->req->params,
        item => $item,
        action => $c->uri_for($c->stash->{contract}->{id}, 'edit'),
    );
    return if NGCP::Panel::Utils::check_form_buttons(
        c => $c, form => $form,
        fields => {'contract.contact.create' => $c->uri_for('/contact/create'),
                   'billing_profile.create'  => $c->uri_for('/billing/create')},
        back_uri => $c->uri_for($c->stash->{contract}->{id}, 'edit')
    );
    if($posted && $form->validated) {
        $c->flash(messages => [{type => 'success', text => 'Contract successfully changed!'}]);
        $c->response->redirect($c->uri_for());
        return;
    }

    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
}

sub delete :Chained('base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;

    try {
        $c->stash->{contract_result}->delete;
        $c->flash(messages => [{type => 'success', text => 'Contract successfully deleted!'}]);
    } catch (DBIx::Class::Exception $e) {
        $c->flash(messages => [{type => 'error', text => 'Delete failed.'}]);
        $c->log->info("Delete failed: " . $e);
    };
    $c->response->redirect($c->uri_for());
}

sub ajax :Chained('contract_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    
    my $rs = $c->stash->{contract_select_rs};
    
    $c->forward( "/ajax_process_resultset", [$rs,
                 ["id","contact_id","billing_profile","status"],
                 []]);
    
    $c->detach( $c->view("JSON") );
}

sub peering_list :Chained('contract_list') :PathPart('peering') :CaptureArgs(0) {
    my ($self, $c) = @_;

    $c->stash(ajax_uri => $c->uri_for_action("/contract/peering_ajax"));
}

sub peering_root :Chained('peering_list') :PathPart('') :Args(0) {

}

sub peering_ajax :Chained('peering_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    
    my $base_rs = $c->stash->{contract_select_rs};
    my $rs = $base_rs->search({
            'product.class' => 'sippeering',
        }, {
            'join' => {'billing_mappings' => 'product'},
        });
    
    $c->forward( "/ajax_process_resultset", [$rs,
                 ["id","contact_id","billing_profile","status"],
                 []]);
    
    $c->detach( $c->view("JSON") );
}

sub peering_create :Chained('peering_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;
    
    my $item = $c->model('billing')->resultset('billing_mappings')->new_result({});
    $item->product(
        $c->model('billing')->resultset('products')->find({class => 'sippeering'})
    );

    my $form = NGCP::Panel::Form::Contract->new;
    if($form->process(
        posted => ($c->request->method eq 'POST'),
        params => $c->request->params,
        item => $item,
    )) {
        # insert ok, populate contract_balance table
        try {
            NGCP::Panel::Utils::Contract::create_contract_balance(
                c => $c,
                profile => $item->billing_profile,
                contract => $item->contract,
            );
        } catch($e) {
            # TODO: roll back contract and billing_mappings creation and
            # redirect to correct entry point
            $c->log->error($e);
            $c->flash(messages => [{type => 'error', text => 'Failed to create contract balance!'}]);
            if($c->stash->{close_target}) {
                $c->response->redirect($c->stash->{close_target});
                return;
            }
            $c->response->redirect($c->uri_for_action('/contract/root'));
            return;
        }
    }
    return if NGCP::Panel::Utils::check_form_buttons(
        c => $c, form => $form,
        fields => {'contract.contact.create' => $c->uri_for('/contact/create'),
                   'billing_profile.create'  => $c->uri_for('/billing/create')},
        back_uri => $c->uri_for('create')
    );
    if($form->validated) {
        $c->flash(messages => [{type => 'success', text => 'Contract successfully created!'}]);
        
        if($c->stash->{close_target}) {
            $c->response->redirect($c->stash->{close_target});
            return;
        }
        $c->response->redirect($c->uri_for_action('/contract/root'));
        return;
    }

    $c->stash(create_flag => 1);
    $c->stash(form => $form);
}

sub customer_list :Chained('contract_list') :PathPart('customer') :CaptureArgs(0) {
    my ($self, $c) = @_;

    $c->stash(ajax_uri => $c->uri_for_action("/contract/customer_ajax"));
}

sub customer_root :Chained('customer_list') :PathPart('') :Args(0) {

}

sub customer_ajax :Chained('customer_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    
    my $base_rs = $c->stash->{contract_select_rs};
    my $rs = $base_rs->search({
            'product_id' => undef,
        }, {
            'join' => {'billing_mappings' => 'product'},
        });
    
    $c->forward( "/ajax_process_resultset", [$rs,
                 ["id","contact_id","billing_profile","status"],
                 [3]]);
    
    $c->detach( $c->view("JSON") );
}

sub customer_create :Chained('customer_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;
    
    my $item = $c->model('billing')->resultset('billing_mappings')->new_result({});
    $item->product(undef);

    my $form = NGCP::Panel::Form::Contract->new;
    if($form->process(
        posted => ($c->request->method eq 'POST'),
        params => $c->request->params,
        item => $item,
    )) {
        # insert ok, populate contract_balance table
        try {
            NGCP::Panel::Utils::Contract::create_contract_balance(
                c => $c,
                profile => $item->billing_profile,
                contract => $item->contract,
            );
        } catch($e) {
            # TODO: roll back contract and billing_mappings creation and
            # redirect to correct entry point
            $c->log->error($e);
            $c->flash(messages => [{type => 'error', text => 'Failed to create contract balance!'}]);
            if($c->stash->{close_target}) {
                $c->response->redirect($c->stash->{close_target});
                return;
            }
            $c->response->redirect($c->uri_for_action('/contract/root'));
            return;
        }
    }
    return if NGCP::Panel::Utils::check_form_buttons(
        c => $c, form => $form,
        fields => {'contract.contact.create' => $c->uri_for('/contact/create'),
                   'billing_profile.create'  => $c->uri_for('/billing/create')},
        back_uri => $c->uri_for('create')
    );
    if($form->validated) {
        $c->flash(messages => [{type => 'success', text => 'Contract successfully created!'}]);
        
        if($c->stash->{close_target}) {
            $c->response->redirect($c->stash->{close_target});
            return;
        }
        $c->response->redirect($c->uri_for_action('/contract/root'));
        return;
    }

    $c->stash(create_flag => 1);
    $c->stash(form => $form);
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
