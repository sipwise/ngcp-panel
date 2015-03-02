package NGCP::Panel::Controller::Peering;
use Sipwise::Base;


BEGIN { extends 'Catalyst::Controller'; }

use NGCP::Panel::Form::PeeringGroup;
use NGCP::Panel::Form::PeeringRule;
use NGCP::Panel::Form::PeeringServer;
use NGCP::Panel::Utils::DialogicImg;
use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::Navigation;
use NGCP::Panel::Utils::Preferences;
use NGCP::Panel::Utils::XMLDispatcher;

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
    ]);
    
    $c->stash(template => 'peering/list.tt');
}

sub root :Chained('group_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub ajax :Chained('group_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    
    my $resultset = $c->model('DB')->resultset('voip_peer_groups');
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{peering_group_dt_columns});
    
    $c->detach( $c->view("JSON") );
}

sub base :Chained('group_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $group_id) = @_;

    unless($group_id && $group_id->is_integer) {
        NGCP::Panel::Utils::Message->error(
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
        NGCP::Panel::Utils::Message->error(
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
        { name => 'weight', search => 1, title => $c->loc('Weight') },
        { name => 'via_route', search => 1, title => $c->loc('Via Route Set') },
        { name => 'enabled', search => 1, title => $c->loc('Enabled') },
    ]);
    $c->stash->{rules_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'callee_prefix', search => 1, title => $c->loc('Callee Prefix') },
        { name => 'callee_pattern', search => 1, title => $c->loc('Callee Pattern') },
        { name => 'caller_pattern', search => 1, title => $c->loc('Caller Pattern') },
        { name => 'description', search => 1, title => $c->loc('Description') },
        { name => 'enabled', search => 1, title => $c->loc('Enabled') },
    ]);


    $c->stash(group => {$res->get_columns});
    $c->stash->{group}->{'contract.id'} = $res->peering_contract_id;
    $c->stash(group_result => $res);
}

sub edit :Chained('base') :PathPart('edit') {
    my ($self, $c) = @_;
    
    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::PeeringGroup->new;
    my $params = { $c->stash->{group_result}->get_inflated_columns };
    $params->{contract}{id} = delete $params->{peering_contract_id};
    $params = $params->merge($c->session->{created_objects});
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c, form => $form,
        fields => {'contract.create' => $c->uri_for('/contract/peering/create')},
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            $c->stash->{group_result}->update($form->custom_get_values);
            $self->_sip_lcr_reload($c);
            delete $c->session->{created_objects}->{contract};
            NGCP::Panel::Utils::Message->info(
                c    => $c,
                desc => $c->loc('Peering group successfully updated'),
            );
        } catch ($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update peering group'),
            );
        };
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for)
    }

    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
}

sub delete :Chained('base') :PathPart('delete') {
    my ($self, $c) = @_;
    
    try {
        # manually delete hosts in group to let triggers hit in
        foreach my $p ($c->stash->{group_result}->voip_peer_hosts->all) {
            $p->voip_peer_preferences->delete_all;
            $p->delete;
        }
        $c->stash->{group_result}->delete;
        $self->_sip_lcr_reload($c);
        NGCP::Panel::Utils::Message->info(
            c    => $c,
            data => { $c->stash->{group_result}->get_inflated_columns },
            desc => $c->loc('Peering Group successfully deleted'),
        );
    } catch ($e) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => $e,
            desc  => $c->loc('Failed to delete peering group'),
        );
    };
    $c->response->redirect($c->uri_for());
}

