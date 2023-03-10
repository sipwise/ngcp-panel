package NGCP::Panel::Controller::Peering;
use NGCP::Panel::Utils::Generic qw(:all);
use Sipwise::Base;

use parent 'Catalyst::Controller';

use NGCP::Panel::Form;

use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::Navigation;
use NGCP::Panel::Utils::Preferences;
use NGCP::Panel::Utils::Peering;

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub group_list :Chained('/') :PathPart('peering') :CaptureArgs(0) {
    my ( $self, $c ) = @_;

    $c->stash->{peering_group_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'contract.contact.email', search => 1, title => $c->loc('Contact Email') },
        { name => 'name', search => 1, title => $c->loc('Name') },
        { name => 'priority', search => 1, title => $c->loc('Priority') },
        { name => 'description', search => 1, title => $c->loc('Description') },
        { name => 'time_set.name', search => 1, title => $c->loc('Time Set') },
    ]);
    
    $c->stash(template => 'peering/list.tt');
    return;
}

sub root :Chained('group_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
    return;
}

sub ajax :Chained('group_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    
    my $resultset = $c->model('DB')->resultset('voip_peer_groups');
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{peering_group_dt_columns});
    
    $c->detach( $c->view("JSON") );
    return;
}

sub base :Chained('group_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $group_id) = @_;

    unless($group_id && is_int($group_id)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Invalid group id detected',
            desc  => $c->loc('Invalid group id detected'),
        );
        $c->response->redirect($c->uri_for());
        $c->detach;
        return;
    }

    my $res = $c->model('DB')->resultset('voip_peer_groups')->find($group_id);
    unless(defined($res)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Peering group does not exist',
            desc  => $c->loc('Peering group does not exist'),
        );
        $c->response->redirect($c->uri_for());
        $c->detach;
        return;
    }

    $c->stash->{server_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'name', search => 1, title => $c->loc('Name') },
        { name => 'ip', search => 1, title => $c->loc('IP Address') },
        { name => 'host', search => 1, title => $c->loc('Hostname') },
        { name => 'port', search => 1, title => $c->loc('Port') },
        { name => 'transport', search => 1, title => $c->loc('Protocol') },
        { name => 'weight', search => 0, title => $c->loc('Weight') },
        { name => 'via_route', search => 1, title => $c->loc('Via Route Set') },
        { name => 'probe', search => 0, title => $c->loc('Probe') },
        { name => 'enabled', search => 0, title => $c->loc('Enabled') },
    ]);
    $c->stash->{rules_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'callee_prefix', search => 1, title => $c->loc('Callee Prefix') },
        { name => 'callee_pattern', search => 1, title => $c->loc('Callee Pattern') },
        { name => 'caller_pattern', search => 1, title => $c->loc('Caller Pattern') },
        { name => 'description', search => 1, title => $c->loc('Description') },
        { name => 'enabled', search => 0, title => $c->loc('Enabled') },
        { name => 'stopper', search => 0, title => $c->loc('Stopper') },
    ]);
    $c->stash->{inbound_rules_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'priority', search => 0, title => $c->loc('Priority') },
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'field', search => 1, title => $c->loc('Field') },
        { name => 'pattern', search => 1, title => $c->loc('Pattern') },
        { name => 'reject_code', search => 1, title => $c->loc('Reject Code') },
        { name => 'reject_reason', search => 1, title => $c->loc('Reject Reason') },
        { name => 'enabled', search => 1, title => $c->loc('Enabled') },
    ]);


    $c->stash(group => {$res->get_columns});
    $c->stash->{group}->{'contract.id'} = $res->peering_contract_id;
    $c->stash(group_result => $res);
    return;
}

