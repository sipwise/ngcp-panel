package NGCP::Panel::Controller::Domain;
use Sipwise::Base;


BEGIN { extends 'Catalyst::Controller'; }

use NGCP::Panel::Form::Domain::Reseller;
use NGCP::Panel::Form::Domain::ResellerPbx;
use NGCP::Panel::Form::Domain::Admin;
use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::Navigation;
use NGCP::Panel::Utils::Prosody;
use NGCP::Panel::Utils::Preferences;

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub dom_list :Chained('/') :PathPart('domain') :CaptureArgs(0) {
    my ($self, $c) = @_;

    my $dispatch_to = '_dom_resultset_' . $c->user->auth_realm;
    my $dom_rs = $self->$dispatch_to($c);

    $c->stash->{domain_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => '#' },
        { name => 'domain_resellers.reseller.name', search => 1, title => 'Reseller' },
        { name => 'domain', search => 1, title => 'Domain' },
    ]);

    $c->stash(dom_rs   => $dom_rs,
              template => 'domain/list.tt');
}

sub _dom_resultset_admin {
    my ($self, $c) = @_;
    return $c->model('DB')->resultset('domains');
}

sub _dom_resultset_reseller {
    my ($self, $c) = @_;

    return $c->model('DB')->resultset('admins')->find(
            { id => $c->user->id, } )
        ->reseller
        ->domain_resellers
        ->search_related('domain');
}

sub root :Chained('dom_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub create :Chained('dom_list') :PathPart('create') :Args() {
    my ($self, $c, $reseller_id, $type) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form; my $pbx;
    if($type && $type eq 'pbx') {
        unless($reseller_id && $reseller_id->is_int) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => 'invalid reseller id for creating pbx domain',
                desc => 'Invalid reseller id detected.',
            );
            NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/domain'));
        }
        if(!$c->user->is_superuser && $reseller_id != $c->user->reseller_id) {
            $c->detach('/denied_page');
        }
        $c->stash->{reseller} = $c->model('DB')->resultset('resellers')->find($reseller_id);
        unless($c->stash->{reseller}) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => "reseller with id $reseller_id not found when creating pbx domain",
                desc => 'Reseller not found.',
            );
            NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/domain'));
        }
        $form = NGCP::Panel::Form::Domain::ResellerPbx->new(ctx => $c);
        $pbx = 1;
    } elsif($c->user->is_superuser) {
        $form = NGCP::Panel::Form::Domain::Admin->new;
    } else {
        $form = NGCP::Panel::Form::Domain::Reseller->new;
    }
    my $params = {};
    $params = $params->merge($c->session->{created_objects});
    delete $params->{domain} if exists($params->{domain}{id});
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params,
    );
    if($posted && $form->validated) {
        try {
            $c->model('DB')->schema->txn_do( sub {
                my $prov_dom = $c->model('DB')->resultset('voip_domains')
                    ->create({domain => $form->value->{domain}});
                my $new_dom = $c->stash->{dom_rs}
                    ->create({domain => $form->value->{domain}});
                unless($pbx) {
                    $reseller_id = $c->user->is_superuser ? 
                        $form->values->{reseller}{id} : $c->user->reseller_id;
                } elsif($form->values->{rwr_set}) {
                    my $rwr_set = $c->model('DB')->resultset('voip_rewrite_rule_sets')
                        ->find($form->values->{rwr_set});
                    NGCP::Panel::Utils::Preferences::set_rewrite_preferences(
                        c => $c,
                        rwrs_result => $rwr_set,
                        pref_rs => $prov_dom->voip_dom_preferences,
                    ) if($rwr_set);
                }

                $new_dom->create_related('domain_resellers', {
                    reseller_id => $reseller_id
                    });
                NGCP::Panel::Utils::Prosody::activate_domain($c, $form->value->{domain})
                    unless($c->config->{features}->{debug});
                delete $c->session->{created_objects}->{reseller};
                $c->session->{created_objects}->{domain} = { id => $new_dom->id };
            });
        } catch ($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => "Failed to create domain.",
            );
            NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/domain'));
        }

        $self->_sip_domain_reload;
        $c->flash(messages => [{type => 'success', text => 'Domain successfully created'}]);
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/domain'));
    }

    $c->stash(
        close_target => $c->uri_for,
        create_flag => 1,
        form => $form
    );
}

