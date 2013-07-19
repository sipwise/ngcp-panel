package NGCP::Panel::Controller::Subscriber;
use Sipwise::Base;
use namespace::sweep;
BEGIN { extends 'Catalyst::Controller'; }
use NGCP::Panel::Utils;
use NGCP::Panel::Utils::Navigation;
use NGCP::Panel::Utils::Contract;
use NGCP::Panel::Utils::Subscriber;
use NGCP::Panel::Utils::Datatables;
use NGCP::Panel::Form::Subscriber;
use NGCP::Panel::Form::SubscriberCFSimple;
use NGCP::Panel::Form::SubscriberCFTSimple;
use NGCP::Panel::Form::SubscriberCFAdvanced;
use NGCP::Panel::Form::SubscriberCFTAdvanced;
use NGCP::Panel::Form::DestinationSet;
use NGCP::Panel::Form::TimeSet;
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

    $c->stash->{dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => "#" },
        { name => "username", search => 1, title => "Username" },
        { name => "domain.domain", search => 1, title => "Domain" },
        { name => "status", search => 1, title => "Status" },
        { name => "contract_id", search => 1, title => "Contract #"},
    ]);
    #NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);

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
    return if NGCP::Panel::Utils::Navigation::check_form_buttons(
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
                my $billing_domain = $schema->resultset('domains')
                    ->find($c->request->params->{'domain.id'});
                my $prov_domain = $schema->resultset('voip_domains')
                    ->find({domain => $billing_domain->domain});

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

    
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{dt_columns});

    $c->detach( $c->view("JSON") );
}

