package NGCP::Panel::Controller::Billing;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller'; }

use NGCP::Panel::Form::BillingProfile;
use NGCP::Panel::Form::BillingFee;

sub list :Chained('/') :PathPart('billing') :CaptureArgs(0) :Args(0) {
    my ( $self, $c ) = @_;

    $c->stash(has_edit => 1);
    $c->stash(has_preferences => 0);
    $c->stash(template => 'billing/list.tt');
}

sub root :Chained('list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub ajax :Chained('list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    
    my $resultset = $c->model('billing')->resultset('billing_profiles');
    
    $c->forward( "/ajax_process_resultset", [$resultset,
                 ["id", "name"],
                 [0,1]]);
    
    $c->detach( $c->view("JSON") );
}

sub base :Chained('list') :PathPart('') :CaptureArgs(1) :Args(0) {
    my ($self, $c, $profile_id) = @_;

    unless($profile_id && $profile_id =~ /^\d+$/) {
        $c->flash(messages => [{type => 'error', text => 'Invalid profile id detected!'}]);
        $c->response->redirect($c->uri_for());
        return;
    }

    my $res = $c->model('billing')->resultset('billing_profiles')->find($profile_id);
    unless(defined($res)) {
        $c->flash(messages => [{type => 'error', text => 'Billing Profile does not exist!'}]);
        $c->response->redirect($c->uri_for());
        return;
    }
    $c->stash(profile => {$res->get_columns});
    $c->stash(profile_result => $res);
}

sub edit :Chained('base') :PathPart('edit') {
    my ($self, $c) = @_;
    
    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::BillingProfile->new;
    $form->process(
        posted => 1,
        params => $posted ? $c->request->params : $c->stash->{profile},
        action => $c->uri_for($c->stash->{profile}->{id}, 'edit'),
    );
    if($posted && $form->validated) {
        $c->model('billing')->resultset('billing_profiles')
            ->find($form->field('id')->value)
            ->update($form->fif() );
        $c->flash(messages => [{type => 'success', text => 'Billing Profile successfully changed!'}]);
        $c->response->redirect($c->uri_for());
        return;
    }
    
    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
}

sub create :Chained('list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $form = NGCP::Panel::Form::BillingProfile->new;
    $form->process(
        posted => ($c->request->method eq 'POST'),
        params => $c->request->params,
        action => $c->uri_for('create'),
    );
    if($form->validated) {
        $c->model('billing')->resultset('billing_profiles')->create(
             $form->fif() );
        $c->flash(messages => [{type => 'success', text => 'Billing profile successfully created!'}]);
        $c->response->redirect($c->uri_for());
        return;
    }

    $c->stash(close_target => $c->uri_for());
    $c->stash(create_flag => 1);
    $c->stash(form => $form);
}

sub delete :Chained('base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;
    
    unless ( defined($c->stash->{'profile_result'}) ) {
        $c->flash(messages => [{type => 'error', text => 'Billing profile not found!'}]);
        return;
    }
    $c->stash->{'profile_result'}->delete;

    $c->flash(messages => [{type => 'success', text => 'Billing profile successfully deleted!'}]);
    $c->response->redirect($c->uri_for);
}

sub fees_list :Chained('base') :PathPart('fees') :CaptureArgs(0) {
    my ($self, $c) = @_;
    
    $c->stash(has_edit => 1);
    $c->stash(has_preferences => 0);
    $c->stash(template => 'billing/fees.tt');
}

sub fees :Chained('fees_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;

}

sub fees_base :Chained('fees_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $fee_id) = @_;

        unless($fee_id && $fee_id =~ /^\d+$/) {
        $c->flash(messages => [{type => 'error', text => 'Invalid billing fee id detected!'}]);
        $c->response->redirect($c->uri_for($c->stash->{profile}->{id}, 'fees'));
        return;
    }
    
    my $res = $c->stash->{'profile_result'}->billing_fees
        ->search(undef, {join => 'billing_zone',})
        ->find($fee_id);
    unless(defined($res)) {
        $c->flash(messages => [{type => 'error', text => 'Billing Fee does not exist!'}]);
        $c->response->redirect($c->uri_for($c->stash->{profile}->{id}, 'fees'));
        return;
    }
    $c->stash(fee => {$res->get_columns}); #get_columns should not be used
    $c->stash->{fee}->{'billing_zone.id'} = $res->billing_zone->id
        if (defined $res->billing_zone);
    $c->stash(fee_result => $res);
}

