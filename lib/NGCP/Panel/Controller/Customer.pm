package NGCP::Panel::Controller::Customer;
use Sipwise::Base;
use namespace::sweep;
BEGIN { extends 'Catalyst::Controller'; }
use NGCP::Panel::Utils::Contract;
use NGCP::Panel::Form::CustomerMonthlyFraud;
use NGCP::Panel::Form::CustomerDailyFraud;
use NGCP::Panel::Form::CustomerBalance;
use NGCP::Panel::Form::CustomerSubscriber;
use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::Navigation;
use NGCP::Panel::Utils::DateTime;
use UUID qw/generate unparse/;

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

    my @subscribers = ();
    foreach my $s($contract->first->voip_subscribers->search_rs({ status => { -in => ['active', 'locked'] } })->all) {
        my $sub = { $s->get_columns };
        $sub->{domain} = $s->domain->domain;
        $sub->{primary_number} = {$s->primary_number->get_columns} if(defined $s->primary_number);
        $sub->{locations} = [ map { { $_->get_columns } } $c->model('DB')->resultset('location')->
            search({
                username => $s->username,
                domain => $s->domain->domain,
            })->all ];
        push @subscribers, $sub;
    }
    $c->stash->{subscribers} = \@subscribers;

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

    my $form = NGCP::Panel::Form::CustomerSubscriber->new;
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
        fields => [qw/domain.create/],
        back_uri => $c->req->uri,
    );
    if($form->validated) {
        my $schema = $c->model('DB');
        my $contract = $c->stash->{contract};
        my $reseller = $contract->contact->reseller;
        my $billing_domain = $schema->resultset('domains')
            ->find($c->request->params->{'domain.id'});
        my $prov_domain = $schema->resultset('voip_domains')
            ->find({domain => $billing_domain->domain});
        try {
            $schema->txn_do(sub {
                my $preferences = {};
                my $billing_subscriber = NGCP::Panel::Utils::Subscriber::create_subscriber(
                    c => $c,
                    schema => $schema,
                    contract => $c->stash->{contract},
                    params => $form->params,
                    admin_default => 0,
                    preferences => $preferences,
                );

                delete $c->session->{created_objects}->{domain};

            });
            $c->flash(messages => [{type => 'success', text => 'Subscriber successfully created!'}]);
            $c->response->redirect($c->uri_for_action('/customer/details', [$contract->id]));
            return;
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => "Failed to create subscriber.",
            );
            $c->response->redirect($c->uri_for_action('/customer/details', [$contract->id]));
            return;
        }
    }

    $c->stash(close_target => $c->uri_for());
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

=head1 AUTHOR

Andreas Granig,,,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;

# vim: set tabstop=4 expandtab:
