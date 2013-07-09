package NGCP::Panel::Controller::Subscriber;
use Sipwise::Base;
use namespace::sweep;
BEGIN { extends 'Catalyst::Controller'; }
use NGCP::Panel::Utils::Contract;
use NGCP::Panel::Form::Subscriber;
use UUID;

use Data::Printer;

=head1 NAME

NGCP::Panel::Controller::Subscriber - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    return 1;
}

sub sub_list :Chained('/') :PathPart('subscriber') :CaptureArgs(0) {
    my ($self, $c) = @_;

    $c->stash(
        template => 'subscriber/list.tt',
    );

}

sub root :Chained('sub_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}


sub create_list :Chained('sub_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $form = NGCP::Panel::Form::Subscriber->new;
    $form->process(
        posted => ($c->request->method eq 'POST'),
        params => $c->request->params,
        action => $c->uri_for('/subscriber/create'),
    );
    return if NGCP::Panel::Utils::check_form_buttons(
        c => $c,
        form => $form,
        fields => [qw/domain.create/],
        back_uri => $c->uri_for('/subscriber/create'),
    );
    if($form->validated) {
        # TODO: save subscriber

        $c->log->debug(">>>>>>>>>>>>>>>>>>>>>>>>>> subscriber validated");

        # TODO: use transaction
        my $schema = $c->model('DB');
        try {
            $schema->txn_do(sub {
                my ($uuid_bin, $uuid_string);
                UUID::generate($uuid_bin);
                UUID::unparse($uuid_bin, $uuid_string);

                # TODO: check if we find a reseller and contract and domains
                my $reseller = $c->model('DB')->resultset('resellers')
                    ->find($c->request->params->{'reseller.id'});
                my $contract = $c->model('DB')->resultset('contracts')
                    ->find($c->request->params->{'contract.id'});
                my $prov_domain = $c->model('DB')->resultset('voip_domains')
                    ->find($c->request->params->{'domain.id'});
                my $billing_domain = $c->model('DB')->resultset('domains')
                    ->find({domain => $prov_domain->domain});

                my $number;
                if(defined $c->request->params->{'e164.cc'} && $c->request->params->{'e164.cc'} ne '') {
                    # TODO: must have sn set!
                    $number = $reseller->voip_numbers->create({
                        cc => $c->request->params->{'e164.cc'},
                        ac => $c->request->params->{'e164.ac'} || '',
                        sn => $c->request->params->{'e164.sn'} || '',
                        status => 'active',
                    });
                }
                my $billing_subscriber = $contract->voip_subscribers->create({
                    uuid => $uuid_string,
                    username => $c->request->params->{username},
                    domain_id => $billing_domain->id,
                    status => $c->request->params->{status},
                    primary_number_id => defined $number ? $number->id : undef,
                });
                if(defined $number) {
                    $number->update({ subscriber_id => $billing_subscriber->id });
                }

                $c->model('DB')->resultset('provisioning_voip_subscribers')->create({
                    uuid => $uuid_string,
                    username => $c->request->params->{username},
                    password => $c->request->params->{password},
                    webusername => $c->request->params->{webusername},
                    webpassword => $c->request->params->{webpassword},
                    admin => $c->request->params->{administrative} || 0,
                    account_id => $contract->id,
                    domain_id => $prov_domain->id,
                });
            });
            $c->flash(messages => [{type => 'success', text => 'Subscriber successfully created!'}]);
            $c->response->redirect($c->uri_for('/subscriber'));
            return;
        } catch($e) {
            $c->log->error("Failed to create subscriber: $e");
            $c->flash(messages => [{type => 'error', text => 'Creating subscriber failed!'}]);
            $c->response->redirect($c->uri_for('/subscriber'));
            return;
        }
    }

    $c->log->debug(">>>>>>>>>>>>>>>>>>>>>>>>>> subscriber NOT validated");
    $c->stash(close_target => $c->uri_for());
    $c->stash(create_flag => 1);
    $c->stash(form => $form)
}

sub base :Chained('/subscriber/sub_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $subscriber_id) = @_;

    unless($subscriber_id && $subscriber_id->is_integer) {
        $c->flash(messages => [{type => 'error', text => 'Invalid subscriber id detected!'}]);
        $c->response->redirect($c->uri_for());
        return;
    }

    my $res = $c->model('DB')->resultset('voip_subscribers')->find($subscriber_id);
    unless(defined($res)) {
        $c->flash(messages => [{type => 'error', text => 'Subscriber does not exist!'}]);
        $c->response->redirect($c->uri_for());
        return;
    }

    $c->stash(subscriber => {$res->get_columns});
    $c->stash(subscriber_result => $res);
}

sub ajax :Chained('sub_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    my $dispatch_to = '_ajax_resultset_' . $c->user->auth_realm;
    my $resultset = $self->$dispatch_to($c);
    $c->forward( "/ajax_process_resultset", [$resultset,
                  ["id", "username", "domain_id"],
                  ["username", "domain_id"]]);
    $c->detach( $c->view("JSON") );
}

sub _ajax_resultset_admin {
    my ($self, $c) = @_;
    return $c->model('DB')->resultset('voip_subscribers');
}

sub _ajax_resultset_reseller {
    my ($self, $c) = @_;

    # TODO: filter for reseller
    return $c->model('DB')->resultset('voip_subscribers');
}

sub master :Chained('/') :PathPart('subscriber') :Args(1) {
    my ($self, $c, $subscriber_id) = @_;

    $c->stash(
        template => 'subscriber/master.tt',
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
