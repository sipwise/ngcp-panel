package NGCP::Panel::Controller::Domain;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller'; }

use NGCP::Panel::Form::Domain;
use NGCP::Panel::Form::Preferences;

sub list :Chained('/') :PathPart('domain') :CaptureArgs(0) :Args(0) {
    my ($self, $c) = @_;

    $c->stash(has_edit => 0);
    $c->stash(template => 'domain/list.tt');
}

sub root :Chained('list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub create :Chained('list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $form = NGCP::Panel::Form::Domain->new;
    $form->process(
        posted => ($c->request->method eq 'POST'),
        params => $c->request->params,
        action => $c->uri_for('create'),
    );
    if($form->validated) {
        my $schema = $c->model('billing')->schema;
        $schema->provisioning($c->model('provisioning')->schema->connect);
        $schema->create_domain(
            {
                domain => $form->field('domain')->value,
            },
            1
        );
        $c->flash(messages => [{type => 'success', text => 'Domain successfully created!'}]);
        $c->response->redirect($c->uri_for());
        return;
    }

    $c->stash(close_target => $c->uri_for());
    $c->stash(create_flag => 1);
    $c->stash(form => $form);
}

sub search :Chained('list') :PathPart('search') Args(0) {
    my ($self, $c) = @_;

    $c->flash(messages => [{type => 'info', text => 'Domain search not implemented!'}]);
    $c->response->redirect($c->uri_for());
}

sub base :Chained('/domain/list') :PathPart('') :CaptureArgs(1) :Args(0) {
    my ($self, $c, $domain_id) = @_;

    unless($domain_id && $domain_id =~ /^\d+$/) {
        $c->flash(messages => [{type => 'error', text => 'Invalid domain id detected!'}]);
        $c->response->redirect($c->uri_for());
        return;
    }

    my $res = $c->model('billing')->resultset('domains')->find($domain_id);
    unless(defined($res)) {
        $c->flash(messages => [{type => 'error', text => 'Domain does not exist!'}]);
        $c->response->redirect($c->uri_for());
        return;
    }
    $c->stash(domain => {$res->get_columns});
    $c->stash(domain_result => $res);
}

sub edit :Chained('base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::Domain->new;
    $form->process(
        posted => 1,
        params => $posted ? $c->request->params : $c->stash->{domain},
        action => $c->uri_for($c->stash->{domain}->{id}, 'edit'),
    );
    if($posted && $form->validated) {
        
        $c->stash->{'domain_result'}->update({
              domain => $form->field('domain')->value,
          });

        $c->flash(messages => [{type => 'success', text => 'Domain successfully changed!'}]);
        $c->response->redirect($c->uri_for());
        return;
    }

    $c->stash(close_target => $c->uri_for());
    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
}

sub delete :Chained('base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;
    
    unless ( defined($c->stash->{'domain_result'}) ) {
        return;
    }

    $c->stash->{'domain_result'}->delete;
    
#    my $schema = $c->model('billing')->schema;
#    $schema->provisioning($c->model('provisioning')->schema->connect);
#    $schema->delete_domain({
#            domain => $c->stash->{domain}->{domain},
#            id     => $c->stash->{domain}->{id},
#        },
#        1,
#    );

    $c->flash(messages => [{type => 'success', text => 'Domain successfully deleted!'}]);
    $c->response->redirect($c->uri_for());
}

sub ajax :Chained('list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    
    my $resultset = $c->model('billing')->resultset('domains');
    
    $c->forward( "/ajax_process_resultset", [$resultset,
                 ["id", "domain"],
                 [0,1]]);
    
    $c->detach( $c->view("JSON") );
}

sub preferences :Chained('base') :PathPart('preferences') :Args(0) {
    my ($self, $c) = @_;
    
    $c->stash->{provisioning_domain_id} = $c->model('provisioning')
        ->resultset('voip_domains')
        ->single({domain => $c->stash->{domain}->{domain}})->id;

    $self->load_preference_list($c);
    $c->stash(template => 'domain/preferences.tt');
}

sub preferences_detail :Chained('base') :PathPart('preferences') :CaptureArgs(1) :Args(0) {
    my ($self, $c, $pref_id) = @_;

    $self->load_preference_list($c);

    $c->stash->{preference_meta} = $c->model('provisioning')
        ->resultset('voip_preferences')
        ->single({id => $pref_id});
    $c->stash->{provisioning_domain_id} = $c->model('provisioning')
        ->resultset('voip_domains')
        ->single({domain => $c->stash->{domain}->{domain}})->id;

    $c->stash->{preference} = $c->model('provisioning')
        ->resultset('voip_dom_preferences')
        ->search({attribute_id => $pref_id, domain_id => $c->stash->{provisioning_domain_id}});
    my @values = $c->stash->{preference}->get_column("value")->all;
    $c->stash->{preference_values} = \@values;
    $c->stash(template => 'domain/preferences.tt');
}

