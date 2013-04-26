package NGCP::Panel::Controller::Billing;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller'; }



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
        $c->flash(messages => [{type => 'error', text => 'Domain does not exist!'}]);
        $c->response->redirect($c->uri_for());
        return;
    }
    $c->stash(profile => {$res->get_columns});
    $c->stash(profile_result => $res);
}

sub edit :Chained('base') :PathPart('edit') {
    my ($self, $c) = @_;
    
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

just shows a list of billing profiles

=head2 ajax

Get billing_profiles and output them as JSON.

=head2 base

Fetch a billing_profile by its id.

=head2 edit

Show a modal to edit one billing_profile.

=head1 AUTHOR

Gerhard Jungwirth C<< <gjungwirth@sipwise.com> >>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