sub _ajax_resultset_admin {
    my ($self, $c) = @_;
    return $c->model('DB')->resultset('voip_subscribers')->search;
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

    foreach my $type(qw/cfu cfna cft cfb/) {
        my $maps = $prov_subscriber->voip_cf_mappings
            ->search({ type => $type });
        $cfs->{$type} = [];
        foreach my $map($maps->all) {
            my @dset = map { { $_->get_columns } } $map->destination_set->voip_cf_destinations->search({},
                { order_by => { -asc => 'priority' }})->all;
            foreach my $d(@dset) {
                $d->{as_string} = NGCP::Panel::Utils::Subscriber::destination_as_string($d);
            }
            my @tset = ();
            if($map->time_set) {
                @tset = map { { $_->get_columns } } $map->time_set->voip_cf_periods->all;
                foreach my $t(@tset) {
                    $t->{as_string} = NGCP::Panel::Utils::Subscriber::period_as_string($t);
                }
            }
            push @{ $cfs->{$type} }, { destinations => \@dset, periods => \@tset };
        }
    }
    $c->stash(cf_destinations => $cfs);

    my $ringtimeout_preference = NGCP::Panel::Utils::Subscriber::get_usr_preference_rs(
            c => $c, attribute => 'ringtimeout', prov_subscriber => $prov_subscriber)
        ->first;
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

    my $cf_desc;
    given($cf_type) {
        when("cfu") { $cf_desc = "Call Forward Unconditional" }
        when("cfb") { $cf_desc = "Call Forward Busy" }
        when("cft") { $cf_desc = "Call Forward Timeout" }
        when("cfna") { $cf_desc = "Call Forward Unavailable" }
        default {
            $c->log->error("Invalid call-forward type '$cf_type'");
            $c->flash(messages => [{type => 'error', text => 'Invalid Call Forward type'}]);
            $c->response->redirect($c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
            return;
        }
    }

    my $posted = ($c->request->method eq 'POST');

    my $prov_subscriber = $c->stash->{subscriber}->provisioning_voip_subscriber;
    my $cf_preference = NGCP::Panel::Utils::Subscriber::get_usr_preference_rs(
            c => $c, prov_subscriber => $prov_subscriber, attribute => $cf_type);
    my $ringtimeout_preference = NGCP::Panel::Utils::Subscriber::get_usr_preference_rs(
            c => $c, prov_subscriber => $prov_subscriber, attribute => 'ringtimeout');
    my $cf_mapping = $prov_subscriber->voip_cf_mappings->search_rs({ type => $cf_type });
    my $destination;

    if($cf_mapping->count > 1) {
        # there is more than one mapping,
        # which can only be handled in advanced mode

        $c->response->redirect( 
            $c->uri_for_action('/subscriber/preferences_callforward_advanced', 
                [$c->req->captures->[0]], $cf_type, 'advanced'
            )
       );
       return;
    } elsif($cf_mapping->first && $cf_mapping->first->destination_set && 
            $cf_mapping->first->destination_set->voip_cf_destinations->first) {

        # there are more than one destinations or a time set, so
        # which can only be handled in advanced mode
        if($cf_mapping->first->destination_set->voip_cf_destinations->count > 1 ||
           $cf_mapping->first->time_set) {

            $c->response->redirect( 
                $c->uri_for_action('/subscriber/preferences_callforward_advanced', 
                    [$c->req->captures->[0]], $cf_type, 'advanced'
                )
           );
           return;
        }
        $destination = $cf_mapping->first->destination_set->voip_cf_destinations->first;
    }

    my $params = {};
    if($destination) {
        $params->{destination} = $destination->destination;
        if($cf_type eq 'cft') {
            my $rt = $ringtimeout_preference->first;
            if($rt) {
                $params->{ringtimeout} = $rt->value;
            } else {
                $params->{ringtimeout} = 15;
            }
        }
    }
    if($posted) {
        $params = $c->request->params;
        if(length($params->{destination}) && 
           (!$c->request->params->{submitid} || 
            $c->request->params->{submitid} eq "cf_actions.save")
           ) {
            if($params->{destination} !~ /\@/) {
                $params->{destination} .= '@'.$c->stash->{subscriber}->domain->domain;
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

    return if NGCP::Panel::Utils::Navigation::check_form_buttons(
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

                $cf_mapping = $cf_mapping->first; 
                unless(defined $cf_mapping) {
                    $cf_mapping = $prov_subscriber->voip_cf_mappings->create({
                        type => $cf_type,
                        # subscriber_id => $prov_subscriber->id,
                        destination_set_id => $dest_set->id,
                        time_set_id => undef, #$time_set_id,
                    });
                }
                foreach my $pref($cf_preference->all) {
                    $pref->delete;
                }
                $cf_preference->create({ value => $cf_mapping->id });
                if($cf_type eq 'cft') {
                    if($ringtimeout_preference->first) {
                        $ringtimeout_preference->first->update({ 
                            value => $c->request->params->{ringtimeout}
                        });
                    } else {
                        $ringtimeout_preference->create({
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

    # TODO bail out of $advanced ne "advanced"
    if(defined $advanced && $advanced eq 'advanced') {
        $advanced = 1;
    } else {
        $advanced = 0;
    }

    my $cf_desc;
    given($cf_type) {
        when("cfu") { $cf_desc = "Call Forward Unconditional" }
        when("cfb") { $cf_desc = "Call Forward Busy" }
        when("cft") { $cf_desc = "Call Forward Timeout" }
        when("cfna") { $cf_desc = "Call Forward Unavailable" }
        default {
            $c->log->error("Invalid call-forward type '$cf_type'");
            $c->flash(messages => [{type => 'error', text => 'Invalid Call Forward type'}]);
            $c->response->redirect($c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
            return;
        }
    }

    my $prov_subscriber = $c->stash->{subscriber}->provisioning_voip_subscriber;
    my $cf_mapping = $prov_subscriber->voip_cf_mappings->search_rs({ type => $cf_type });
    my $cf_preference = NGCP::Panel::Utils::Subscriber::get_usr_preference_rs(
            c => $c, prov_subscriber => $prov_subscriber, attribute => $cf_type);
    my $ringtimeout_preference = NGCP::Panel::Utils::Subscriber::get_usr_preference_rs(
            c => $c, prov_subscriber => $prov_subscriber, attribute => 'ringtimeout');

    # TODO: we can have more than one active, no?
    if($cf_mapping->count) {
        $c->stash->{cf_active_destination_set} = $cf_mapping->first->destination_set
            if($cf_mapping->first->destination_set);
        $c->stash->{cf_active_time_set} = $cf_mapping->first->time_set
            if($cf_mapping->first->time_set);
    }
    $c->stash->{cf_destination_sets} = $prov_subscriber->voip_cf_destination_sets;
    $c->stash->{cf_time_sets} = $prov_subscriber->voip_cf_time_sets;

    my $posted = ($c->request->method eq 'POST');

    my $cf_form;
    if($cf_type eq "cft") {
        $cf_form = NGCP::Panel::Form::SubscriberCFTAdvanced->new(ctx => $c);
    } else {
        $cf_form = NGCP::Panel::Form::SubscriberCFAdvanced->new(ctx => $c);
    }

    # TODO: handle ring-rimeout
    my @maps = ();
    foreach my $map($cf_mapping->all) {
        push @maps, {
            destination_set => $map->destination_set->id,
            time_set => $map->time_set ? $map->time_set->id : undef,
        };
    }
    my $params = { 
        active_callforward => \@maps, 
        ringtimeout =>  $ringtimeout_preference->first ? $ringtimeout_preference->first->value : 15,
    };

    $cf_form->process(
        params => $posted ? $c->request->params : $params,
    );


    return if NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c, form => $cf_form,
        fields => {
            'cf_actions.simple' => 
                $c->uri_for_action('/subscriber/preferences_callforward', 
                    [$c->req->captures->[0], $cf_type],
                ),
            'cf_actions.edit_destination_sets' => 
                $c->uri_for_action('/subscriber/preferences_callforward_destinationset', 
                    [$c->req->captures->[0]], $cf_type,
                ),
            'cf_actions.edit_time_sets' => 
                $c->uri_for_action('/subscriber/preferences_callforward_timeset', 
                    [$c->req->captures->[0]], $cf_type,
                ),
        },
        back_uri => $c->uri_for_action('/subscriber/preferences_callforward_advanced',
            [$c->req->captures->[0]], $cf_type, 'advanced'),
    );


    if($posted && $cf_form->validated) {
        try {
            $c->model('DB')->schema->txn_do( sub {
                my @active = $cf_form->field('active_callforward')->fields;
                if($cf_mapping->count) {
                    foreach my $map($cf_mapping->all) {
                        $map->delete;
                        foreach my $cf($cf_preference->all) {
                            $cf->delete;
                        }
                    }
                    unless(@active) {
                        $ringtimeout_preference->first->delete 
                            if($cf_type eq "cft" &&  $ringtimeout_preference->first);
                        $c->flash(messages => [{type => 'success', text => 'Successfully cleared Call Forward'}]);
                        $c->response->redirect(
                            $c->uri_for_action('/subscriber/preferences', 
                                [$c->req->captures->[0]])
                        );
                        return;
                    }
                }
                foreach my $map(@active) {
                    my $m = $cf_mapping->create({
                        type => $cf_type,
                        destination_set_id => $map->field('destination_set')->value,
                        time_set_id => $map->field('time_set')->value,
                    });
                    $cf_preference->create({ value => $m->id });
                }
                if($cf_type eq "cft") {
                    if($ringtimeout_preference->first) {
                        $ringtimeout_preference->first->update({ value => $cf_form->field('ringtimeout')->value });
                    } else {
                        $ringtimeout_preference->create({ value => $cf_form->field('ringtimeout')->value });
                    }
                }

                $c->flash(messages => [{type => 'success', text => 'Successfully saved Call Forward'}]);
                $c->response->redirect(
                    $c->uri_for_action('/subscriber/preferences', 
                        [$c->req->captures->[0]])
                );
                return;
            });
        } catch($e) {
            $c->log->error("failed to save call-forward: $e");
            $c->flash(messages => [{type => 'error', text => 'Failed to save Call Forward'}]);
            $c->response->redirect($c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
            return;
        }
    }


    $self->load_preference_list($c);
    $c->stash(template => 'subscriber/preferences.tt');
    $c->stash(
        edit_cf_flag => 1,
        cf_description => $cf_desc,
        cf_form => $cf_form,
    );
}

sub preferences_callforward_destinationset :Chained('base') :PathPart('preferences/destinationset') :Args(1) {
    my ($self, $c, $cf_type) = @_;

    my $prov_subscriber = $c->stash->{subscriber}->provisioning_voip_subscriber;

    my @sets;
    if($prov_subscriber->voip_cf_destination_sets) {
        foreach my $set($prov_subscriber->voip_cf_destination_sets->all) {
            if($set->voip_cf_destinations) {
                my @dests = map { { $_->get_columns } } $set->voip_cf_destinations->search({},
                    { order_by => { -asc => 'priority' }})->all;
                foreach my $d(@dests) {
                    $d->{as_string} = NGCP::Panel::Utils::Subscriber::destination_as_string($d);
                }
                push @sets, { name => $set->name, id => $set->id, destinations => \@dests };
            }
        }
    }
    $c->stash->{cf_sets} = \@sets;

    my $cf_form = undef;

    $self->load_preference_list($c);
    $c->stash(template => 'subscriber/preferences.tt');
    $c->stash(
        edit_cfset_flag => 1,
        cf_description => "Destination Sets",
        cf_form => $cf_form,
        close_target => $c->uri_for_action('/subscriber/preferences_callforward_advanced', 
                    [$c->req->captures->[0]], $cf_type, 'advanced'),
        cf_type => $cf_type,
    );
}

sub preferences_callforward_destinationset_create :Chained('base') :PathPart('preferences/destinationset/create') :Args(1) {
    my ($self, $c, $cf_type) = @_;

    my $prov_subscriber = $c->stash->{subscriber}->provisioning_voip_subscriber;

    my $form = NGCP::Panel::Form::DestinationSet->new;

    my $posted = ($c->request->method eq 'POST');

    $form->process(
        posted => $posted,
        params => $c->req->params,
    );

    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                my @fields = $form->field('destination')->fields;
                if(@fields) {
                    my $set = $prov_subscriber->voip_cf_destination_sets->create({
                        name => $form->field('name')->value,
                    });
                    my $number = $c->stash->{subscriber}->primary_number;
                    my $numberstr = "";
                    if(defined $number) {
                        $numberstr .= $number->cc;
                        $numberstr .= $number->ac if defined($number->ac);
                        $numberstr .= $number->sn;
                    } else {
                        $numberstr = $c->stash->{subscriber}->uuid;
                    }
                    foreach my $dest(@fields) {
                        my $d = $dest->field('destination')->value;
                        my $t = 300;
                        if($d eq "voicebox") {
                            $d = "sip:vmu$numberstr\@voicebox.local";
                        } elsif($d eq "fax2mail") {
                            $d = "sip:$numberstr\@fax2mail.local";
                        } elsif($d eq "conference") {
                            $d = "sip:conf=$numberstr\@conference.local";
                        } elsif($d eq "callingcard") {
                            $d = "sip:callingcard\@app.local";
                        } elsif($d eq "callthrough") {
                            $d = "sip:callthrough\@app.local";
                        } elsif($d eq "localuser") {
                            $d = "sip:localuser\@app.local";
                        } elsif($d eq "uri") {
                            $d = $dest->field('uri_destination')->value->[1];
                            # TODO: check for valid dest here
                            if($d !~ /\@/) {
                                $d .= '@'.$c->stash->{subscriber}->domain->domain;
                            }
                            if($d !~ /^sip:/) {
                                $d = 'sip:' . $d;
                            }
                            $t = $dest->field('uri_timeout')->value->[1];
                            # TODO: check for valid timeout here
                        }

                        $set->voip_cf_destinations->create({
                            destination => $d,
                            timeout => $t,
                            priority => $dest->field('priority')->value,
                        });
                    }
                    $c->response->redirect(
                        $c->uri_for_action('/subscriber/preferences_callforward_destinationset', 
                            [$c->req->captures->[0]], $cf_type)
                    );
                    return;
                }
            });
        } catch($e) {
            $c->log->error("failed to create new destination set: $e");
            $c->response->redirect($c->uri_for_action('/subscriber/preferences_callforward_destinationset', 
                    [$c->req->captures->[0]], $cf_type)
            );
            return;
        }

    }

    $self->load_preference_list($c);
    $c->stash(template => 'subscriber/preferences.tt');
    $c->stash(
        edit_cf_flag => 1,
        cf_description => "Destination Set",
        cf_form => $form,
        cf_type => $cf_type,
        close_target => $c->uri_for_action('/subscriber/preferences_callforward_destinationset', 
                    [$c->req->captures->[0]], $cf_type),
    );
}

sub preferences_callforward_destinationset_base :Chained('base') :PathPart('preferences/destinationset') :CaptureArgs(1) {
    my ($self, $c, $set_id) = @_;

    $c->stash(destination_set => $c->stash->{subscriber}
        ->provisioning_voip_subscriber
        ->voip_cf_destination_sets
        ->find($set_id));

    $self->load_preference_list($c);
    $c->stash(template => 'subscriber/preferences.tt');
}

sub preferences_callforward_destinationset_edit :Chained('preferences_callforward_destinationset_base') :PathPart('edit') :Args(1) {
    my ($self, $c, $cf_type) = @_;

    my $posted = ($c->request->method eq 'POST');

    my $cf_preference = NGCP::Panel::Utils::Subscriber::get_usr_preference_rs(
        c => $c, prov_subscriber => $c->stash->{subscriber}->provisioning_voip_subscriber,
        attribute => $cf_type,
    );
    my $ringtimeout_preference = NGCP::Panel::Utils::Subscriber::get_usr_preference_rs(
        c => $c, prov_subscriber => $c->stash->{subscriber}->provisioning_voip_subscriber,
        attribute => 'ringtimeout',
    );

    my $set =  $c->stash->{destination_set};
    my $params;
    unless($posted) {
        $params->{name} = $set->name;
        my @destinations;
        for my $dest($set->voip_cf_destinations->all) {
            my $d = $dest->destination;
            my $duri = undef;
            my $t = $dest->timeout;
            if($d =~ /\@voicebox\.local$/) {
                $d = 'voicebox';
            } elsif($d =~ /\@fax2mail\.local$/) {
                $d = 'fax2mail';
            } elsif($d =~ /\@conference\.local$/) {
                $d = 'conference';
            } elsif($d =~ /\@fax2mail\.local$/) {
                $d = 'fax2mail';
            } elsif($d =~ /^sip:callingcard\@app\.local$/) {
                $d = 'callingcard';
            } elsif($d =~ /^sip:callingthrough\@app\.local$/) {
                $d = 'callingcard';
            } elsif($d =~ /^sip:localuser\@.+\.local$/) {
                $d = 'localuser';
            } else {
                $duri = $d;
                $d = 'uri';
            }
            push @destinations, { 
                destination => $d,
                uri_timeout => $t,
                uri_destination => $duri,
                priority => $dest->priority,
                id => $dest->id,
            };
        }
        $params->{destination} = \@destinations;
    }

    $c->stash->{cf_tmp_params} = $params;
    my $form = NGCP::Panel::Form::DestinationSet->new(ctx => $c);
    $form->process(
        params => $posted ? $c->req->params : $params
    );
    delete $c->stash->{cf_tmp_params};

    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                # delete whole set and mapping if empty
                my @fields = $form->field('destination')->fields;
                unless(@fields) {
                    foreach my $mapping($set->voip_cf_mappings) {
                        my $cf = $cf_preference->find({ value => $mapping->id });
                        $cf->delete if $cf;
                        $ringtimeout_preference->first->delete 
                            if($cf_type eq "cft" && $ringtimeout_preference->first);
                        $mapping->delete;
                    }
                    $set->delete;

                    $c->response->redirect(
                        $c->uri_for_action('/subscriber/preferences_callforward_destinationset', 
                            [$c->req->captures->[0]], $cf_type)
                    );
                    return;
                }
                if($form->field('name')->value ne $set->name) {
                    $set->update({name => $form->field('name')->value});
                }
                foreach my $dest($set->voip_cf_destinations->all) {
                    $dest->delete;
                }

                my $number = $c->stash->{subscriber}->primary_number;
                my $numberstr = "";
                if(defined $number) {
                    $numberstr .= $number->cc;
                    $numberstr .= $number->ac if defined($number->ac);
                    $numberstr .= $number->sn;
                } else {
                    $numberstr = $c->stash->{subscriber}->uuid;
                }
                foreach my $dest($form->field('destination')->fields) {
                    my $d = $dest->field('destination')->value;
                    my $t = 300;
                    if($d eq "voicebox") {
                        $d = "sip:vmu$numberstr\@voicebox.local";
                    } elsif($d eq "fax2mail") {
                        $d = "sip:$numberstr\@fax2mail.local";
                    } elsif($d eq "conference") {
                        $d = "sip:conf=$numberstr\@conference.local";
                    } elsif($d eq "callingcard") {
                        $d = "sip:callingcard\@app.local";
                    } elsif($d eq "callthrough") {
                        $d = "sip:callthrough\@app.local";
                    } elsif($d eq "localuser") {
                        $d = "sip:localuser\@app.local";
                    } elsif($d eq "uri") {
                        $d = $dest->field('uri_destination')->value->[1];
                        # TODO: check for valid dest here
                        if($d !~ /\@/) {
                            $d .= '@'.$c->stash->{subscriber}->domain->domain;
                        }
                        if($d !~ /^sip:/) {
                            $d = 'sip:' . $d;
                        }
                        $t = $dest->field('uri_timeout')->value->[1];
                        # TODO: check for valid timeout here
                    }

                    $set->voip_cf_destinations->create({
                        destination => $d,
                        timeout => $t,
                        priority => $dest->field('priority')->value,
                    });
                }

                $c->response->redirect(
                    $c->uri_for_action('/subscriber/preferences_callforward_destinationset', 
                        [$c->req->captures->[0]], $cf_type)
                );
                return;
            });
        } catch($e) {
            $c->log->error("failed to update destination set: $e");
            $c->response->redirect(
                $c->uri_for_action('/subscriber/preferences_callforward_destinationset', 
                    [$c->req->captures->[0]], $cf_type)
            );
            return;
        }
    }

    $c->stash(
        edit_cf_flag => 1,
        cf_description => "Destination Set",
        cf_form => $form,
        close_target => $c->uri_for_action('/subscriber/preferences_callforward_destinationset', 
                    [$c->req->captures->[0]], $cf_type),
    );

}

sub preferences_callforward_destinationset_delete :Chained('preferences_callforward_destinationset_base') :PathPart('delete') :Args(1) {
    my ($self, $c, $cf_type) = @_;

    my $cf_preference = NGCP::Panel::Utils::Subscriber::get_usr_preference_rs(
        c => $c, prov_subscriber => $c->stash->{subscriber}->provisioning_voip_subscriber,
        attribute => $cf_type,
    );
    my $ringtimeout_preference = NGCP::Panel::Utils::Subscriber::get_usr_preference_rs(
        c => $c, prov_subscriber => $c->stash->{subscriber}->provisioning_voip_subscriber,
        attribute => 'ringtimeout',
    );
    my $set =  $c->stash->{destination_set};
    my $prov_subscriber = $c->stash->{subscriber}->provisioning_voip_subscriber;

    try {
        my $schema = $c->model('DB');
        $schema->txn_do(sub {
            foreach my $map($set->voip_cf_mappings->all) {
                my $cf = $cf_preference->find({ value => $map->id });
                $cf->delete if $cf;
                $map->delete;
            }
            if($cf_type eq "cft" && 
               $prov_subscriber->voip_cf_mappings->search_rs({ type => $cf_type})->count == 0) {
                $ringtimeout_preference->first->delete;
            }
            $set->delete;
        });
    } catch($e) {
        $c->log->error("failed to delete destination set: $e");
    }

    $c->response->redirect(
        $c->uri_for_action('/subscriber/preferences_callforward_destinationset', 
            [$c->req->captures->[0]], $cf_type)
    );
    return;
}

sub preferences_callforward_timeset :Chained('base') :PathPart('preferences/timeset') :Args(1) {
    my ($self, $c, $cf_type) = @_;

    my $prov_subscriber = $c->stash->{subscriber}->provisioning_voip_subscriber;

    my @sets;
    if($prov_subscriber->voip_cf_time_sets) {
        foreach my $set($prov_subscriber->voip_cf_time_sets->all) {
            if($set->voip_cf_periods) {
                my @periods = map { { $_->get_columns } } $set->voip_cf_periods->all;
                foreach my $p(@periods) {
                    $p->{as_string} = NGCP::Panel::Utils::Subscriber::period_as_string($p);
                }
                push @sets, { name => $set->name, id => $set->id, periods => \@periods};
            }
        }
    }
    $c->stash->{cf_sets} = \@sets;

    my $cf_form = undef;

    $self->load_preference_list($c);
    $c->stash(template => 'subscriber/preferences.tt');
    $c->stash(
        edit_timeset_flag => 1,
        cf_description => "Time Sets",
        cf_form => $cf_form,
        close_target => $c->uri_for_action('/subscriber/preferences_callforward_advanced', 
                    [$c->req->captures->[0]], $cf_type, 'advanced'),
        cf_type => $cf_type,
    );
}

sub preferences_callforward_timeset_create :Chained('base') :PathPart('preferences/timeset/create') :Args(1) {
    my ($self, $c, $cf_type) = @_;

    my $prov_subscriber = $c->stash->{subscriber}->provisioning_voip_subscriber;

    my $form = NGCP::Panel::Form::TimeSet->new;

    my $posted = ($c->request->method eq 'POST');

    $form->process(
        posted => $posted,
        params => $c->req->params,
    );

    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                my @fields = $form->field('period')->fields;
                if(@fields) {
                    my $set = $prov_subscriber->voip_cf_time_sets->create({
                        name => $form->field('name')->value,
                    });

                    foreach my $period($form->field('period')->fields) {
                        my $fields = {};
                        for my $type (qw/year month mday wday hour minute/) {
                            my $row = $period->field("row");
                            my $from = $row->field($type)->field("from")->value;
                            my $to = $row->field($type)->field("to")->value;
                            if($type eq "wday") {
                                $from = int($from)+1 if defined($from);
                                $to = int($to)+1 if defined($to);
                            }
                            if(defined $from) {
                                $fields->{$type} = $from .
                                    (defined $to ?
                                        '-'.$to : '');
                            }
                        }
                        $set->voip_cf_periods->create($fields);
                    }

                    $c->response->redirect(
                        $c->uri_for_action('/subscriber/preferences_callforward_timeset', 
                            [$c->req->captures->[0]], $cf_type)
                    );
                    return;
                }
            });
        } catch($e) {
            $c->log->error("failed to create new time set: $e");
            $c->response->redirect($c->uri_for_action('/subscriber/preferences_callforward_timeset', 
                    [$c->req->captures->[0]], $cf_type)
            );
            return;
        }

    }

    $self->load_preference_list($c);
    $c->stash(template => 'subscriber/preferences.tt');
    $c->stash(
        edit_cf_flag => 1,
        cf_description => "Time Set",
        cf_form => $form,
        cf_type => $cf_type,
        close_target => $c->uri_for_action('/subscriber/preferences_callforward_timeset', 
                    [$c->req->captures->[0]], $cf_type),
    );
}

sub preferences_callforward_timeset_base :Chained('base') :PathPart('preferences/timeset') :CaptureArgs(1) {
    my ($self, $c, $set_id) = @_;

    $c->stash(time_set => $c->stash->{subscriber}
        ->provisioning_voip_subscriber
        ->voip_cf_time_sets
        ->find($set_id));

    $self->load_preference_list($c);
    $c->stash(template => 'subscriber/preferences.tt');
}

sub preferences_callforward_timeset_edit :Chained('preferences_callforward_timeset_base') :PathPart('edit') :Args(1) {
    my ($self, $c, $cf_type) = @_;

    my $form = NGCP::Panel::Form::TimeSet->new;

    my $posted = ($c->request->method eq 'POST');

    my $set =  $c->stash->{time_set};
    my $params;
    unless($posted) {
        $params->{name} = $set->name;
        my @periods;
        for my $period($set->voip_cf_periods->all) {
            my $p = {};
            foreach my $type(qw/year month mday wday hour minute/) {
                my $val = $period->$type;
                if(defined $val) {
                    my ($from, $to) = split/\-/, $val;
                    if($type eq "wday") {
                        $from = int($from)-1 if defined($from);
                        $to = int($to)-1 if defined($to);
                    }
                    $p->{row}->{$type}->{from} = $from;
                    $p->{row}->{$type}->{to} = $to if defined($to);
                }
            }
            push @periods, $p;
        }
        $params->{period} = \@periods;
    }

    $form->process(
        params => $posted ? $c->req->params : $params
    );

    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                my @fields = $form->field('period')->fields;
                unless(@fields) {
                    foreach my $mapping($set->voip_cf_mappings) {
                        $mapping->update({ time_set_id => undef });
                    }
                    $set->delete;

                    $c->response->redirect(
                        $c->uri_for_action('/subscriber/preferences_callforward_timeset', 
                            [$c->req->captures->[0]], $cf_type)
                    );
                    return;
                }
                if($form->field('name')->value ne $set->name) {
                    $set->update({name => $form->field('name')->value});
                }
                foreach my $period($set->voip_cf_periods->all) {
                    $period->delete;
                }
                foreach my $period($form->field('period')->fields) {
                    my $fields = {};
                    for my $type (qw/year month mday wday hour minute/) {
                        my $row = $period->field("row");
                        my $from = $row->field($type)->field("from")->value;
                        my $to = $row->field($type)->field("to")->value;
                        if($type eq "wday") {
                            $from = int($from)+1 if defined($from);
                            $to = int($to)+1 if defined($to);
                        }
                        if(defined $from) {
                            $fields->{$type} = $from .
                                (defined $to ?
                                    '-'.$to : '');
                        }
                    }
                    $set->voip_cf_periods->create($fields);
                }
                $c->response->redirect(
                    $c->uri_for_action('/subscriber/preferences_callforward_timeset', 
                        [$c->req->captures->[0]], $cf_type)
                );
                return;
            });
        } catch($e) {
            $c->log->error("failed to update time set: $e");
            $c->response->redirect(
                $c->uri_for_action('/subscriber/preferences_callforward_timeset', 
                    [$c->req->captures->[0]], $cf_type)
            );
            return;
        }
    }

    $c->stash(
        edit_cf_flag => 1,
        cf_description => "Time Set",
        cf_form => $form,
        close_target => $c->uri_for_action('/subscriber/preferences_callforward_timeset', 
                    [$c->req->captures->[0]], $cf_type),
    );

}