sub create :Chained('group_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::PeeringGroup->new;
    my $params = {};
    $params = $params->merge($c->session->{created_objects});
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c, form => $form,
        fields => {'contract.create' => $c->uri_for('/contract/peering/create')},
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        my $formdata = $form->custom_get_values;
        try {
            $c->model('DB')->resultset('voip_peer_groups')->create(
                $formdata );
            $self->_sip_lcr_reload($c);
            delete $c->session->{created_objects}->{contract};
            NGCP::Panel::Utils::Message->info(
                c    => $c,
                desc => $c->loc('Peering group successfully created'),
            );
        } catch ($e) {
            NGCP::Panel::Utils::Message->error(
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
}

sub servers_list :Chained('base') :PathPart('servers') :CaptureArgs(0) {
    my ($self, $c) = @_;
    $c->stash(template => 'peering/servers_rules.tt');
}

sub servers_root :Chained('servers_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub servers_ajax :Chained('servers_list') :PathPart('s_ajax') :Args(0) {
    my ($self, $c) = @_;
    
    my $resultset = $c->stash->{group_result}->voip_peer_hosts;
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{server_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub servers_create :Chained('servers_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;
    
    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::PeeringServer->new(ctx => $c);
    $form->process(
        posted => $posted,
        params => $c->request->params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri
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
            };
            my $server = $c->stash->{group_result}->voip_peer_hosts->create($dbvalues);
            if ($form->values->{dialogic_mode} ne 'none') {
                my $api = NGCP::Panel::Utils::DialogicImg->new(
                    server      => 'https://' . $form->values->{dialogic_config_ip},
                );
                my @configured_out_codecs =  map { s/^\s+|\s+$//gr } split(',', $form->values->{dialogic_out_codecs});
                $api->login( 'dialogic', 'Dial0gic' );
                my $resp = $api->obtain_lock();
                die "Couldn't connect to dialogic"
                    unless $resp->code == 200;
                if ($form->values->{dialogic_mode} eq 'sipsip') {
                    my $config = {
                        ip_sip => $form->values->{ip},
                        ip_rtp => $form->values->{dialogic_rtp_ip},
                        ip_client => $c->config->{dialogic}{own_ip},
                        out_codecs => \@configured_out_codecs,
                        ip_config => $form->values->{dialogic_config_ip}, # just for the config hash
                        dialogic_mode => $form->values->{dialogic_mode},
                        };

                    $resp = $api->create_all_sipsip($config, 1);
                    my $config_hash = $api->hash_config($config);
                    # $server->voip_peer_hosts_dialogic->create({
                    #     configuration_hash => $config_hash,
                    #     mode => 'sipsip',
                    #     ip_rtp => $config->{ip_rtp},
                    #     out_codecs => $config->{out_codecs},
                    #     ip_config => $config->{ip_config},
                    # });
                }
            }
            $self->_sip_lcr_reload($c);
            NGCP::Panel::Utils::Message->info(
                c    => $c,
                desc => $c->loc('Peering server successfully created'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
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
        servers_form => $form
    );
}

sub servers_base :Chained('servers_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $server_id) = @_;

    unless($server_id && $server_id->is_integer) {
        NGCP::Panel::Utils::Message->error(
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
        NGCP::Panel::Utils::Message->error(
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
}

sub servers_edit :Chained('servers_base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;
    
    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::PeeringServer->new(ctx => $c);
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $c->stash->{server},
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri
    );
    if($posted && $form->validated) {
        try {
            $c->stash->{server_result}->update($form->values);
            $self->_sip_lcr_reload($c);
            NGCP::Panel::Utils::Message->info(
                c    => $c,
                desc => $c->loc('Peering server successfully updated'),
            );
        } catch ($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update peering server'),
            );
        };
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action('/peering/servers_root', [$c->req->captures->[0]]));
    }

    $c->stash(
        close_target => $c->uri_for_action('/peering/servers_root', [$c->req->captures->[0]]),
        servers_form => $form,
        servers_edit_flag => 1
    );
}

sub servers_delete :Chained('servers_base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;
    
    try {
        $c->stash->{server_result}->delete;
        $self->_sip_lcr_reload($c);
        NGCP::Panel::Utils::Message->info(
            c    => $c,
            data => { $c->stash->{server_result}->get_inflated_columns },
            desc => $c->loc('Peering server successfully deleted'),
        );
    } catch ($e) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => $e,
            desc  => $c->loc('Failed to delete peering server'),
        );
    };
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action('/peering/servers_root', [$c->req->captures->[0]]));
}

sub servers_preferences_list :Chained('servers_base') :PathPart('preferences') :CaptureArgs(0) {
    my ($self, $c) = @_;
      
    my $x_pref_values = $c->model('DB')
        ->resultset('voip_preferences')
        ->search({
                'peer_host.id' => $c->stash->{server}->{id}
            },{
                prefetch => {'voip_peer_preferences' => 'peer_host'},
            });
            
    my %pref_values;
    foreach my $value($x_pref_values->all) {
    
        $pref_values{$value->attribute} = [
            map {$_->value} $value->voip_peer_preferences->all
        ];
    }

    my $rewrite_rule_sets_rs = $c->model('DB')
        ->resultset('voip_rewrite_rule_sets');
    $c->stash(rwr_sets_rs => $rewrite_rule_sets_rs,
              rwr_sets    => [$rewrite_rule_sets_rs->all]);

    NGCP::Panel::Utils::Preferences::load_preference_list( c => $c,
        pref_values => \%pref_values,
        peer_pref => 1,
    );
    
    $c->stash(template => 'peering/preferences.tt');
}

sub servers_preferences_root :Chained('servers_preferences_list') :PathPart('') :Args(0) {

}

sub servers_preferences_base :Chained('servers_preferences_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $pref_id) = @_;
    
    $c->stash->{preference_meta} = $c->model('DB')
        ->resultset('voip_preferences')
        ->search({
            -or => ['voip_preferences_enums.peer_pref' => 1,
                'voip_preferences_enums.peer_pref' => undef]
        },{
            prefetch => 'voip_preferences_enums',
        })
        ->find({id => $pref_id});

    $c->stash->{preference} = $c->model('DB')
        ->resultset('voip_peer_preferences')
        ->search({
            attribute_id => $pref_id,
            'peer_host.id' => $c->stash->{server}->{id},
        },{
            prefetch => 'peer_host',
        });
    my @values = $c->stash->{preference}->get_column("value")->all;
    $c->stash->{preference_values} = \@values;
}

sub servers_preferences_edit :Chained('servers_preferences_base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;
   
    $c->stash(edit_preference => 1);

    my @enums = $c->stash->{preference_meta}
        ->voip_preferences_enums
        ->all;
    
    my $pref_rs = $c->stash->{server_result}->voip_peer_preferences;

    NGCP::Panel::Utils::Preferences::create_preference_form( c => $c,
        pref_rs => $pref_rs,
        enums   => \@enums,
        base_uri => $c->uri_for_action('/peering/servers_preferences_root', [@{ $c->req->captures }[0,1]]),
        edit_uri => $c->uri_for_action('/peering/servers_preferences_edit', $c->req->captures),
    );
}

sub rules_list :Chained('base') :PathPart('rules') :CaptureArgs(0) {
    my ($self, $c) = @_;

    my $sr_list_uri = $c->uri_for_action(
        '/peering/servers_root', [$c->req->captures->[0]]);
    $c->stash(sr_list_uri => $sr_list_uri);
    $c->stash(template => 'peering/servers_rules.tt');
}

sub rules_ajax :Chained('rules_list') :PathPart('r_ajax') :Args(0) {
    my ($self, $c) = @_;
    
    my $resultset = $c->stash->{group_result}->voip_peer_rules;
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{rules_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub rules_create :Chained('rules_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;
   
    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::PeeringRule->new;
    $form->process(
        posted => $posted,
        params => $c->request->params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri
    );
    if($posted && $form->validated) {
        try {
            $form->values->{callee_prefix} //= '';
            $c->stash->{group_result}->voip_peer_rules->create($form->values);
            $self->_sip_lcr_reload($c);
            NGCP::Panel::Utils::Message->info(
                c => $c,
                desc  => $c->loc('Peering rule successfully created'),
            );
        } catch ($e) {
            NGCP::Panel::Utils::Message->error(
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
}

sub rules_base :Chained('rules_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $rule_id) = @_;

    unless($rule_id && $rule_id->is_integer) {
        NGCP::Panel::Utils::Message->error(
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
        NGCP::Panel::Utils::Message->error(
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
}

sub rules_edit :Chained('rules_base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;
    
    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::PeeringRule->new;
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $c->stash->{rule},
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri
    );
    if($posted && $form->validated) {
        try {
            $form->values->{callee_prefix} //= '';
            $c->stash->{rule_result}->update($form->values);
            $self->_sip_lcr_reload($c);
            NGCP::Panel::Utils::Message->info(
                c    => $c,
                desc => $c->loc('Peering rule successfully changed'),
            );
        } catch ($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update peering rule'),
            );
        };
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action('/peering/servers_root', [$c->req->captures->[0]]));
    }

    $c->stash(
        close_target => $c->uri_for_action('/peering/servers_root', [$c->req->captures->[0]]),
        rules_form => $form,
        rules_edit_flag => 1,
    );
}

sub rules_delete :Chained('rules_base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;
    
    try {
        $c->stash->{rule_result}->delete;
        $self->_sip_lcr_reload($c);
        NGCP::Panel::Utils::Message->info(
            c    => $c,
            data => { $c->stash->{rule_result}->get_inflated_columns },
            desc => $c->loc('Peering rule successfully deleted'),
        );
    } catch ($e) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => $e,
            desc  => $c->loc('Failed to delete peering rule'),
        );
    };
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for_action('/peering/servers_root', [$c->req->captures->[0]]));
}

sub _sip_lcr_reload {
    my ($self, $c) = @_;
    my $dispatcher = NGCP::Panel::Utils::XMLDispatcher->new;
    $dispatcher->dispatch($c, "proxy-ng", 1, 1, <<EOF );
<?xml version="1.0" ?>
<methodCall>
<methodName>lcr.reload</methodName>
<params/>
</methodCall>
EOF

    return 1;
}

__PACKAGE__->meta->make_immutable;

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

=head2 _sip_lcr_reload

This is ported from ossbss.

Reloads lcr cache of sip proxies.

=head1 AUTHOR

Gerhard Jungwirth C<< <gjungwirth@sipwise.com> >>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
