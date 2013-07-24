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
use NGCP::Panel::Form::SubscriberEdit;
use NGCP::Panel::Form::SubscriberCFSimple;
use NGCP::Panel::Form::SubscriberCFTSimple;
use NGCP::Panel::Form::SubscriberCFAdvanced;
use NGCP::Panel::Form::SubscriberCFTAdvanced;
use NGCP::Panel::Form::DestinationSet;
use NGCP::Panel::Form::TimeSet;
use NGCP::Panel::Form::Voicemail::Pin;
use NGCP::Panel::Form::Voicemail::Email;
use NGCP::Panel::Form::Voicemail::Attach;
use NGCP::Panel::Form::Voicemail::Delete;
use NGCP::Panel::Form::Reminder;
use NGCP::Panel::Form::Subscriber::TrustedSource;
use NGCP::Panel::Form::Subscriber::Location;
use NGCP::Panel::Form::Faxserver::Name;
use NGCP::Panel::Form::Faxserver::Password;
use NGCP::Panel::Form::Faxserver::Active;
use NGCP::Panel::Form::Faxserver::SendStatus;
use NGCP::Panel::Form::Faxserver::SendCopy;
use NGCP::Panel::Form::Faxserver::Destination;

use NGCP::Panel::Utils::XMLDispatcher;
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
                if($number) {
                    $schema->resultset('dbaliases')->create({
                        alias_username => $number->cc .
                                          ($number->ac || '').
                                          $number->sn,
                        alias_domain => $prov_subscriber->domain->domain,
                        username => $prov_subscriber->username,
                        domain => $prov_subscriber->domain->domain,
                    });
                }

                my $cli = 0;
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
                        $cli = $c->request->params->{'e164.cc'} .
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
                $schema->resultset('voicemail_users')->create({
                    customer_id => $uuid_string,
                    mailbox => $cli,
                    password => sprintf("%04d", int(rand 10000)),
                    email => '',
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
    if($posted) {
        # TODO: normalize
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
    } else {
        my $ringtimeout = 15;
        if($cf_type eq 'cft') {
            my $rt = $ringtimeout_preference->first;
            if($rt) {
                $ringtimeout = $rt->value;
            }
        }
        my $d = $destination ? $destination->destination : "";
        my $duri = undef;
        my $t = $destination ? ($destination->timeout || 300) : 300;
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
        } elsif($d =~ /^sip:callthrough\@app\.local$/) {
            $d = 'callthrough';
        } elsif($d =~ /^sip:localuser\@.+\.local$/) {
            $d = 'localuser';
        } else {
            $duri = $d;
            $d = 'uri';
            $c->stash->{cf_tmp_params} = {
                uri_destination => $duri,
                uri_timeout => $t,
                id => $destination ? $destination->id : undef,
            };
        }
        $params = $c->stash->{cf_tmp_params};
        $params->{destination} = { destination => $d };
        $params->{ringtimeout} = $ringtimeout;
    }

    my $cf_form;
    if($cf_type eq "cft") {
        $cf_form = NGCP::Panel::Form::SubscriberCFTSimple->new(ctx => $c);
    } else {
        $cf_form = NGCP::Panel::Form::SubscriberCFSimple->new(ctx => $c);
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

                my $numberstr = "";
                my $number = $c->stash->{subscriber}->primary_number;
                if(defined $number) {
                    $numberstr .= $number->cc;
                    $numberstr .= $number->ac if defined($number->ac);
                    $numberstr .= $number->sn;
                } else {
                    $numberstr = $c->stash->{subscriber}->uuid;
                }
                my $dest = $cf_form->field('destination');
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

                $dest_set->voip_cf_destinations->create({
                    destination => $d,
                    timeout => $t,
                    priority => 1,
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
        close_target => $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]),
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
            } elsif($d =~ /^sip:callthrough\@app\.local$/) {
                $d = 'callthrough';
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
        { name => "start_time", search_from_epoch => 1, search_to_epoch => 1, title => "Start Time" },
        { name => "duration", search => 1, title => "Duration" },
    ]);
    $c->stash->{vm_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => "#" },
        { name => "callerid", search => 1, title => "Caller" },
        { name => "origtime", search_from_epoch => 1, search_to_epoch => 1, title => "Time" },
        { name => "duration", search => 1, title => "Duration" },
    ]);
    $c->stash->{reg_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => "#" },
        { name => "user_agent", search => 1, title => "User Agent" },
        { name => "contact", search => 1, title => "Contact" },
        { name => "expires", search => 1, title => "Expires" },
    ]);

    $c->stash(
        template => 'subscriber/master.tt',
    );
}