sub base :Chained('/domain/dom_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $domain_id) = @_;

    unless($domain_id && $domain_id->is_integer) {
        $c->flash(messages => [{type => 'error', text => 'Invalid domain id detected'}]);
        $c->response->redirect($c->uri_for());
        $c->detach;
        return;
    }

    my $res = $c->stash->{dom_rs}->find($domain_id);
    unless(defined($res)) {
        $c->flash(messages => [{type => 'error', text => 'Domain does not exist'}]);
        $c->response->redirect($c->uri_for());
        $c->detach;
        return;
    }

    $c->stash(provisioning_domain_result => $c->model('DB')
        ->resultset('voip_domains')
        ->find({domain => $res->domain}) );

    $c->stash(domain        => {$res->get_columns},
              domain_result => $res);
}

sub edit :Chained('base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::Domain::Reseller->new;
    $form->process(
        posted => 1,
        params => $posted ? $c->request->params : $c->stash->{domain},
        action => $c->uri_for($c->stash->{domain}->{id}, 'edit'),
    );
    if($posted && $form->validated) {

        try {
            $c->model('DB')->schema->txn_do( sub {
                $c->stash->{'domain_result'}->update({
                    domain => $form->value->{domain},
                });
                $c->stash->{'provisioning_domain_result'}->update({
                    domain => $form->value->{domain},
                });
            });
        } catch ($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => "Failed to update domain.",
            );
            $c->response->redirect($c->uri_for());
            return;
        }

        $self->_sip_domain_reload;

        $c->flash(messages => [{type => 'success', text => 'Domain successfully updated'}]);
        $c->response->redirect($c->uri_for());
        return;
    }

    $c->stash(close_target => $c->uri_for());
    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
}

sub delete :Chained('base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;

    my $domain = $c->stash->{'domain_result'}->domain;
    try {
        $c->model('DB')->schema->txn_do( sub {
            $c->stash->{'domain_result'}->delete;
            $c->stash->{'provisioning_domain_result'}->delete;
            NGCP::Panel::Utils::Prosody::deactivate_domain($c, $domain)
                unless($c->config->{features}->{debug});
        });
    } catch ($e) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => $e,
            desc  => "Failed to delete domain.",
        );
        $c->response->redirect($c->uri_for());
        return;
    }

    $self->_sip_domain_reload;

    $c->flash(messages => [{type => 'success', text => 'Domain successfully deleted!'}]);
    $c->response->redirect($c->uri_for());
}

