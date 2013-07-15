package NGCP::Panel::Controller::Subscriber;
use Sipwise::Base;
use namespace::sweep;
BEGIN { extends 'Catalyst::Controller'; }
use NGCP::Panel::Utils::Contract;
use NGCP::Panel::Form::Subscriber;
use NGCP::Panel::Form::SubscriberCFSimple;
use NGCP::Panel::Form::SubscriberCFTSimple;
use NGCP::Panel::Form::SubscriberCFAdvanced;
#use NGCP::Panel::Form::SubscriberCFTAdvanced;
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

    my $prov_subscriber = $c->stash->{subscriber}->provisioning_voip_subscriber;
    my $cfs = {};
    my $mappings = {};
    for my $type(qw/cfu cfna cft cfb/) {
        $mappings->{$type} = $prov_subscriber->voip_cf_mappings
            ->find({ type => $type });
        if(defined $mappings->{$type}) {
            $cfs->{$type} = [ $mappings->{$type}
                ->destination_set
                ->voip_cf_destinations->search({}, 
                    { order_by => { -asc => 'priority' }}
                )->all ];
        }
    }
    $c->stash(cf_mappings => $mappings);
    $c->stash(cf_destinations => $cfs);
    my $ringtimeout_preference = $c->model('DB')->resultset('voip_preferences')->search({
            attribute => 'ringtimeout', 'usr_pref' => 1,
        })->first->voip_usr_preferences->find({
            subscriber_id => $prov_subscriber->id,
        });
    $c->stash(cf_ringtimeout => $ringtimeout_preference ? $ringtimeout_preference->value : undef);
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