sub fees_ajax :Chained('fees_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;

    my $resultset = $c->stash->{'profile_result'}->billing_fees
        ->search(undef, {
            join => 'billing_zone',
            columns => [
                {'zone' => 'billing_zone.zone'},
               'id','source','destination','direction'
            ]
        });
    
    $c->forward( "/ajax_process_resultset", [$resultset,
                 ["id", "source", "destination", "direction", 'zone'],
                 [1,2,3]]);
    
    $c->detach( $c->view("JSON") );
}

sub fees_create :Chained('fees_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $form = NGCP::Panel::Form::BillingFee->new;
    $form->process(
        posted => ($c->request->method eq 'POST'),
        params => $c->request->params,
        action => $c->uri_for($c->stash->{profile}->{id}, 'fees', 'create'),
    );
    if($form->validated) {
        $c->stash->{'profile_result'}->billing_fees
            ->create(
                 $form->custom_get_values()
             );
        $c->flash(messages => [{type => 'success', text => 'Billing Fee successfully created!'}]);
        $c->response->redirect($c->uri_for($c->stash->{profile}->{id}, 'fees'));
        return;
    }

    $c->stash(close_target => $c->uri_for($c->stash->{profile}->{id}, 'fees'));
    $c->stash(create_flag => 1);
    $c->stash(form => $form);
}

sub fees_edit :Chained('fees_base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;
    
    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::BillingFee->new;
    $form->field('billing_zone')->field('id')->ajax_src('../../zones/ajax');
    $form->process(
        posted => 1,
        params => $posted ? $c->request->params : $c->stash->{fee},
        action => $c->uri_for($c->stash->{profile}->{id},'fees',$c->stash->{fee}->{id}, 'edit'),
    );
    if($posted && $form->validated) {
        $c->stash->{'fee_result'}
            ->update($form->custom_get_values_to_update() );
        $c->flash(messages => [{type => 'success', text => 'Billing Profile successfully changed!'}]);
        $c->response->redirect($c->uri_for($c->stash->{profile}->{id}, 'fees'));
        return;
    }
    
    $c->stash(edit_fee_flag => 1);
    $c->stash(form => $form);
    $c->stash(close_target => $c->uri_for($c->stash->{profile}->{id}, 'fees'));
}

sub fees_delete :Chained('fees_base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;

    unless ( defined($c->stash->{'fee_result'}) ) {
        $c->flash(messages => [{type => 'error', text => 'Billing fee not found!'}]);
        return;
    }
    $c->stash->{'fee_result'}->delete;

    $c->flash(messages => [{type => 'success', text => 'Billing profile successfully deleted!'}]);
    $c->response->redirect($c->uri_for($c->stash->{profile}->{id}, 'fees'));
}

sub zones_list :Chained('base') :PathPart('zones') :CaptureArgs(0) {


}

sub zones_ajax :Chained('zones_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;

    my $resultset = $c->stash->{'profile_result'}->billing_zones;
    
    $c->forward( "/ajax_process_resultset", [$resultset,
                 ["id", "zone", "detail",],
                 [1,2]]);
    
    $c->detach( $c->view("JSON") );
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

NGCP::Panel::Controller::Billing - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=head2 list

basis for the billing controller

=head2 root

just shows a list of billing profiles using datatables

=head2 ajax

Get billing_profiles and output them as JSON.

=head2 base

Fetch a billing_profile by its id.

=head2 edit

Show a modal to edit one billing_profile.

=head2 create

Show a modal to add a new billing_profile.

=head2 delete

Delete a billing_profile identified by base.

=head2 fees_list

basis for the billing_fees logic. for a certain billing_profile identified
by base.

=head2 fees

Shows a list of billing_fees for one billing_profile using datatables.

=head2 fees_base

Fetch a billing_fee (identified by id).

=head2 fees_ajax

Get billing_fees and output them as JSON.

=head2 fees_create

Show a modal to add a new billing_fee.

=head2 fees_edit

Show a modal to edit a billing_fee.

=head2 fees_delete

Delete a billing_fee.

=head2 zones_list

basis for billing zones. part of a certain billing profile.

=head2 zones_ajax

sends a JSON representation of billing_zones und the current billing profile.

=head1 AUTHOR

Gerhard Jungwirth C<< <gjungwirth@sipwise.com> >>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