sub edit :Chained('base') :PathPart('edit') {
    my ($self, $c) = @_;
    
    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Peering::Group", $c);
    my $params = { $c->stash->{group_result}->get_inflated_columns };
    $params->{contract}{id} = delete $params->{peering_contract_id};
    $params->{time_set}{id} = delete $params->{time_set_id};
    $params = merge($params, $c->session->{created_objects});
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c, form => $form,
        fields => {
            'contract.create' => $c->uri_for('/contract/peering/create'),
            'time_set.create' => $c->uri_for('/timeset/create'),
        },
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            $c->stash->{group_result}->update($form->custom_get_values);
            NGCP::Panel::Utils::Peering::_sip_lcr_reload(c => $c);
            delete $c->session->{created_objects}->{contract};
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Peering group successfully updated'),
            );
        } catch ($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update peering group'),
            );
        };
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for);
    }

    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
    return;
}

sub delete_peering :Chained('base') :PathPart('delete') {
    my ($self, $c) = @_;
    
    try {
        # manually delete hosts in group to let triggers hit in
        foreach my $p ($c->stash->{group_result}->voip_peer_hosts->all) {
            if($p->probe) {
                NGCP::Panel::Utils::Peering::_sip_delete_probe(
                    c => $c,
                    ip => $p->ip,
                    port => $p->port,
                    transport => $p->transport,
                );
            }
            if ($p->enabled) {
                $c->stash->{server}->{name} = $p->name;
                $c->stash->{server}->{ip} = $p->ip;
                $c->stash->{server}->{id} = $p->id;
                $c->stash->{server_result} = $p;
                NGCP::Panel::Utils::Peering::_sip_delete_peer_registration(c => $c);
            }
            $p->voip_peer_preferences->delete_all;
            $p->delete;
        }
        $c->stash->{group_result}->delete;
        NGCP::Panel::Utils::Peering::_sip_lcr_reload(c => $c);
        NGCP::Panel::Utils::Message::info(
            c    => $c,
            data => { $c->stash->{group_result}->get_inflated_columns },
            desc => $c->loc('Peering Group successfully deleted'),
        );
    } catch ($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            desc  => $c->loc('Failed to delete peering group'),
        );
    };
    $c->response->redirect($c->uri_for());
    return;
}

sub create :Chained('group_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Peering::Group", $c);
    my $params = {};
    $params = merge($params, $c->session->{created_objects});
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c, form => $form,
        fields => {
            'contract.create' => $c->uri_for('/contract/peering/create'),
            'time_set.create' => $c->uri_for('/timeset/create'),
        },
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        my $formdata = $form->custom_get_values;
        try {
            $c->model('DB')->resultset('voip_peer_groups')->create(
                $formdata );
            NGCP::Panel::Utils::Peering::_sip_lcr_reload(c => $c);
            delete $c->session->{created_objects}->{contract};
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Peering group successfully created'),
            );
        } catch ($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create peering group'),
            );
        };
        $c->response->redirect($c->uri_for_action('/peering/root'));
        return;
    }

    $c->stash(close_target => $c->uri_for_action('/peering/root'));
    $c->stash(create_flag => 1);
    $c->stash(form => $form);
    return;
}

sub servers_list :Chained('base') :PathPart('servers') :CaptureArgs(0) {
    my ($self, $c) = @_;
    $c->stash(template => 'peering/servers_rules.tt');
    return;
}

sub servers_root :Chained('servers_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
    return;
}

sub servers_ajax :Chained('servers_list') :PathPart('s_ajax') :Args(0) {
    my ($self, $c) = @_;
    
    my $resultset = $c->stash->{group_result}->voip_peer_hosts;
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{server_dt_columns});
    $c->detach( $c->view("JSON") );
    return;
}