sub details :Chained('master') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub edit_master :Chained('master') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;

    my $form = NGCP::Panel::Form::SubscriberEdit->new;
    my $posted = ($c->request->method eq 'POST');
    my $subscriber = $c->stash->{subscriber};
    my $prov_subscriber = $subscriber->provisioning_voip_subscriber;

    my $params;
    my $lock = NGCP::Panel::Utils::Subscriber::get_usr_preference_rs(
        c => $c,
        attribute => 'lock',
        prov_subscriber => $prov_subscriber,
    );

    unless($posted) {
        $params->{webusername} = $prov_subscriber->webusername;
        $params->{webpassword} = $prov_subscriber->webpassword;
        $params->{password} = $prov_subscriber->password;
        $params->{administrative} = $prov_subscriber->admin;
        if($subscriber->primary_number) {
            $params->{e164}->{cc} = $subscriber->primary_number->cc;
            $params->{e164}->{ac} = $subscriber->primary_number->ac;
            $params->{e164}->{sn} = $subscriber->primary_number->sn;
        }
        my @alias_nums = ();
        for my $num($subscriber->voip_numbers->all) {
            next if $subscriber->primary_number && 
                $num->id == $subscriber->primary_number->id;
            push @alias_nums, { e164 => { cc => $num->cc, ac => $num->ac, sn => $num->sn } };
        }
        $params->{alias_number} = \@alias_nums;
        $params->{status} = $subscriber->status;
        $params->{external_id} = $subscriber->external_id;

        $params->{lock} = $lock->first ? $lock->first->value : undef;
    }

    $form->process(
        params => $posted ? $c->request->params : $params
    );

    if($posted && $form->validated) {
        my $schema = $c->model('DB');
        try {
            $schema->txn_do(sub {
                $prov_subscriber->update({
                    webusername => $form->field('webusername')->value,
                    webpassword => $form->field('webpassword')->value,
                    password => $form->field('password')->value,
                    admin => $form->field('administrative')->value,
                });
                $subscriber->update({
                    status => $form->field('status')->value,
                    external_id => $form->field('external_id')->value,
                });

                for my $num($subscriber->voip_numbers->all) {
                    next if($subscriber->primary_number && $num->id == $subscriber->primary_number->id);
                    $num->delete;
                }

                for my $alias($schema->resultset('dbaliases')->search({
                                    username => $prov_subscriber->username,
                                    domain => $prov_subscriber->domain->domain,
                                })->all) {
                    $alias->delete;
                }

                # TODO: check for availablity of cc and sn
                my $num;
                if($subscriber->primary_number) {
                    if(!$form->field('e164')->field('cc')->value &&
                       !$form->field('e164')->field('ac')->value &&
                       !$form->field('e164')->field('sn')->value) {
                        $subscriber->primary_number->delete;
                        $prov_subscriber->voicemail_user->update({ mailbox => '0' });
                    } else {
                        # check if cc and sn are set if cc is there
                        $num = $subscriber->primary_number->update({
                            cc => $form->field('e164')->field('cc')->value,
                            ac => $form->field('e164')->field('ac')->value || '',
                            sn => $form->field('e164')->field('sn')->value,
                        });
                        my $cli = $num->cc.($num->ac || '').$num->sn;
                        for my $cfset($prov_subscriber->voip_cf_destination_sets->all) {
                            for my $cf($cfset->voip_cf_destinations->all) {
                                if($cf->destination =~ /\@voicebox\.local$/) {
                                    $cf->update({ destination => 'sip:vmu'.$cli.'@voicebox.local' });
                                } elsif($cf->destination =~ /\@fax2mail\.local$/) {
                                    $cf->update({ destination => 'sip:'.$cli.'@fax2mail.local' });
                                } elsif($cf->destination =~ /\@conference\.local$/) {
                                    $cf->update({ destination => 'sip:conf='.$cli.'@conference.local' });
                                }
                            }
                        }
                        $prov_subscriber->voicemail_user->update({ mailbox => $cli });
                    }
                } else {
                    if($form->field('e164')->field('cc')->value &&
                       $form->field('e164')->field('sn')->value) {
                        $num = $schema->resultset('voip_numbers')->create({
                            subscriber_id => $subscriber->id,
                            reseller_id => $subscriber->contract->reseller_id,
                            cc => $form->field('e164')->field('cc')->value,
                            ac => $form->field('e164')->field('ac')->value || '',
                            sn => $form->field('e164')->field('sn')->value,
                        });
                        $subscriber->update({ primary_number_id => $num->id });
                        $prov_subscriber->voicemail_user->update({ mailbox => 
                            $form->field('e164')->field('cc')->value .
                            ($form->field('e164')->field('ac')->value || '').
                            $form->field('e164')->field('sn')->value,
                        });
                    } else {
                        $prov_subscriber->voicemail_user->update({ mailbox => '0' });
                    }

                }
                if($num) {
                    $schema->resultset('dbaliases')->create({
                        alias_username => $num->cc.($num->ac || '').$num->sn,
                        alias_domain => $prov_subscriber->domain->domain,
                        username => $prov_subscriber->username,
                        domain => $prov_subscriber->domain->domain,
                    });
                    my $cli = $num->cc.($num->ac || '').$num->sn;
                    for my $cfset($prov_subscriber->voip_cf_destination_sets->all) {
                        for my $cf($cfset->voip_cf_destinations->all) {
                            if($cf->destination =~ /\@voicebox\.local$/) {
                                $cf->update({ destination => 'sip:vmu'.$cli.'@voicebox.local' });
                            } elsif($cf->destination =~ /\@fax2mail\.local$/) {
                                $cf->update({ destination => 'sip:'.$cli.'@fax2mail.local' });
                            } elsif($cf->destination =~ /\@conference\.local$/) {
                                $cf->update({ destination => 'sip:conf='.$cli.'@conference.local' });
                            }
                        }
                    }
                }
                for my $alias($form->field('alias_number')->fields) {
                    $num = $subscriber->voip_numbers->create({
                        cc => $alias->field('e164')->field('cc')->value,
                        ac => $alias->field('e164')->field('ac')->value,
                        sn => $alias->field('e164')->field('sn')->value,
                    });
                    $schema->resultset('dbaliases')->create({
                        alias_username => $num->cc.($num->ac || '').$num->sn,
                        alias_domain => $prov_subscriber->domain->domain,
                        username => $prov_subscriber->username,
                        domain => $prov_subscriber->domain->domain,
                    });
                }

                if($lock->first) {
                    $lock->first->update({ value => $form->field('lock')->value });
                } else {
                    $lock->create({ value => $form->field('lock')->value });
                }
            });
            $c->flash(messages => [{type => 'success', text => 'Successfully updated subscriber'}]);
        } catch($e) {
            $c->log->error("failed to update subscriber: $e");
            $c->flash(messages => [{type => 'error', text => 'Failed to update subscriber'}]);
        }

        $c->response->redirect($c->uri_for_action('/subscriber/details', [$c->req->captures->[0]]));
        return;
    }

    $c->stash(
        edit_flag => 1,
        description => 'Subscriber Master Data',
        form => $form,
        close_target => $c->uri_for_action('/subscriber/details', [$c->req->captures->[0]]),
    );

}

