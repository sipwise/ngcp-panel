package NGCP::Panel::Controller::Customer;
use Sipwise::Base;
use namespace::sweep;
BEGIN { extends 'Catalyst::Controller'; }
use NGCP::Panel::Form::Customer;
use NGCP::Panel::Form::CustomerMonthlyFraud;
use NGCP::Panel::Form::CustomerDailyFraud;
use NGCP::Panel::Utils;

use Data::Printer;

=head1 NAME

NGCP::Panel::Controller::Customer - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    return 1;
}

sub list_customer :Chained('/') :PathPart('customer') :CaptureArgs(0) {
    my ($self, $c) = @_;

    $c->stash(
        template => 'customer/list.tt'
    );
    NGCP::Panel::Utils::check_redirect_chain(c => $c);
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

    my $contract = $c->model('billing')->resultset('contracts')
        ->find($contract_id);

    $c->stash(fraud => $contract->contract_fraud_preference);
    $c->stash(template => 'customer/details.tt'); 
    $c->stash(contract => $contract);
}

sub details :Chained('base') :PathPart('details') :Args(0) {
    my ($self, $c) = @_;
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
        $c->model('billing')->resultset('contract_fraud_preferences')
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
            $c->log->error("Failed to clear fraud interval: $e");
            $c->flash(messages => [{type => 'error', text => "Failed to clear fraud interval!"}]);
            $c->response->redirect($c->uri_for_action("/customer/details", [$c->stash->{contract}->id]));
            return;
        }
    }
    $c->flash(messages => [{type => 'success', text => "Successfully cleared fraud interval!"}]);
    $c->response->redirect($c->uri_for_action("/customer/details", [$c->stash->{contract}->id]));
    return;
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