sub servers_create :Chained('servers_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;
    
    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Peering::Server", $c);
    $form->process(
        posted => $posted,
        params => $c->request->params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            my $dbvalues = {
                name => $form->values->{name},
                ip => $form->values->{ip},
                host => $form->values->{host},
                port => $form->values->{port},
                transport => $form->values->{transport},
                weight => $form->values->{weight},
                via_route => $form->values->{via_route},
                enabled => $form->values->{enabled},
                probe => $form->values->{probe},
            };
            my $server = $c->stash->{group_result}->voip_peer_hosts->create($dbvalues);
            NGCP::Panel::Utils::Peering::_sip_lcr_reload(c => $c);
            if($dbvalues->{probe}) {
                NGCP::Panel::Utils::Peering::_sip_dispatcher_reload(c => $c);
            }
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Peering server successfully created'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create peering server'),
            );
        };
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action('/peering/servers_root', [$c->req->captures->[0]]));
    }

    $c->stash(
        close_target => $c->uri_for_action('/peering/servers_root', [$c->req->captures->[0]]),
        servers_create_flag => 1,
        servers_form => $form,
    );
    return;
}

sub servers_base :Chained('servers_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $server_id) = @_;

    unless($server_id && is_int($server_id)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Invalid peering server id',
            desc  => $c->loc('Invalid peering server id'),
        );
        $c->response->redirect($c->stash->{sr_list_uri});
        $c->detach;
        return;
    }

    my $res = $c->stash->{group_result}->voip_peer_hosts->find($server_id);
    unless(defined($res)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Peering server does not exist',
            desc  => $c->loc('Peering server does not exist'),
        );
        $c->response->redirect($c->stash->{sr_list_uri});
        $c->detach;
        return;
    }
    $c->stash(server => {$res->get_columns});
    $c->stash(server_result => $res);
    return;
}

sub servers_edit :Chained('servers_base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;
    
    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Peering::Server", $c);
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $c->stash->{server},
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            my $enabled_before = $c->stash->{server_result}->enabled;
            my $probing_before = $c->stash->{server_result}->probe;

            if ($enabled_before && !$form->values->{enabled}) {
                NGCP::Panel::Utils::Peering::_sip_delete_peer_registration(c => $c);
            }

            $c->stash->{server_result}->update($form->values);

            if (!$enabled_before && $form->values->{enabled}) {
                NGCP::Panel::Utils::Peering::_sip_create_peer_registration(c => $c);
            }

            NGCP::Panel::Utils::Peering::_sip_lcr_reload(c => $c);

            if (($c->stash->{server_result}->probe && $enabled_before && !$c->stash->{server_result}->enabled) || ($probing_before && !$c->stash->{server_result}->probe)) {
                NGCP::Panel::Utils::Peering::_sip_delete_probe(
                    c => $c,
                    ip => $c->stash->{server_result}->ip,
                    port => $c->stash->{server_result}->port,
                    transport => $c->stash->{server_result}->transport,
                );
            }
            NGCP::Panel::Utils::Peering::_sip_dispatcher_reload(c => $c);
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Peering server successfully updated'),
            );
        } catch ($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update peering server'),
            );
        };
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action('/peering/servers_root', [$c->req->captures->[0]]));
    }

    $c->stash(
        servers_form => $form,
        servers_edit_flag => 1,
    );
    return;
}

sub servers_delete :Chained('servers_base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;

    try {
        my $probe = $c->stash->{server_result}->probe;
        my $enabled = $c->stash->{server_result}->enabled;
        if ($enabled) {
            NGCP::Panel::Utils::Peering::_sip_delete_peer_registration(c => $c);
        }

        $c->stash->{server_result}->delete;
        NGCP::Panel::Utils::Peering::_sip_lcr_reload(c => $c);
        if($probe) {
            NGCP::Panel::Utils::Peering::_sip_delete_probe(
                c => $c,
                ip => $c->stash->{server_result}->ip,
                port => $c->stash->{server_result}->port,
                transport => $c->stash->{server_result}->transport,
            );
            NGCP::Panel::Utils::Peering::_sip_dispatcher_reload(c => $c);
        }
        NGCP::Panel::Utils::Message::info(
            c    => $c,
            data => { $c->stash->{server_result}->get_inflated_columns },
            desc => $c->loc('Peering server successfully deleted'),
        );
    } catch ($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            desc  => $c->loc('Failed to delete peering server'),
        );
    };
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action('/peering/servers_root', [$c->req->captures->[0]]));
    return;
}

