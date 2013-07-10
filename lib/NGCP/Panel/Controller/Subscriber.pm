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
        my $schema = $c->model('DB');
        try {
            $schema->txn_do(sub {
                my ($uuid_bin, $uuid_string);
                UUID::generate($uuid_bin);
                UUID::unparse($uuid_bin, $uuid_string);

                # TODO: check if we find a reseller and contract and domains
                my $reseller = $schema->resultset('resellers')
                    ->find($c->request->params->{'reseller.id'});
                my $contract = $schema->resultset('contracts')
                    ->find($c->request->params->{'contract.id'});
                my $prov_domain = $schema->resultset('voip_domains')
                    ->find($c->request->params->{'domain.id'});
                my $billing_domain = $schema->resultset('domains')
                    ->find({domain => $prov_domain->domain});

                my $number;
                if(defined $c->request->params->{'e164.cc'} && 
                   $c->request->params->{'e164.cc'} ne '') {

                    $number = $reseller->voip_numbers->create({
                        cc => $c->request->params->{'e164.cc'},
                        ac => $c->request->params->{'e164.ac'} || '',
                        sn => $c->request->params->{'e164.sn'},
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

                my $prov_subscriber = $schema->resultset('provisioning_voip_subscribers')->create({
                    uuid => $uuid_string,
                    username => $c->request->params->{username},
                    password => $c->request->params->{password},
                    webusername => $c->request->params->{webusername} || $c->request->params->{username},
                    webpassword => $c->request->params->{webpassword},
                    admin => $c->request->params->{administrative} || 0,
                    account_id => $contract->id,
                    domain_id => $prov_domain->id,
                });

                my $voip_preferences = $schema->resultset('voip_preferences')->search({
                    'usr_pref' => 1,
                });
                $voip_preferences->find({ 'attribute' => 'account_id' })
                    ->voip_usr_preferences->create({ 
                        'subscriber_id' => $prov_subscriber->id,
                        'value' => $prov_subscriber->contract->id,
                    });
                $voip_preferences->find({ 'attribute' => 'ac' })
                    ->voip_usr_preferences->create({ 
                        'subscriber_id' => $prov_subscriber->id,
                        'value' => $c->request->params->{'e164.ac'},
                    }) if (defined $c->request->params->{'e164.ac'} && 
                           length($c->request->params->{'e164.ac'}) > 0);
                if(defined $c->request->params->{'e164.cc'} &&
                   length($c->request->params->{'e164.cc'}) > 0) {

                        $voip_preferences->find({ 'attribute' => 'cc' })
                            ->voip_usr_preferences->create({ 
                                'subscriber_id' => $prov_subscriber->id,
                                'value' => $c->request->params->{'e164.cc'},
                            });
                        my $cli = $c->request->params->{'e164.cc'} .
                                  (defined $c->request->params->{'e164.ac'} &&
                                   length($c->request->params->{'e164.ac'}) > 0 ?
                                   $c->request->params->{'e164.ac'} : ''
                                  ) .
                                  $c->request->params->{'e164.sn'};
                        $voip_preferences->find({ 'attribute' => 'cli' })
                            ->voip_usr_preferences->create({ 
                                'subscriber_id' => $prov_subscriber->id,
                                'value' => $cli,
                            });
                }
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

    my $res = $c->model('DB')->resultset('voip_subscribers')->find({ id => $subscriber_id });
    unless(defined $res) {
        $c->flash(messages => [{type => 'error', text => 'Subscriber does not exist!'}]);
        $c->response->redirect($c->uri_for('/subscriber'));
        $c->detach;
    }

    $c->stash(subscriber => $res);
}

sub ajax :Chained('sub_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    my $dispatch_to = '_ajax_resultset_' . $c->user->auth_realm;
    my $resultset = $self->$dispatch_to($c);
    $c->forward( "/ajax_process_resultset", [$resultset,
                  ["id", "username", "domain_id", "contract_id", "status",],
                  ["username", "domain_id", "contract_id", "status",]]);
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

sub terminate :Chained('base') :PathPart('terminate') :Args(0) {
    my ($self, $c) = @_;

    my $subscriber = $c->stash->{subscriber};
    my $schema = $c->model('DB');
    try {
        $schema->txn_do(sub {
            use Data::Printer;
            p $subscriber;
            $subscriber->provisioning_voip_subscriber->delete;
            $subscriber->update({ status => 'terminated' });
        });
        $c->flash(messages => [{type => 'success', text => 'Successfully terminated subscriber'}]);
        $c->response->redirect($c->uri_for());
        return;
    } catch($e) {
        $c->log->error("Failed to terminate subscriber: $e");
        $c->flash(messages => [{type => 'error', text => 'Failed to terminate subscriber'}]);
        $c->response->redirect($c->uri_for());
        return;
    }
}

sub preferences :Chained('base') :PathPart('preferences') :Args(0) {
    my ($self, $c) = @_;

    $self->load_preference_list($c);
    $c->stash(template => 'subscriber/preferences.tt');
}

sub preferences_base :Chained('base') :PathPart('preferences') :CaptureArgs(1) {
    my ($self, $c, $pref_id) = @_;

    $self->load_preference_list($c);

    $c->stash->{preference_meta} = $c->model('DB')
        ->resultset('voip_preferences')
        ->single({id => $pref_id});

    $c->stash->{preference} = $c->model('DB')
        ->resultset('voip_usr_preferences')
        ->search({
            attribute_id => $pref_id,
            subscriber_id => $c->stash->{subscriber}->provisioning_voip_subscriber->id
        });
    my @values = $c->stash->{preference}->get_column("value")->all;
    $c->stash->{preference_values} = \@values;
    $c->stash(template => 'subscriber/preferences.tt');
}

sub preferences_edit :Chained('preferences_base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;

    $c->stash(edit_preference => 1);

    my @enums = $c->stash->{preference_meta}
        ->voip_preferences_enums
        ->search({usr_pref => 1})
        ->all;

    my $pref_rs = $c->model('DB')
        ->resultset('voip_usr_preferences')
        ->search({
            subscriber_id => $c->stash->{subscriber}->provisioning_voip_subscriber->id
        });

    NGCP::Panel::Utils::create_preference_form( c => $c,
        pref_rs => $pref_rs,
        enums   => \@enums,
        base_uri => $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]),
        edit_uri => $c->uri_for_action('/subscriber/preferences_edit', $c->req->captures),
    );
}


sub load_preference_list :Private {
    my ($self, $c) = @_;

    my $usr_pref_values = $c->model('DB')
        ->resultset('voip_preferences')
        ->search({
                'subscriber.id' => $c->stash->{subscriber}->provisioning_voip_subscriber->id
            },{
                prefetch => {'voip_usr_preferences' => 'subscriber'},
            });

    my %pref_values;
    foreach my $value($usr_pref_values->all) {

        $pref_values{$value->attribute} = [
            map {$_->value} $value->voip_usr_preferences->all
        ];
    }

    my $rewrite_rule_sets_rs = $c->model('DB')
        ->resultset('voip_rewrite_rule_sets');
    $c->stash(rwr_sets_rs => $rewrite_rule_sets_rs,
              rwr_sets    => [$rewrite_rule_sets_rs->all]);

    my $ncos_levels_rs = $c->model('DB')
        ->resultset('ncos_levels');
    $c->stash(ncos_levels_rs => $ncos_levels_rs,
              ncos_levels    => [$ncos_levels_rs->all]);

    NGCP::Panel::Utils::load_preference_list( c => $c,
        pref_values => \%pref_values,
        usr_pref => 1,
    );
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