sub preferences_edit :Chained('preferences_detail') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;
   
    $c->stash(edit_preference => 1);

    my @enums = $c->stash->{preference_meta}
        ->voip_preferences_enums
        ->search({dom_pref => 1})
        ->all;

    my $form = NGCP::Panel::Form::Preferences->new({
        fields_data => [{
            meta => $c->stash->{preference_meta},
            enums => \@enums,
        }],
    });
    $form->create_structure([$c->stash->{preference_meta}->attribute]);

    my $posted = ($c->request->method eq 'POST');
    if($c->stash->{preference_meta}->max_occur == 1){
        $form->process(
            posted => 1,
            params => $posted ? $c->request->params : { $c->stash->{preference_meta}->attribute => $c->stash->{preference_values}->[0] },
            action => $c->uri_for($c->stash->{domain}->{id}, 'preferences', $c->stash->{preference_meta}->id, 'edit'),
        );
    } else {
        $form->process(
            posted => 1,
            params => $posted ? $c->request->params : {},
            action => $c->uri_for($c->stash->{domain}->{id}, 'preferences', $c->stash->{preference_meta}->id, 'edit'),
        );
    }
    if($posted && $form->validated) {
        my $preference_id = $c->stash->{preference}->first ? $c->stash->{preference}->first->id : undef;
        if ($c->stash->{preference_meta}->max_occur != 1) {
            $c->model('provisioning')
                ->resultset('voip_dom_preferences')
                ->create({
                    attribute_id => $c->stash->{preference_meta}->id,
                    domain_id => $c->stash->{provisioning_domain_id},
                    value => $form->field($c->stash->{preference_meta}->attribute)->value,
                });
        } else {
            my $rs = $c->model('provisioning')
                ->resultset('voip_dom_preferences')
                ->update_or_create({
                    id => $preference_id,
                    attribute_id => $c->stash->{preference_meta}->id,
                    domain_id => $c->stash->{provisioning_domain_id},
                    value => $form->field($c->stash->{preference_meta}->attribute)->value,
                  });
            $c->flash(messages => [{type => 'success', text => 'Preference '.$c->stash->{preference_meta}->attribute.' successfully updated.'}]);
            $c->response->redirect($c->uri_for($c->stash->{domain}->{id}, 'preferences'));
            return;
         }
    }
    
    my $delete_param = $c->request->params->{delete};
    my $deactivate_param = $c->request->params->{deactivate};
    my $activate_param = $c->request->params->{activate};
    my $param_id = $delete_param || $deactivate_param || $activate_param;
    # only one parameter is processed at a time (?)
    if($param_id) {
        my $rs = $c->model('provisioning')
            ->resultset('voip_dom_preferences')
            ->find($param_id);
        if($rs->attribute_id != $c->stash->{preference_meta}->id) {
            # Invalid param (dom_pref does not belong to current pref)
        } elsif($delete_param) {
            $rs->delete();
        } elsif ($deactivate_param) {
            $rs->update({value => "#".$rs->value});
        } elsif ($activate_param) {
            my $new_value = $rs->value;
            $new_value =~ s/^#//;
            $rs->update({value => $new_value});
        }
    }

    $c->stash(form => $form);
}

sub load_preference_list : Private {
    my ($self, $c) = @_;

    my @dom_pref_groups = $c->model('provisioning')
        ->resultset('voip_preference_groups')
        ->search({ 'voip_preferences.dom_pref' => 1, 'voip_preferences.internal' => 0,
            }, {
                prefetch => {'voip_preferences' => 'voip_preferences_enums'},
            })
        ->all;
    
    my $dom_pref_values = $c->model('provisioning')
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

    foreach my $group(@dom_pref_groups) {
        my @group_prefs = $group->voip_preferences->all;
        
        foreach my $pref(@group_prefs) {
            if($pref->data_type eq "enum") {
                $pref->{enums} = [];
                push @{ $pref->{enums} },
                    $pref->voip_preferences_enums->search({dom_pref => 1})->all;
            }
            my @values = @{
                exists $pref_values{$pref->attribute}
                    ? $pref_values{$pref->attribute}
                    : []
            };
            next unless(scalar @values);
            if($pref->max_occur != 1) {
                $pref->{value} = \@values;
            } else {
                $pref->{value} = $values[0];
            }
        }
        $group->{prefs} = \@group_prefs;
    }
    $c->stash(pref_groups => \@dom_pref_groups);
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

NGCP::Panel::Controller::Domain - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=head2 list

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

Data that is put on stash: provisioning_domain_id

=head2 preferences_detail

Get details about one preference for further editing.

Data that is put on stash: preference_meta, provisioning_domain_id, preference, preference_values

=head2 preferences_edit

Use a form for editing one preference. Execute the changes that are posted.

Data that is put on stash: edit_preference, form

=head2 load_preference_list

Retrieves and processes a datastructure containing preference groups, preferences and their values, to be used in rendering the preference list.

Data that is put on stash: pref_groups

=head1 AUTHOR

Andreas Granig,,,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