sub servers_preferences_list :Chained('servers_base') :PathPart('preferences') :CaptureArgs(0) {
    my ($self, $c) = @_;
      
    my $x_pref_values = $c->model('DB')
        ->resultset('voip_preferences')
        ->search({
                'peer_host.id' => $c->stash->{server}->{id},
            },{
                prefetch => {'voip_peer_preferences' => 'peer_host'},
            });
            
    my %pref_values;
    foreach my $value($x_pref_values->all) {
        if ($value->data_type eq "blob") {
            $pref_values{$value->attribute} = [
                map {$_->blob
                        ? $_->blob->content_type
                        : ''} $value->voip_peer_preferences->all
            ];
        } else {
            $pref_values{$value->attribute} = [
                map {$_->value} $value->voip_peer_preferences->all
            ];
        }
    }

    my $rewrite_rule_sets_rs = $c->model('DB')
        ->resultset('voip_rewrite_rule_sets');
    my $header_rule_sets_rs = $c->model('DB')
        ->resultset('voip_header_rule_sets')->search({
            subscriber_id => undef
        });
    $c->stash(rwr_sets_rs => $rewrite_rule_sets_rs,
              rwr_sets    => [$rewrite_rule_sets_rs->all],
              hdr_sets_rs => $header_rule_sets_rs,
              hdr_sets    => [$header_rule_sets_rs->all]);

    my $sound_sets_rs = $c->model('DB')
        ->resultset('voip_sound_sets')->search({
            contract_id => undef });
    $c->stash(sound_sets_rs => $sound_sets_rs,
              sound_sets    => [$sound_sets_rs->all]);

    NGCP::Panel::Utils::Preferences::load_preference_list( c => $c,
        pref_values => \%pref_values,
        peer_pref => 1,
    );

    $c->stash(template => 'peering/preferences.tt');
    return;
}

sub servers_preferences_root :Chained('servers_preferences_list') :PathPart('') :Args(0) {
    return;
}

sub servers_preferences_base :Chained('servers_preferences_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $pref_id) = @_;
    
    $c->stash->{preference_meta} = $c->model('DB')
        ->resultset('voip_preferences')
        ->search({
            -or => ['voip_preferences_enums.peer_pref' => 1,
                'voip_preferences_enums.peer_pref' => undef],
        },{
            prefetch => 'voip_preferences_enums',
        })
        ->find({id => $pref_id});

    my $blob_short_value_size = NGCP::Panel::Utils::Preferences::get_blob_short_value_size;
    $c->stash->{preference} = $c->model('DB')
        ->resultset('voip_peer_preferences')
        ->search({
            attribute_id => $pref_id,
            'peer_host.id' => $c->stash->{server}->{id},
        },{
            prefetch => 'peer_host',
            join => 'blob',
            '+select' => [ \"SUBSTRING(blob.value, 1, $blob_short_value_size)" ],
            '+as' => [ 'short_blob_value' ],
        });
    return;
}