sub preferences_callforward_timeset_delete :Chained('preferences_callforward_timeset_base') :PathPart('delete') :Args(1) {
    my ($self, $c, $cf_type) = @_;

    my $set =  $c->stash->{time_set};

    try {
        my $schema = $c->model('DB');
        $schema->txn_do(sub {
            foreach my $map($set->voip_cf_mappings->all) {
                $map->update({ time_set_id => undef });
            }
            $set->delete;
        });
    } catch($e) {
        $c->log->error("failed to delete time set: $e");
    }

    $c->response->redirect(
        $c->uri_for_action('/subscriber/preferences_callforward_timeset', 
            [$c->req->captures->[0]], $cf_type)
    );
    return;
}

sub preferences_callforward_delete :Chained('base') :PathPart('preferences/callforward/delete') :Args(1) {
    my ($self, $c, $cf_type) = @_;

    try {
        #$c->model('DB')->resultset('voip_cf_mappings')->find($cfmap_id)->delete;
        # TODO: we need to delete all mappings for the cf_type here!
        # also, we need to delete all usr_preferences of cf_type!
        $c->flash(messages => [{type => 'error', text => 'TODO: Successfully deleted Call Forward'}]);
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

sub master :Chained('base') :PathPart('details') :CaptureArgs(0) {
    my ($self, $c) = @_;

    $c->stash->{calls_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "source_user", search => 1, title => "Caller" },
        { name => "destination_user", search => 1, title => "Callee" },
        { name => "call_status", search => 1, title => "Status" },
        { name => "start_time", search => 1, title => "Start Time" },
        { name => "duration", search => 1, title => "Duration" },
    ]);

    $c->stash(
        template => 'subscriber/master.tt',
    );
}

sub details :Chained('master') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub ajax_calls :Chained('master') :PathPart('calls/ajax') :Args(0) {
    my ($self, $c) = @_;

    my $out_rs = $c->model('DB')->resultset('cdr')->search({
        source_user_id => $c->stash->{subscriber}->uuid,
    });
    my $in_rs = $c->model('DB')->resultset('cdr')->search({
        destination_user_id => $c->stash->{subscriber}->uuid,
    });
    my $rs = $out_rs->union($in_rs);

    NGCP::Panel::Utils::Datatables::process($c, $rs, $c->stash->{calls_dt_columns});

    $c->detach( $c->view("JSON") );
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