sub ajax :Chained('dom_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;

    my $resultset = $c->stash->{dom_rs};
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{domain_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub ajax_filter_reseller :Chained('dom_list') :PathPart('ajax/filter_reseller') :Args(1) {
    my ($self, $c, $reseller_id) = @_;

    my $resultset = $c->stash->{dom_rs}->search({
        'domain_resellers.reseller_id' => $reseller_id,
    },{
        join => 'domain_resellers'
    });
    NGCP::Panel::Utils::Datatables::process($c, $resultset, $c->stash->{domain_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub preferences :Chained('base') :PathPart('preferences') :Args(0) {
    my ($self, $c) = @_;

    $self->load_preference_list($c);
    $c->stash(template => 'domain/preferences.tt');
}

sub preferences_base :Chained('base') :PathPart('preferences') :CaptureArgs(1) {
    my ($self, $c, $pref_id) = @_;

    $self->load_preference_list($c);

    $c->stash->{preference_meta} = $c->model('DB')
        ->resultset('voip_preferences')
        ->single({id => $pref_id});
    my $domain_name = $c->stash->{domain}->{domain};
    my $provisioning_domain_id = $c->stash->{provisioning_domain_result}->id;

    $c->stash->{preference} = $c->model('DB')
        ->resultset('voip_dom_preferences')
        ->search({
            attribute_id => $pref_id,
            domain_id => $provisioning_domain_id,
        });
    my @values = $c->stash->{preference}->get_column("value")->all;
    $c->stash->{preference_values} = \@values;
    $c->stash(template => 'domain/preferences.tt');
}

sub preferences_edit :Chained('preferences_base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;
   
    $c->stash(edit_preference => 1);
    
    my @enums = $c->stash->{preference_meta}
        ->voip_preferences_enums
        ->search({dom_pref => 1})
        ->all;

    my $pref_rs = $c->model('DB')
        ->resultset('voip_dom_preferences')
        ->search({
            domain_id => $c->stash->{provisioning_domain_result}->id,
        });

    NGCP::Panel::Utils::Preferences::create_preference_form( c => $c,
        pref_rs => $pref_rs,
        enums   => \@enums,
        base_uri => $c->uri_for_action('/domain/preferences', [$c->req->captures->[0]]),
        edit_uri => $c->uri_for_action('/domain/preferences_edit', $c->req->captures),
    );
}

sub load_preference_list :Private {
    my ($self, $c) = @_;
    
    my $dom_pref_values = $c->model('DB')
        ->resultset('voip_preferences')
        ->search({
                domain => $c->stash->{domain}->{domain}
            },{
                prefetch => {'voip_dom_preferences' => 'domain'},
            });
        
    my %pref_values;
    foreach my $value($dom_pref_values->all) {
    
        $pref_values{$value->attribute} = [
            map {$_->value} $value->voip_dom_preferences->all
        ];
    }

    my $correct_reseller_id = $c->stash->{domain_result}->domain_resellers->first->reseller_id;
    my $rewrite_rule_sets_rs = $c->model('DB')
        ->resultset('voip_rewrite_rule_sets')
        ->search_rs({ reseller_id => $correct_reseller_id, });
    $c->stash(rwr_sets_rs => $rewrite_rule_sets_rs,
              rwr_sets    => [$rewrite_rule_sets_rs->all]);

    my $ncos_levels_rs = $c->model('DB')
        ->resultset('ncos_levels')
        ->search_rs({ reseller_id => $correct_reseller_id, });
    $c->stash(ncos_levels_rs => $ncos_levels_rs,
              ncos_levels    => [$ncos_levels_rs->all]);

    my $sound_sets_rs = $c->model('DB')
        ->resultset('voip_sound_sets')
        ->search_rs({ reseller_id => $correct_reseller_id, contract_id => undef, });
    $c->stash(sound_sets_rs => $sound_sets_rs,
              sound_sets    => [$sound_sets_rs->all]);

    NGCP::Panel::Utils::Preferences::load_preference_list( c => $c,
        pref_values => \%pref_values,
        dom_pref => 1,
    );
}

sub _sip_domain_reload {
    my ($self) = @_;
    my $dispatcher = NGCP::Panel::Utils::XMLDispatcher->new;
    $dispatcher->dispatch("proxy-ng", 1, 1, <<EOF );
<?xml version="1.0" ?>
<methodCall>
<methodName>domain.reload</methodName>
<params/>
</methodCall>
EOF

    return 1;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

NGCP::Panel::Controller::Domain - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=head2 dom_list

basis for the domain controller

=head2 root

=head2 create

Provide a form to create new domains. Handle posted data and create domains.

=head2 search

obsolete

=head2 base

Fetch a domain by its id.

Data that is put on stash: domain, domain_result

=head2 edit

probably obsolete

=head2 delete

deletes a domain (defined in base)

=head2 ajax

Get domains and output them as JSON.

=head2 preferences

Show a table view of preferences.

=head2 preferences_base

Get details about one preference for further editing.

Data that is put on stash: preference_meta, preference, preference_values

=head2 preferences_edit

Use a form for editing one preference. Execute the changes that are posted.

Data that is put on stash: edit_preference, form

=head2 load_preference_list

Retrieves and processes a datastructure containing preference groups, preferences and their values, to be used in rendering the preference list.

Data that is put on stash: pref_groups

=head2 _sip_domain_reload

Ported from ossbss

reloads domain cache of sip proxies

=head1 AUTHOR

Andreas Granig,,,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