sub servers_preferences_edit :Chained('servers_preferences_base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;
   
    $c->stash(edit_preference => 1);

    my @enums = $c->stash->{preference_meta}
        ->voip_preferences_enums
        ->all;
    
    my $pref_rs = $c->stash->{server_result}->voip_peer_preferences->search({
    }, {
        join => 'attribute',
    });

    my $old_authentication_prefs = {};
    if ($c->req->method eq "POST" && $c->stash->{preference_meta}->attribute =~ /^peer_auth_/) {
        foreach my $pref ($pref_rs->all) {
            my $attr = $pref->attribute->attribute;
            if ($attr =~ /^peer_auth_/) {
                $old_authentication_prefs->{$attr} = $pref->value;
            }
        }
    }

    NGCP::Panel::Utils::Preferences::create_preference_form( c => $c,
        pref_rs => $pref_rs,
        enums   => \@enums,
        base_uri => $c->uri_for_action('/peering/servers_preferences_root', [@{ $c->req->captures }[0,1]]),
        edit_uri => $c->uri_for_action('/peering/servers_preferences_edit', $c->req->captures),
        blob_rs  => $c->model('DB')->resultset('voip_peer_preferences_blob'),
    );

    if (keys %{ $old_authentication_prefs }) {
        my $new_authentication_prefs = {};
        if ($c->req->method eq "POST" && $c->stash->{preference_meta}->attribute =~ /^peer_auth_/) {
            foreach my $pref ($pref_rs->all) {
                my $attr = $pref->attribute->attribute;
                if ($attr =~ /^peer_auth_/) {
                    $new_authentication_prefs->{$attr} = $pref->value;
                }
            }

            unless ($c->stash->{server_result}->lcr_gw) {
                my $err = "Cannot set peer registration, this server is not enabled";
                NGCP::Panel::Utils::Message::error(
                    c     => $c,
                    log   => "Failed to set peer registration: $err",
                    desc  => $c->loc($err),
                );
                return;
            }

            my $prov_peer = {};
            my $type = 'peering';
            $prov_peer->{username} = $c->stash->{server}->{name};
            $prov_peer->{domain} = $c->stash->{server}->{ip};
            $prov_peer->{id} = $c->stash->{server_result}->lcr_gw->id;
            $prov_peer->{uuid} = 0;

            unless(compare($old_authentication_prefs, $new_authentication_prefs)) {
                try {
                    NGCP::Panel::Utils::Preferences::update_sems_peer_auth(
                        $c, $prov_peer, $type, $old_authentication_prefs, $new_authentication_prefs);
                } catch($e) {
                    NGCP::Panel::Utils::Message::error(
                        c     => $c,
                        log   => "Failed to set peer registration: $e",
                        desc  => $c->loc('Peer registration error'),
                    );
                }
            }
        }
    }

    return;
}

sub rules_list :Chained('base') :PathPart('rules') :CaptureArgs(0) {
    my ($self, $c) = @_;

    my $sr_list_uri = $c->uri_for_action(
        '/peering/servers_root', [$c->req->captures->[0]]);
    $c->stash(sr_list_uri => $sr_list_uri);
    $c->stash(template => 'peering/servers_rules.tt');
    return;
}

sub rules_ajax :Chained('rules_list') :PathPart('r_ajax') :Args(0) {
    my ($self, $c) = @_;
    
    my $resultset = $c->stash->{group_result}->voip_peer_rules;
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{rules_dt_columns});
    $c->detach( $c->view("JSON") );
    return;
}

sub rules_create :Chained('rules_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;
   
    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Peering::Rule", $c);
    $form->process(
        posted => $posted,
        params => $c->request->params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            $form->values->{callee_prefix} //= '';
            $form->values->{caller_pattern} //= '';
            $form->values->{callee_pattern} //= '';
            my $dup_item = $c->model('DB')->resultset('voip_peer_rules')->find({
                group_id => $c->stash->{group_result}->id,
                callee_pattern => $form->values->{callee_pattern},
                caller_pattern => $form->values->{caller_pattern},
                callee_prefix => $form->values->{callee_prefix},
            });
            die("peering rule already exists") if $dup_item;
            $c->stash->{group_result}->voip_peer_rules->create($form->values);
            NGCP::Panel::Utils::Peering::_sip_lcr_reload(c => $c);
            NGCP::Panel::Utils::Message::info(
                c => $c,
                desc  => $c->loc('Peering rule successfully created'),
            );
        } catch ($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create peering rule'),
            );
        };
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action('/peering/servers_root', [$c->req->captures->[0]]));
    }

    $c->stash(
        close_target => $c->uri_for_action('/peering/servers_root', [$c->req->captures->[0]]),
        rules_create_flag => 1,
        rules_form => $form,
    );
    return;
}