sub edit_voicebox :Chained('base') :PathPart('preferences/voicebox/edit') :Args(1) {
    my ($self, $c, $attribute) = @_;

    my $form;
    my $posted = ($c->request->method eq 'POST');
    my $vm_user = $c->stash->{subscriber}->provisioning_voip_subscriber->voicemail_user;
    unless($vm_user) {
        $c->log->error("no voicemail user found for subscriber uuid ".$c->stash->{subscriber}->uuid);
        $c->flash(messages => [{type => 'error', text => 'Failed to find voicemail user'}]);
        $c->response->redirect($c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
        return;
        # TODO: we could create one instead?
    }
    my $params;

    try {
        given($attribute) {
            when('pin') { 
                $form = NGCP::Panel::Form::Voicemail::Pin->new;
                $params = { 'pin' => $vm_user->password };
                $form->process(params => $posted ? $c->req->params : $params);
                if($posted && $form->validated) {
                    $vm_user->update({ password => $form->field('pin')->value });
                }
            }
            when('email') { 
                $form = NGCP::Panel::Form::Voicemail::Email->new; 
                $params = { 'email' => $vm_user->email };
                $form->process(params => $posted ? $c->req->params : $params);
                if($posted && $form->validated) {
                    $vm_user->update({ email => $form->field('email')->value });
                }
            }
            when('attach') { 
                $form = NGCP::Panel::Form::Voicemail::Attach->new; 
                $params = { 'attach' => $vm_user->attach eq 'yes' ? 1 : 0 };
                $form->process(params => $posted ? $c->req->params : $params);
                if($posted && $form->validated) {
                    $vm_user->update({ attach => $form->field('attach')->value ? 'yes' : 'no' });
                }
            }
            when('delete') { 
                $form = NGCP::Panel::Form::Voicemail::Delete->new; 
                $params = { 'delete' => $vm_user->get_column('delete') eq 'yes' ? 1 : 0 };
                $form->process(params => $posted ? $c->req->params : $params);
                if($posted && $form->validated) {
                    $vm_user->update({ 
                        delete => $form->field('delete')->value ? 'yes' : 'no',
                        # force attach if delete flag is set, otherwise message will be lost
                        'attach' => $form->field('delete')->value ? 'yes' : $vm_user->attach,
                    });
                }
            }
            default {
                $c->log->error("trying to set invalid voicemail param '$attribute' for subscriber uuid ".$c->stash->{subscriber}->uuid);
                $c->flash(messages => [{type => 'error', text => 'Invalid voicemail setting'}]);
                $c->response->redirect($c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
                return;
            }
        }
        if($posted && $form->validated) {
            $c->flash(messages => [{type => 'success', text => 'Successfully updated voicemail setting'}]);
            $c->response->redirect($c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
            return;
        }
    } catch($e) {
        $c->log->error("updating voicemail setting failed: $e");
        $c->flash(messages => [{type => 'error', text => 'Failed to update voicemail setting'}]);
        $c->response->redirect($c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
        return;
    }

    $c->stash(
        template => 'subscriber/preferences.tt',
        edit_cf_flag => 1,
        cf_description => $attribute,
        cf_form => $form,
        close_target => $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]),
    );
}

sub edit_fax :Chained('base') :PathPart('preferences/fax/edit') :Args(1) {
    my ($self, $c, $attribute) = @_;

    my $form;
    my $posted = ($c->request->method eq 'POST');
    my $prov_subscriber = $c->stash->{subscriber}->provisioning_voip_subscriber;
    my $faxpref = $prov_subscriber->voip_fax_preference;
    my $params = {};
    my $faxpref_rs = $c->model('DB')->resultset('voip_fax_preferences')->search({
                            subscriber_id => $prov_subscriber->id
                        });
    if(!$faxpref) {
        $faxpref = $faxpref_rs->create({});
    }

    try {
        given($attribute) {
            when('name') { 
                $form = NGCP::Panel::Form::Faxserver::Name->new;
                $params = { 'name' => $faxpref->name };
                $form->process(params => $posted ? $c->req->params : $params);
                if($posted && $form->validated) {
                    $faxpref->update({ name => $form->field('name')->value });
                }
            }
            when('password') { 
                $form = NGCP::Panel::Form::Faxserver::Password->new;
                $params = { 'password' => $faxpref->password };
                $form->process(params => $posted ? $c->req->params : $params);
                if($posted && $form->validated) {
                    $faxpref->update({ password => $form->field('password')->value });
                }
            }
            when('active') { 
                $form = NGCP::Panel::Form::Faxserver::Active->new;
                $params = { 'active' => $faxpref->active };
                $form->process(params => $posted ? $c->req->params : $params);
                if($posted && $form->validated) {
                    $faxpref->update({ active => $form->field('active')->value });
                }
            }
            when('send_status') { 
                $form = NGCP::Panel::Form::Faxserver::SendStatus->new;
                $params = { 'send_status' => $faxpref->send_status };
                $form->process(params => $posted ? $c->req->params : $params);
                if($posted && $form->validated) {
                    $faxpref->update({ send_status => $form->field('send_status')->value });
                }
            }
            when('send_copy') { 
                $form = NGCP::Panel::Form::Faxserver::SendCopy->new;
                $params = { 'send_copy' => $faxpref->send_copy };
                $form->process(params => $posted ? $c->req->params : $params);
                if($posted && $form->validated) {
                    $faxpref->update({ send_copy => $form->field('send_copy')->value });
                }
            }
            when('destinations') { 
                $form = NGCP::Panel::Form::Faxserver::Destination->new;
                unless($posted) {
                    my @dests = ();
                    for my $dest($prov_subscriber->voip_fax_destinations->all) {
                        push @dests, {
                            destination => $dest->destination,
                            filetype => $dest->filetype,
                            cc => $dest->cc,
                            incoming => $dest->incoming,
                            outgoing => $dest->outgoing,
                            status => $dest->status,
                        }
                    }
                    $params->{destination} = \@dests;
                }
                $form->process(params => $posted ? $c->req->params : $params);
                if($posted && $form->validated) {
                    for my $dest($prov_subscriber->voip_fax_destinations->all) {
                        $dest->delete;
                    }
                    for my $dest($form->field('destination')->fields) {
                        $prov_subscriber->voip_fax_destinations->create({
                            destination => $dest->field('destination')->value,
                            filetype => $dest->field('filetype')->value,
                            cc => $dest->field('cc')->value,
                            incoming => $dest->field('incoming')->value,
                            outgoing => $dest->field('outgoing')->value,
                            status => $dest->field('status')->value,
                        });
                    }
                }
            }
            default {
                $c->log->error("trying to set invalid fax param '$attribute' for subscriber uuid ".$c->stash->{subscriber}->uuid);
                $c->flash(messages => [{type => 'error', text => 'Invalid fax setting'}]);
                $c->response->redirect($c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
                return;
            }
        }
        if($posted && $form->validated) {
            $c->flash(messages => [{type => 'success', text => 'Successfully updated fax setting'}]);
            $c->response->redirect($c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
            return;
        }
    } catch($e) {
        $c->log->error("updating fax setting failed: $e");
        $c->flash(messages => [{type => 'error', text => 'Failed to update fax setting'}]);
        $c->response->redirect($c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
        return;
    }

    $c->stash(
        template => 'subscriber/preferences.tt',
        edit_cf_flag => 1,
        cf_description => $attribute,
        cf_form => $form,
        close_target => $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]),
    );
}

sub edit_reminder :Chained('base') :PathPart('preferences/reminder/edit') {
    my ($self, $c, $attribute) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $reminder = $c->stash->{subscriber}->provisioning_voip_subscriber->voip_reminder;
    my $params = {};
    
    if(!$posted && $reminder) {
        $params = { 'time' => $reminder->column_time, recur => $reminder->recur};
    }

    my $form = NGCP::Panel::Form::Reminder->new;
    $form->process(
        params => $posted ? $c->req->params : $params
    );

    if($posted && $form->validated) {

        try {
            if($form->field('time')->value) {
                my $t = $form->field('time')->value;
                $t =~ s/^(\d+:\d+)(:\d+)?$/$1/; # strip seconds
                if($reminder) {
                    $reminder->update({
                        time => $t,
                        recur => $form->field('recur')->value,
                    });
                } else {
                    $c->model('DB')->resultset('voip_reminder')->create({
                        subscriber_id => $c->stash->{subscriber}->provisioning_voip_subscriber->id,
                        time => $t,
                        recur => $form->field('recur')->value,
                    });
                }
            } elsif($reminder) {
                $reminder->delete;
            }

            $c->flash(messages => [{type => 'success', text => 'Successfully updated reminder setting'}]);
            $c->response->redirect($c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
            return;
        } catch($e) {
            $c->log->error("updating reminder setting failed: $e");
            $c->flash(messages => [{type => 'error', text => 'Failed to update reminder setting'}]);
            $c->response->redirect($c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
            return;
        }
    }

    $c->stash(
        template => 'subscriber/preferences.tt',
        edit_cf_flag => 1,
        cf_description => 'Reminder',
        cf_form => $form,
        close_target => $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]),
    );
}

sub ajax_calls :Chained('master') :PathPart('calls/ajax') :Args(0) {
    my ($self, $c) = @_;

    # CDRs
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

sub ajax_registered :Chained('master') :PathPart('registered/ajax') :Args(0) {
    my ($self, $c) = @_;

    my $s = $c->stash->{subscriber}->provisioning_voip_subscriber;
    my $reg_rs = $c->model('DB')->resultset('location')->search({
        username => $s->username,
        domain => $s->domain->domain,
    });
    NGCP::Panel::Utils::Datatables::process($c, $reg_rs, $c->stash->{reg_dt_columns});

    $c->detach( $c->view("JSON") );
}

sub ajax_voicemails :Chained('master') :PathPart('voicemails/ajax') :Args(0) {
    my ($self, $c) = @_;

    my $vm_rs = $c->model('DB')->resultset('voicemail_spool')->search({
        mailboxuser => $c->stash->{subscriber}->uuid,
    });
    NGCP::Panel::Utils::Datatables::process($c, $vm_rs, $c->stash->{vm_dt_columns});

    $c->detach( $c->view("JSON") );
}

sub voicemail :Chained('master') :PathPart('voicemail') :CaptureArgs(1) {
    my ($self, $c, $vm_id) = @_;

    my $rs = $c->model('DB')->resultset('voicemail_spool')->search({
         mailboxuser => $c->stash->{subscriber}->uuid,
         id => $vm_id,
    });
    unless($rs->first) {
        $c->log->error("no such voicemail file with id '$vm_id' for uuid ".$c->stash->{subscriber}->uuid);
        $c->flash(messages => [{type => 'error', text => 'No such voicemail file to play'}]);
        $c->response->redirect($c->uri_for_action('/subscriber/details', [$c->req->captures->[0]]));
        return;
    }
    $c->stash->{voicemail} = $rs->first;
}

sub play_voicemail :Chained('voicemail') :PathPart('play') :Args(0) {
    my ($self, $c) = @_;

    my $file = $c->stash->{voicemail};
    my $recording = $file->recording;
    my $data;

    try {
        $data= NGCP::Panel::Utils::Sounds::transcode_data(
            $recording, 'WAV', 'WAV');
    } catch ($error) {
        $c->flash(messages => [{type => 'error', text => 'Transcode of audio file failed!'}]);
        $c->log->info("Transcode failed: $error");
        $c->response->redirect($c->uri_for_action('/subscriber/details', [$c->req->captures->[0]]));
        return;
    }

    $c->response->header('Content-Disposition' => 'attachment; filename="'.$file->msgnum.'.wav"');
    $c->response->content_type('audio/x-wav');
    $c->response->body($data);
}

sub delete_voicemail :Chained('voicemail') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;

    try {
        $c->stash->{voicemail}->delete;
        $c->flash(messages => [{type => 'success', text => 'Successfully deleted voicemail'}]);
    } catch($e) {
        $c->log->error("failed to delete voicemail message: $e");
        $c->flash(messages => [{type => 'error', text => 'Failed to delete voicemail'}]);
    }

    $c->response->redirect($c->uri_for_action('/subscriber/details', [$c->req->captures->[0]]));
}

sub registered :Chained('master') :PathPart('registered') :CaptureArgs(1) {
    my ($self, $c, $reg_id) = @_;

    my $s = $c->stash->{subscriber}->provisioning_voip_subscriber;
    $c->stash->{registered} = $c->model('DB')->resultset('location')->find({
        id => $reg_id,
        username => $s->username,
        domain => $s->domain->domain,
    });
    unless($c->stash->{registered}) {
        $c->log->error("failed to find location id '$reg_id' for subscriber uuid " . $s->uuid);
        $c->flash(messages => [{type => 'error', text => 'Failed to find registered device'}]);
        $c->response->redirect($c->uri_for_action('/subscriber/details', [$c->req->captures->[0]]));
        return;
    }
}

sub delete_registered :Chained('registered') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;
    my $ret;

    try {
        my $s = $c->stash->{subscriber}->provisioning_voip_subscriber;
        my $aor = $s->username . '@' . $s->domain->domain;
        my $contact = $c->stash->{registered}->contact;
        my $dispatcher = NGCP::Panel::Utils::XMLDispatcher->new;
        $ret = $dispatcher->dispatch("proxy-ng", 1, 1, <<EOF );
<?xml version="1.0" ?>
<methodCall>
<methodName>ul.rm_contact</methodName>
<params>
<param><value><string>location</string></value></param>
<param><value><string>$aor</string></value></param>
<param><value><string>$contact</string></value></param>
</params>
</methodCall>
EOF
    } catch($e) {
        $c->log->error("failed to delete registered device: $e");
        $c->flash(messages => [{type => 'error', text => 'Failed to delete registered device'}]);
    }

# TODO: how to determine if $ret was ok?
#    unless($ret) {
#        $c->log->error("failed to delete registered device: $e");
#        $c->flash(messages => [{type => 'error', text => 'Failed to delete registered device'}]);
#    }

    $c->flash(messages => [{type => 'success', text => 'Successfully deleted registered device'}]);
    $c->response->redirect($c->uri_for_action('/subscriber/details', [$c->req->captures->[0]]));
}

sub create_registered :Chained('master') :PathPart('registered/create') :Args(0) {
    my ($self, $c) = @_;

    my $s = $c->stash->{subscriber}->provisioning_voip_subscriber;
    my $posted = ($c->request->method eq 'POST');
    my $ret;

    my $form = NGCP::Panel::Form::Subscriber::Location->new;
    $form->process(
        posted => $posted,
        params => $c->request->params
    );
    if($posted && $form->validated) {
        try {
            my $s = $c->stash->{subscriber}->provisioning_voip_subscriber;
            my $aor = $s->username . '@' . $s->domain->domain;
            my $contact = $form->field('contact')->value;
            my $path = $c->config->{sip}->{path} || '<sip:127.0.0.1:5060;lr>';
            my $dispatcher = NGCP::Panel::Utils::XMLDispatcher->new;
            $ret = $dispatcher->dispatch("proxy-ng", 1, 1, <<EOF );
<?xml version="1.0" ?>
<methodCall>
<methodName>ul.add</methodName>
<params>
<param><value><string>location</string></value></param>
<param><value><string>$aor</string></value></param>
<param><value><string>$contact</string></value></param>
<param><value><int>0</int></value></param>
<param><value><double>1.00</double></value></param>
<param><value><string><![CDATA[$path]]></string></value></param>
<param><value><int>0</int></value></param>
<param><value><int>0</int></value></param>
<param><value><int>4294967295</int></value></param>
</params>
</methodCall>
EOF
            # TODO: error check
            $c->flash(messages => [{type => 'success', text => 'Successfully added registered device'}]);
            $c->response->redirect($c->uri_for_action('/subscriber/details', [$c->req->captures->[0]]));
            return;
        } catch($e) {
            $c->log->error("failed to add registered device: $e");
            $c->flash(messages => [{type => 'error', text => 'Failed to add registered device'}]);
            $c->response->redirect($c->uri_for_action('/subscriber/details', [$c->req->captures->[0]]));
            return;
        }
    }

    $c->stash(
        edit_flag => 1,
        description => 'Registered Device',
        form => $form,
        close_target => $c->uri_for_action('/subscriber/details', [$c->req->captures->[0]]),
    );
}

sub create_trusted :Chained('base') :PathPart('preferences/trusted/create') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $trusted_rs = $c->stash->{subscriber}->provisioning_voip_subscriber->voip_trusted_sources;
    my $params = {};
    
    my $form = NGCP::Panel::Form::Subscriber::TrustedSource->new;
    $form->process(
        posted => $posted,
        params => $posted ? $c->req->params : {}
    );

    if($posted && $form->validated) {
        try {
            $trusted_rs->create({
                uuid => $c->stash->{subscriber}->uuid,
                src_ip => $form->field('src_ip')->value,
                protocol => $form->field('protocol')->value,
                from_pattern => $form->field('from_pattern') ? $form->field('from_pattern')->value : undef,
            });
            $c->flash(messages => [{type => 'success', text => 'Successfully created trusted source'}]);
            $c->response->redirect($c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
            return;
        } catch($e) {
            $c->log->error("creating trusted source failed: $e");
            $c->flash(messages => [{type => 'error', text => 'Failed to create trusted source'}]);
            $c->response->redirect($c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
            return;
        }
    }

    $c->stash(
        template => 'subscriber/preferences.tt',
        edit_cf_flag => 1,
        cf_description => 'Trusted Source',
        cf_form => $form,
        close_target => $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]),
    );
}

sub trusted_base :Chained('base') :PathPart('preferences/trusted') :CaptureArgs(1) {
    my ($self, $c, $trusted_id) = @_;

    $c->stash->{trusted} = $c->stash->{subscriber}->provisioning_voip_subscriber
                            ->voip_trusted_sources->find($trusted_id);

    unless($c->stash->{trusted}) {
        $c->log->error("trusted source id '$trusted_id' not found for subscriber uuid ".$c->stash->{subscriber}->uuid);
        $c->flash(messages => [{type => 'error', text => 'Trusted source entry not found'}]);
        $c->response->redirect($c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
        return;
    }
}

sub edit_trusted :Chained('trusted_base') :PathPart('edit') {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $trusted = $c->stash->{trusted};
    my $params = {};
    
    if(!$posted && $trusted) {
        $params = { 
            'src_ip' => $trusted->src_ip,
            'protocol' => $trusted->protocol,
            'from_pattern' => $trusted->from_pattern,
        };
    }

    my $form = NGCP::Panel::Form::Subscriber::TrustedSource->new;
    $form->process(
        params => $posted ? $c->req->params : $params
    );

    if($posted && $form->validated) {
        try {
            $trusted->update({
                src_ip => $form->field('src_ip')->value,
                protocol => $form->field('protocol')->value,
                from_pattern => $form->field('from_pattern') ? $form->field('from_pattern')->value : undef,
            });

            $c->flash(messages => [{type => 'success', text => 'Successfully updated trusted source'}]);
            $c->response->redirect($c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
            return;
        } catch($e) {
            $c->log->error("updating trusted source failed: $e");
            $c->flash(messages => [{type => 'error', text => 'Failed to update trusted source'}]);
            $c->response->redirect($c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
            return;
        }
    }

    $c->stash(
        template => 'subscriber/preferences.tt',
        edit_cf_flag => 1,
        cf_description => 'Trusted Source',
        cf_form => $form,
        close_target => $c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]),
    );
}

sub delete_trusted :Chained('trusted_base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;

    try {
        $c->stash->{trusted}->delete;
        $c->flash(messages => [{type => 'success', text => 'Successfully deleted trusted source'}]);
    } catch($e) {
        $c->log->error("failed to delete trusted source: $e");
        $c->flash(messages => [{type => 'error', text => 'Failed to delete trusted source'}]);
    }

    $c->response->redirect($c->uri_for_action('/subscriber/preferences', [$c->req->captures->[0]]));
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