sub preferences_callforward :Chained('base') :PathPart('preferences/callforward') :Args(1) {
    my ($self, $c, $cf_type) = @_;

    say ">>>>>>>>>>>>>>>>>>>>>> preferences_callforward";

    my $cf_desc;
    given($cf_type) {
        when("cfu") { $cf_desc = "Unconditional" }
        when("cfb") { $cf_desc = "Busy" }
        when("cft") { $cf_desc = "Timeout" }
        when("cfna") { $cf_desc = "Unavailable" }
        default {
            $c->log->error("Invalid call-forward type '$cf_type'");
            $c->flash(messages => [{type => 'error', text => 'Invalid Call Forward type'}]);
            $c->response->redirect($c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
            return;
        }
    }

    my $posted = ($c->request->method eq 'POST');

    my $voip_preferences = $c->model('DB')->resultset('voip_preferences')->search({
        'usr_pref' => 1,
    });
    my $cf_preference = $voip_preferences->find({ 'attribute' => $cf_type })
        ->voip_usr_preferences;
    my $ringtimeout_preference = $voip_preferences->find({ 'attribute' => 'ringtimeout' })
        ->voip_usr_preferences;
    my $billing_subscriber = $c->stash->{subscriber};
    my $prov_subscriber = $billing_subscriber->provisioning_voip_subscriber;
    my $cf_mapping = $prov_subscriber->voip_cf_mappings->find({ type => $cf_type });
    my $destination;
    if($cf_mapping && 
       $cf_mapping->destination_set && 
       $cf_mapping->destination_set->voip_cf_destinations->first) {

        $destination = $cf_mapping->destination_set->voip_cf_destinations->first;
    }

    my $params = {};
    if($destination) {
        $params->{destination} = $destination->destination;
        if($cf_type eq 'cft') {
            my $rt = $ringtimeout_preference->find({ subscriber_id => $prov_subscriber->id });
            if($rt) {
                $params->{ringtimeout} = $rt->value;
            } else {
                $params->{ringtimeout} = 15;
            }
        }
    }
    if($posted) {
        $params = $c->request->params;
        if(!defined($c->request->params->{submitid})) {
            if($params->{destination} !~ /\@/) {
                $params->{destination} .= '@'.$billing_subscriber->domain->domain;
            }
            if($params->{destination} !~ /^sip:/) {
                $params->{destination} = 'sip:' . $params->{destination};
            }
        }
    }

    my $cf_form;
    if($cf_type eq "cft") {
        $cf_form = NGCP::Panel::Form::SubscriberCFTSimple->new;
    } else {
        $cf_form = NGCP::Panel::Form::SubscriberCFSimple->new;
    }

    $cf_form->process(
        params => $params,
    );

    # TODO: if more than one entry in $cf_mapping->voip_cf_destination_set->voip_cf_destinations,
    # show advanced mode and list them all; same for time sets

    return if NGCP::Panel::Utils::check_form_buttons(
        c => $c, form => $cf_form,
        fields => {
            'cf_actions.advanced' => 
                $c->uri_for_action('/subscriber/preferences_callforward_advanced', 
                    [$c->req->captures->[0]], $cf_type, 'advanced'
                ),
        },
        back_uri => $c->uri_for($c->action, $c->req->captures)
    );

    if($posted && $cf_form->validated) {
        try {
            $c->model('DB')->schema->txn_do( sub {
                my $dest_set = $c->model('DB')->resultset('voip_cf_destination_sets')->find({
                    subscriber_id => $prov_subscriber->id,
                    name => 'quickset_'.$cf_type,
                });
                unless($dest_set) {
                    $dest_set = $c->model('DB')->resultset('voip_cf_destination_sets')->create({
                        name => 'quickset_'.$cf_type,
                        subscriber_id => $prov_subscriber->id,
                    });
                } else {
                    my @all = $dest_set->voip_cf_destinations->all;
                    foreach my $dest(@all) {
                        $dest->delete;
                    }
                }
                my $dest = $dest_set->voip_cf_destinations->create({
                    priority => 1,
                    timeout => 300,
                    destination => $c->request->params->{destination},
                });

                unless(defined $cf_mapping) {
                    $cf_mapping = $prov_subscriber->voip_cf_mappings->create({
                        type => $cf_type,
                        # subscriber_id => $prov_subscriber->id,
                        destination_set_id => $dest_set->id,
                        time_set_id => undef, #$time_set_id,
                    });
                }
                my $cf_preference_row = $cf_preference->find({ 
                    subscriber_id => $prov_subscriber->id 
                });
                if($cf_preference_row) {
                    $cf_preference_row->update({ value => $cf_mapping->id });
                } else {
                    $cf_preference->create({
                        subscriber_id => $prov_subscriber->id,
                        value => $cf_mapping->id,
                    });
                }
                if($cf_type eq 'cft') {
                    my $ringtimeout_preference_row = $ringtimeout_preference->find({ 
                        subscriber_id => $prov_subscriber->id 
                    });
                    if($ringtimeout_preference_row) {
                        $ringtimeout_preference_row->update({ 
                            value => $c->request->params->{ringtimeout}
                        });
                    } else {
                        $ringtimeout_preference->create({
                            subscriber_id => $prov_subscriber->id,
                            value => $c->request->params->{ringtimeout},
                        });
                    }
                }
            });
        } catch($e) {
            $c->log->error("failed to save call-forward: $e");
            $c->flash(messages => [{type => 'error', text => 'Failed to save Call Forward'}]);
            $c->response->redirect($c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
            return;
        }
        
        $c->flash(messages => [{type => 'success', text => 'Successfully saved Call Forward'}]);
        $c->response->redirect($c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
        return;
    }

    $self->load_preference_list($c);
    $c->stash(template => 'subscriber/preferences.tt');
    $c->stash(
        edit_cf_flag => 1,
        cf_description => $cf_desc,
        cf_form => $cf_form,
    );
}

sub preferences_callforward_advanced :Chained('base') :PathPart('preferences/callforward') :Args(2) {
    my ($self, $c, $cf_type, $advanced) = @_;

    say ">>>>>>>>>>>>>>>>>>>>>> preferences_callforward_advanced";

    if(defined $advanced && $advanced eq 'advanced') {
        $advanced = 1;
    } else {
        $advanced = 0;
    }

    my $cf_desc;
    given($cf_type) {
        when("cfu") { $cf_desc = "Unconditional" }
        when("cfb") { $cf_desc = "Busy" }
        when("cft") { $cf_desc = "Timeout" }
        when("cfna") { $cf_desc = "Unavailable" }
        default {
            $c->log->error("Invalid call-forward type '$cf_type'");
            $c->flash(messages => [{type => 'error', text => 'Invalid Call Forward type'}]);
            $c->response->redirect($c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
            return;
        }
    }

    my $billing_subscriber = $c->stash->{subscriber};
    my $prov_subscriber = $billing_subscriber->provisioning_voip_subscriber;
    my $cf_mapping = $prov_subscriber->voip_cf_mappings->find({ type => $cf_type });
    if($cf_mapping) {
        $c->stash->{cf_active_destination_set} = $cf_mapping->destination_set
            if($cf_mapping->destination_set);
        $c->stash->{cf_destination_sets} = $prov_subscriber->voip_cf_destination_sets;
        $c->stash->{cf_active_time_set} = $cf_mapping->time_set
            if($cf_mapping->time_set);
        $c->stash->{cf_time_sets} = $prov_subscriber->voip_cf_time_sets;
    }

    my $destination;
    if($cf_mapping && 
       $cf_mapping->destination_set && 
       $cf_mapping->destination_set->voip_cf_destinations->first) {

        $destination = $cf_mapping->destination_set->voip_cf_destinations->first;
    }


    my $posted = ($c->request->method eq 'POST');

    my $cf_form;
#    my $params = {};
#    if($cf_type eq "cft") {
#        $cf_form = NGCP::Panel::Form::SubscriberCFTAdvanced->new;
#    } else {
        $cf_form = NGCP::Panel::Form::SubscriberCFAdvanced->new(ctx => $c);
#    }
    $cf_form->process(
        params => $posted ? $c->request->params : {}
    );


    say ">>>>>>>>>>>>>>>>>>>>>>>> check_form_buttons";
    return if NGCP::Panel::Utils::check_form_buttons(
        c => $c, form => $cf_form,
        fields => {
            'cf_actions.simple' => 
                $c->uri_for_action('/subscriber/preferences_callforward', 
                    [$c->req->captures->[0], $cf_type],
                ),
        },
        back_uri => $c->uri_for($c->action, $c->req->captures)
    );


    say ">>>>>>>>>>>>>>>>>>>>>>>> after check_form_buttons";

=pod
    if($posted && $cf_form->validated) {
        try {
            $c->model('DB')->schema->txn_do( sub {
                my $dest_set = $c->model('DB')->resultset('voip_cf_destination_sets')->find({
                    subscriber_id => $prov_subscriber->id,
                    name => 'quickset_'.$cf_type,
                });
                unless($dest_set) {
                    $dest_set = $c->model('DB')->resultset('voip_cf_destination_sets')->create({
                        name => 'quickset_'.$cf_type,
                        subscriber_id => $prov_subscriber->id,
                    });
                } else {
                    my @all = $dest_set->voip_cf_destinations->all;
                    foreach my $dest(@all) {
                        $dest->delete;
                    }
                }
                my $dest = $dest_set->voip_cf_destinations->create({
                    priority => 1,
                    timeout => 300,
                    destination => $c->request->params->{destination},
                });

                unless(defined $cf_mapping) {
                    $cf_mapping = $prov_subscriber->voip_cf_mappings->create({
                        type => $cf_type,
                        # subscriber_id => $prov_subscriber->id,
                        destination_set_id => $dest_set->id,
                        time_set_id => undef, #$time_set_id,
                    });
                }
                my $cf_preference_row = $cf_preference->find({ 
                    subscriber_id => $prov_subscriber->id 
                });
                if($cf_preference_row) {
                    $cf_preference_row->update({ value => $cf_mapping->id });
                } else {
                    $cf_preference->create({
                        subscriber_id => $prov_subscriber->id,
                        value => $cf_mapping->id,
                    });
                }
                if($cf_type eq 'cft') {
                    my $ringtimeout_preference_row = $ringtimeout_preference->find({ 
                        subscriber_id => $prov_subscriber->id 
                    });
                    if($ringtimeout_preference_row) {
                        $ringtimeout_preference_row->update({ 
                            value => $c->request->params->{ringtimeout}
                        });
                    } else {
                        $ringtimeout_preference->create({
                            subscriber_id => $prov_subscriber->id,
                            value => $c->request->params->{ringtimeout},
                        });
                    }
                }
            });
        } catch($e) {
            $c->log->error("failed to save call-forward: $e");
            $c->flash(messages => [{type => 'error', text => 'Failed to save Call Forward'}]);
            $c->response->redirect($c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
            return;
        }
        
        $c->flash(messages => [{type => 'success', text => 'Successfully saved Call Forward'}]);
        $c->response->redirect($c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
        return;
    }

=cut

    $self->load_preference_list($c);
    $c->stash(template => 'subscriber/preferences.tt');
    $c->stash(
        edit_cf_flag => 1,
        cf_description => $cf_desc,
        cf_form => $cf_form,
    );
}

sub preferences_callforward_delete :Chained('base') :PathPart('preferences/callforward/delete') :Args(1) {
    my ($self, $c, $cfmap_id) = @_;

    try {
        $c->model('DB')->resultset('voip_cf_mappings')->find($cfmap_id)->delete;
        $c->flash(messages => [{type => 'success', text => 'Successfully deleted Call Forward'}]);
    } catch($e) {
        $c->log->error("failed to delete call forward mapping: $e");
        $c->flash(messages => [{type => 'error', text => 'Failed to deleted Call Forward'}]);
    }

    $c->response->redirect($c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
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

    my $sound_sets_rs = $c->model('DB')
        ->resultset('voip_sound_sets');
    $c->stash(sound_sets_rs => $sound_sets_rs,
              sound_sets    => [$sound_sets_rs->all]);

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