sub rules_base :Chained('rules_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $rule_id) = @_;

    unless($rule_id && is_int($rule_id)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Invalid peering rule id detected',
            desc  => $c->loc('Invalid peering rule id detected'),
        );
        $c->response->redirect($c->stash->{sr_list_uri});
        $c->detach;
        return;
    }

    my $res = $c->stash->{group_result}->voip_peer_rules->find($rule_id);
    unless(defined($res)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Peering Rule does not exist',
            desc  => $c->loc('Peering Rule does not exist'),
        );
        $c->response->redirect($c->stash->{sr_list_uri});
        $c->detach;
        return;
    }
    $c->stash(rule => {$res->get_columns});
    $c->stash(rule_result => $res);
    return;
}

sub rules_edit :Chained('rules_base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;
    
    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Peering::RuleEditAdmin", $c);
    $c->stash->{rule}{group}{id} = delete $c->stash->{rule}{group_id};
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $c->stash->{rule},
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            $form->values->{callee_prefix} //= '';
            $form->values->{caller_pattern} //= '';
            $form->values->{callee_pattern} //= '';
            $form->values->{group_id} = $form->values->{group}{id};
            my $dup_item = $c->model('DB')->resultset('voip_peer_rules')->find({
                group_id => $form->values->{group_id},
                callee_pattern => $form->values->{callee_pattern},
                caller_pattern => $form->values->{caller_pattern},
                callee_prefix => $form->values->{callee_prefix},
            });
            die("peering rule already exists") if ($dup_item && $dup_item->id != $c->stash->{rule_result}->id);
            $c->stash->{rule_result}->update($form->values);
            NGCP::Panel::Utils::Peering::_sip_lcr_reload(c => $c);
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Peering rule successfully changed'),
            );
        } catch ($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update peering rule'),
            );
        };
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action('/peering/servers_root', [$c->req->captures->[0]]));
    }

    $c->stash(
        rules_form => $form,
        rules_edit_flag => 1,
    );
    return;
}

sub rules_delete :Chained('rules_base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;
    
    try {
        $c->stash->{rule_result}->delete;
        NGCP::Panel::Utils::Peering::_sip_lcr_reload(c => $c);
        NGCP::Panel::Utils::Message::info(
            c    => $c,
            data => { $c->stash->{rule_result}->get_inflated_columns },
            desc => $c->loc('Peering rule successfully deleted'),
        );
    } catch ($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            desc  => $c->loc('Failed to delete peering rule'),
        );
    };
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action('/peering/servers_root', [$c->req->captures->[0]]));
    return;
}

sub inbound_rules_list :Chained('base') :PathPart('inboundrules') :CaptureArgs(0) {
    my ($self, $c) = @_;

    my $sr_list_uri = $c->uri_for_action(
        '/peering/servers_root', [$c->req->captures->[0]]);
    $c->stash(sr_list_uri => $sr_list_uri);
    $c->stash(template => 'peering/servers_rules.tt');
    return;
}

sub inbound_rules_ajax :Chained('inbound_rules_list') :PathPart('r_ajax') :Args(0) {
    my ($self, $c) = @_;
    
    my $resultset = $c->stash->{group_result}->voip_peer_inbound_rules->search(undef, {
        order_by => {'-asc' => 'priority'},
    });
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{inbound_rules_dt_columns});
    $c->detach( $c->view("JSON") );
    return;
}

sub inbound_rules_create :Chained('inbound_rules_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;
   
    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Peering::InboundRule", $c);
    $form->process(
        posted => $posted,
        params => $c->request->params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            my $last_priority = $c->stash->{group_result}->voip_peer_inbound_rules->get_column('priority')->max() || 49;
            $form->values->{priority} = $last_priority + 1;
            $c->stash->{group_result}->voip_peer_inbound_rules->create($form->values);
            $c->stash->{group_result}->update({has_inbound_rules => 1});
            NGCP::Panel::Utils::Message::info(
                c => $c,
                desc  => $c->loc('Inbound peering rule successfully created'),
            );
        } catch ($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create inbound peering rule'),
            );
        };
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action('/peering/servers_root', [$c->req->captures->[0]]));
    }

    $c->stash(
        close_target => $c->uri_for_action('/peering/servers_root', [$c->req->captures->[0]]),
        inbound_rules_create_flag => 1,
        inbound_rules_form => $form,
    );
    return;
}

sub inbound_rules_base :Chained('inbound_rules_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $rule_id) = @_;

    unless($rule_id && is_int($rule_id)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Invalid inbound peering rule id detected',
            desc  => $c->loc('Invalid inbound peering rule id detected'),
        );
        $c->response->redirect($c->stash->{sr_list_uri});
        $c->detach;
        return;
    }

    my $res = $c->stash->{group_result}->voip_peer_inbound_rules->find($rule_id);
    unless(defined($res)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Inbound Peering Rule does not exist',
            desc  => $c->loc('Inbound Peering Rule does not exist'),
        );
        $c->response->redirect($c->stash->{sr_list_uri});
        $c->detach;
        return;
    }
    $c->stash(inbound_rule => {$res->get_columns});
    $c->stash(inbound_rule_result => $res);
    return;
}

sub inbound_rules_edit :Chained('inbound_rules_base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;
    
    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Peering::InboundRuleEditAdmin", $c);
    $c->stash->{inbound_rule}{group}{id} = delete $c->stash->{inbound_rule}{group_id};
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $c->stash->{inbound_rule},
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );
    if ($posted && $form->validated) {
        try {
            $form->values->{group_id} = $form->values->{group}{id};
            $c->stash->{inbound_rule_result}->update($form->values);
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Inbound peering rule successfully changed'),
            );
        } catch ($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update inbound peering rule'),
            );
        };
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action('/peering/servers_root', [$c->req->captures->[0]]));
    }

    $c->stash(
        inbound_rules_form => $form,
        inbound_rules_edit_flag => 1,
    );
    return;
}

sub inbound_rules_delete :Chained('inbound_rules_base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;
    
    try {
        $c->stash->{inbound_rule_result}->delete;
        unless($c->stash->{group_result}->voip_peer_inbound_rules->count)
        {
            $c->stash->{group_result}->update({has_inbound_rules => 0});
        }
        NGCP::Panel::Utils::Message::info(
            c    => $c,
            data => { $c->stash->{inbound_rule_result}->get_inflated_columns },
            desc => $c->loc('Inbound peering rule successfully deleted'),
        );
    } catch ($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            desc  => $c->loc('Failed to delete inbound peering rule'),
        );
    };
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action('/peering/servers_root', [$c->req->captures->[0]]));
    return;
}

sub inbound_rules_up :Chained('inbound_rules_base') :PathPart('up') :Args(0) {
    my ($self, $c) = @_;
   
    my $elem = $c->stash->{inbound_rule_result};

    my $swap_elem = $c->stash->{group_result}->voip_peer_inbound_rules->search({
        priority => { '<' => $elem->priority },
    },{
        order_by => {'-desc' => 'priority'},
    })->first;
    try {
        if ($swap_elem) {
            my $tmp_priority = $swap_elem->priority;
            $swap_elem->priority($elem->priority);
            $elem->priority($tmp_priority);
            $swap_elem->update;
            $elem->update;
        } else {
            my $last_priority = $c->stash->{group_result}->voip_peer_inbound_rules->get_column('priority')->min() || 1;
            $elem->priority(int($last_priority) - 1);
            $elem->update;
        }
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            desc  => $c->loc('Failed to move inbound peering rule up.'),
        );
    }
    #to clear $c->stash->{close_target} that was set in the Navigation::check_redirect_chain from the back parameter
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action('/peering/servers_root', [$c->req->captures->[0]]));
    return;
}

sub inbound_rules_down :Chained('inbound_rules_base') :PathPart('down') :Args(0) {
    my ($self, $c) = @_;
   
    my $elem = $c->stash->{inbound_rule_result};

    my $swap_elem = $c->stash->{group_result}->voip_peer_inbound_rules->search({
        priority => { '>' => $elem->priority },
    },{
        order_by => {'-asc' => 'priority'},
    })->first;
    try {
        if ($swap_elem) {
            my $tmp_priority = $swap_elem->priority;
            $swap_elem->priority($elem->priority);
            $elem->priority($tmp_priority);
            $swap_elem->update;
            $elem->update;
        } else {
            my $last_priority = $c->stash->{group_result}->voip_peer_inbound_rules->get_column('priority')->max() || 49;
            $elem->priority(int($last_priority) + 1);
            $elem->update;
        }
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            desc  => $c->loc('Failed to move inbound peering rule down.'),
        );
    }
    #to clear $c->stash->{close_target} that was set in the Navigation::check_redirect_chain from the back parameter
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action('/peering/servers_root', [$c->req->captures->[0]]));
    return;
}



1;

__END__

=head1 NAME

NGCP::Panel::Controller::Peering - manage peering groups, servers, rules

=head1 DESCRIPTION

Create/Edit/Delete of peering groups.

Create/Edit/Delete of peering servers and peering rules within peering groups.

Management of peer_preferences within peering servers.

=head1 METHODS

=head2 group_list

basis for peering groups.

=head2 root

Display peering groups through F<peering/list.tt> template.

=head2 ajax

Get provisioning.voip_peer_groups from the database and output them as JSON.
The format is meant for parsing with datatables.

=head2 base

Fetch a provisioning.voip_peer_groups from the database by its id.
Add the field "contract.id" for easier parsing into the form (in L</edit>).

=head2 edit

Show a modal to edit a peering group.

=head2 delete

Delete a peering group.

=head2 create

Show a modal to create a new peering group.

=head2 servers_list

Basis for peering servers. Chains from L</base>.

=head2 servers_root

Display peering servers and peering groups through
F<peering/servers_rules.tt> template. Uses datatables.

=head2 servers_ajax

Get provisioning.voip_peer_hosts from the database and output them as JSON.
The format is meant for parsing with datatables.
Only returns data from the current peering group.

=head2 servers_create

Show a modal to create a new peering server.

=head2 servers_base

Fetch a provisioning.voip_peer_hosts from the database by its id.
Only searches data that belongs to the current peering group.

=head2 servers_edit

Show a modal to edit a peering server.

=head2 servers_delete

Delete a peering server.

=head2 servers_preferences_list

Basis to show preferences for a given peering host/sever.

=head2 servers_preferences_root

Shows the preferences.

=head2 servers_preferences_base

Load preference, preference_meta and preference_values for a captured
id to stash. Will be used by L</servers_preferences_edit>.

=head2 servers_preferences_edit

Show a modal to edit one preference. Mainly uses
NGCP::Panel::Utils::Preferences::create_preference_form.

=head2 rules_list

Basis for peering rules. Chains from L</base>.

=head2 rules_ajax

Get provisioning.voip_peer_rules from the database and output them as JSON.
The format is meant for parsing with datatables.
Only returns data from the current peering group.

=head2 rules_create

Show a modal to create a new peering rule.

=head2 rules_base

Fetch a provisioning.voip_peer_rules from the database by its id.
Only searches data that belongs to the current peering group.

=head2 rules_edit

Show a modal to edit a peering rule.

=head2 rules_delete

Delete a peering rule.

=head1 AUTHOR

Gerhard Jungwirth C<< <gjungwirth@sipwise.com> >>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
