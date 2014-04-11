package NGCP::Panel::Controller::SubscriberProfile;
use Sipwise::Base;

BEGIN { extends 'Catalyst::Controller'; }

use NGCP::Panel::Form::SubscriberProfile::Admin;
use NGCP::Panel::Form::SubscriberProfile::Reseller;
use NGCP::Panel::Form::SubscriberProfile::Clone;
use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::Navigation;

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub profile_list :Chained('/') :PathPart('subscriberprofile') :CaptureArgs(0) {
    my ( $self, $c ) = @_;

    $c->stash->{profiles_rs} = $c->model('DB')->resultset('voip_subscriber_profiles');
    if($c->user->roles eq "admin") {
    } else {
        $c->stash->{profiles_rs} = $c->stash->{profiles_rs}->search({
            reseller_id => $c->user->reseller_id
        });
    }
    $c->stash->{profile_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'reseller.name', search => 1, title => $c->loc('Reseller') },
        { name => 'name', search => 1, title => $c->loc('Name') },
        { name => 'description', search => 1, title => $c->loc('Description') },
    ]);
    
    $c->stash(template => 'subprofile/list.tt');
}

sub root :Chained('profile_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub ajax :Chained('profile_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    my $rs = $c->stash->{profiles_rs};
    NGCP::Panel::Utils::Datatables::process($c, $rs, $c->stash->{profile_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub base :Chained('profile_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $profile_id) = @_;

    unless($profile_id && $profile_id->is_integer) {
        NGCP::Panel::Utils::Message->error(
            c     => $c,
            log   => 'Invalid subscriber profile id detected',
            desc  => $c->loc('Invalid subscriber profile id detected'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/rewrite'));
    }

    my $res = $c->stash->{profiles_rs}->find($profile_id);
    unless(defined($res)) {
        NGCP::Panel::Utils::Message->error(
            c     => $c,
            log   => 'Subscriber profile does not exist',
            desc  => $c->loc('Subscriber profile does not exist'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/subscriberprofile'));
    }
    $c->stash(profile_result => $res);
}

sub create :Chained('profile_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $params = {};
    $params = $params->merge($c->session->{created_objects});
    my $form;
    if($c->user->roles eq "admin") {
        $form = NGCP::Panel::Form::SubscriberProfile::Admin->new(ctx => $c);
        $form->create_structure($form->field_names);
    } else {
        $form = NGCP::Panel::Form::SubscriberProfile::Reseller->new(ctx => $c);
        $form->create_structure($form->field_names);
    }
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item   => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {
            'reseller.create' => $c->uri_for('/reseller/create'),
        },
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                my $reseller_id;
                if($c->user->roles eq "admin") {
                    $reseller_id = $form->values->{reseller}{id};
                } else {
                    $reseller_id = $c->user->reseller_id;
                }
                delete $form->values->{reseller};
                my $name = delete $form->values->{name};
                my $desc = delete $form->values->{description};
                my $profile = $c->stash->{profiles_rs}->create({
                    reseller_id => $reseller_id,
                    name => $name,
                    description => $desc,
                });
                
                # TODO: save profile_attributes here too


                delete $c->session->{created_objects}->{reseller};
            });
            $c->flash(messages => [{type => 'success', text => $c->loc('Subscriber profile successfully created')}]);
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create subscriber profile.'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/subscriberprofile'));
    }

    $c->stash(form => $form);
    $c->stash(create_flag => 1);
}

sub edit :Chained('base') :PathPart('edit') {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $params = { $c->stash->{profile_result}->get_inflated_columns };
    $params->{reseller}{id} = delete $params->{reseller_id};
    $params = $params->merge($c->session->{created_objects});
    my $form;
    if($c->user->roles eq "admin") {
        $form = NGCP::Panel::Form::SubscriberProfile::Admin->new(ctx => $c);
        $form->create_structure($form->field_names);
    } else {
        $form = NGCP::Panel::Form::SubscriberProfile::Reseller->new(ctx => $c);
        $form->create_structure($form->field_names);
    }
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item   => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {
            'reseller.create' => $c->uri_for('/reseller/create'),
        },
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            if($c->user->is_superuser) {
                $form->values->{reseller_id} = $form->values->{reseller}{id};
                delete $form->values->{reseller};
            }
            $c->stash->{profile_result}->update($form->values);
            delete $c->session->{created_objects}->{reseller};
            $c->flash(messages => [{type => 'success', text => $c->loc('Subscriber profile successfully updated')}]);
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update subscriber profile.'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/subscriberprofile'));
    }

    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
}

sub delete :Chained('base') :PathPart('delete') {
    my ($self, $c) = @_;
    
    try {
        $c->stash->{profile_result}->delete;
        $c->flash(messages => [{type => 'success', text => $c->loc('Subscriber profile successfully deleted')}]);
    } catch($e) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => $e,
            desc  => $c->loc('Failed to delete subscriber profile.'),
        );
    }
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/subscriberprofile'));
}

sub clone :Chained('base') :PathPart('clone') {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $params = { $c->stash->{profile_result}->get_inflated_columns };
    $params = $params->merge($c->session->{created_objects});
    my $form = NGCP::Panel::Form::SubscriberProfile::Clone->new;
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item   => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                my $new_profile = $c->stash->{profiles_rs}->create({
                    %{ $form->values },
                    reseller_id => $c->stash->{profile_result}->reseller_id,
                });

                my @old_attributes = $c->stash->{profile_result}->profile_attributes->all;
                for my $attr (@old_attributes) {
                    $new_profile->profile_attributes->create({
                        attribute_id => $attr->id,
                    });
                }
            });

            $c->flash(messages => [{type => 'success', text => $c->loc('Subscriber profile successfully cloned')}]);
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to clone subscriber profile.'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/subscriberprofile'));
    }

    $c->stash(form => $form);
    $c->stash(create_flag => 1);
    $c->stash(clone_flag => 1);
}


=pod
sub rules_list :Chained('set_base') :PathPart('rules') :CaptureArgs(0) {
    my ( $self, $c ) = @_;
    
    my $rules_rs = $c->stash->{profile_result}->voip_rewrite_rules;
    $c->stash(rules_rs => $rules_rs);
    $c->stash(rules_uri => $c->uri_for_action("/rewrite/rules_root", [$c->req->captures->[0]]));

    $c->stash(template => 'rewrite/rules_list.tt');
}

sub rules_root :Chained('rules_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
    
    my $rules_rs    = $c->stash->{rules_rs};
    my $param_move  = $c->req->params->{move};
    my $param_where = $c->req->params->{where};
    
    my $elem = $rules_rs->find($param_move)
        if ($param_move && $param_move->is_integer && $param_where);
    if($elem) {
        my $use_next = ($param_where eq "down") ? 1 : 0;
        my $swap_elem = $rules_rs->search({
            field => $elem->field,
            direction => $elem->direction,
            priority => { ($use_next ? '>' : '<') => $elem->priority },
        },{
            order_by => {($use_next ? '-asc' : '-desc') => 'priority'}
        })->first;
        try {
            if ($swap_elem) {
                my $tmp_priority = $swap_elem->priority;
                $swap_elem->priority($elem->priority);
                $elem->priority($tmp_priority);
                $swap_elem->update;
                $elem->update;
            } elsif($use_next) {
                my $last_priority = $c->stash->{rules_rs}->get_column('priority')->max() || 49;
                $elem->priority(int($last_priority) + 1);
                $elem->update;
            } else {
                my $last_priority = $c->stash->{rules_rs}->get_column('priority')->min() || 1;
                $elem->priority(int($last_priority) - 1);
                $elem->update;
            }
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to move rewrite rule.'),
            );
        }
    }
    
    my @caller_in = $rules_rs->search({
        field => 'caller',
        direction => 'in',
    },{
        order_by => { -asc => 'priority' },
    })->all;
    
    my @callee_in = $rules_rs->search({
        field => 'callee',
        direction => 'in',
    },{
        order_by => { -asc => 'priority' },
    })->all;
    
    my @caller_out = $rules_rs->search({
        field => 'caller',
        direction => 'out',
    },{
        order_by => { -asc => 'priority' },
    })->all;
    
    my @callee_out = $rules_rs->search({
        field => 'callee',
        direction => 'out',
    },{
        order_by => { -asc => 'priority' },
    })->all;
    
    for my $row (@caller_in, @callee_in, @caller_out, @callee_out) {
        my $mp = $row->match_pattern;
        my $rp = $row->replace_pattern;
        $mp =~ s/\$avp\(s\:(\w+)\)/\${$1}/g;
        $rp =~ s/\$avp\(s\:(\w+)\)/\${$1}/g;
        $row->match_pattern($mp);
        $row->replace_pattern($rp);
    }
    
    $c->stash(rules => {
        caller_in  => \@caller_in,
        callee_in  => \@callee_in,
        caller_out => \@caller_out,
        callee_out => \@callee_out,
    });
    return;
}

sub rules_base :Chained('rules_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $rule_id) = @_;

    unless($rule_id && $rule_id->is_integer) {
        NGCP::Panel::Utils::Message->error(
            c     => $c,
            log   => 'Invalid rewrite rule id detected',
            desc  => $c->loc('Invalid rewrite rule id detected'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{rules_uri});
    }

    my $res = $c->stash->{rules_rs}->find($rule_id);
    unless(defined($res)) {
        NGCP::Panel::Utils::Message->error(
            c     => $c,
            log   => 'Rewrite rule does not exist',
            desc  => $c->loc('Rewrite rule does not exist'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{rules_uri});
    }
    $c->stash(rule_result => $res);
}

sub rules_edit :Chained('rules_base') :PathPart('edit') {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::RewriteRule::Rule->new;
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item   => $c->stash->{rule_result},
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            $c->stash->{rule_result}->update($form->values);
            $self->_sip_dialplan_reload();
            $c->flash(messages => [{type => 'success', text => $c->loc('Rewrite rule successfully updated')}]);
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update rewrite rule.'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{rules_uri});
    }

    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
}

sub rules_delete :Chained('rules_base') :PathPart('delete') {
    my ($self, $c) = @_;
    
    try {
        $c->stash->{rule_result}->delete;
        $self->_sip_dialplan_reload();
        $c->flash(messages => [{type => 'success', text => $c->loc('Rewrite rule successfully deleted') }]);
    } catch($e) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => $e,
            desc  => $c->loc('Failed to delete rewrite rule.'),
        );
    };
    NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{rules_uri});
}

sub rules_create :Chained('rules_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::RewriteRule::Rule->new;
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
            my $last_priority = $c->stash->{rules_rs}->get_column('priority')->max() || 49;
            $form->values->{priority} = int($last_priority) + 1;
            $c->stash->{rules_rs}->create($form->values);
            $self->_sip_dialplan_reload();
            $c->flash(messages => [{type => 'success', text => $c->loc('Rewrite rule successfully created') }]);
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create rewrite rule.'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{rules_uri});
    }

    $c->stash(form => $form);
    $c->stash(create_flag => 1);
}

sub _sip_dialplan_reload {
    my ($self) = @_;
    my $dispatcher = NGCP::Panel::Utils::XMLDispatcher->new;
    $dispatcher->dispatch("proxy-ng", 1, 1, <<EOF );
<?xml version="1.0" ?>
<methodCall>
<methodName>dialplan.reload</methodName>
<params/>
</methodCall>
EOF

    return 1;
}

=cut

__PACKAGE__->meta->make_immutable;

1;

=head1 NAME

NGCP::Panel::Controller::SubscriberProfile - Manage Subscriber Profiles

=head1 DESCRIPTION

Show/Edit/Create/Delete Rewrite Rule Sets.

Show/Edit/Create/Delete Rewrite Rules within Rewrite Rule Sets.

=head1 METHODS

=head2 set_list

Basis for provisioning.voip_rewrite_rule_sets.

=head2 set_root

Display rewrite rule sets through F<rewrite/set_list.tt> template.

=head2 set_ajax

Get provisioning.voip_rewrite_rule_sets from the database and
output them as JSON.
The format is meant for parsing with datatables.

=head2 set_base

Fetch a provisioning.voip_rewrite_rule_set from the database by its id.

=head2 set_edit

Show a modal to edit a rewrite rule set determined by L</set_base>.
The form used is L<NGCP::Panel::Form::RewriteRuleSet>.

=head2 set_delete

Delete a rewrite rule set determined by L</set_base>.

=head2 set_clone

Deep copy a rewrite rule set determined by L</set_base>. The user can enter
a new name and description. The reseller is not configurable, but set by the
original rewrite rule set. The rewrite rules of the original rwrs are then
cloned and assigned to the new rwrs.

=head2 set_create

Show a modal to create a new rewrite rule set using the form
L<NGCP::Panel::Form::RewriteRuleSet>.

=head2 rules_list

Basis for provisioning.voip_rewrite_rules. Chained from L</set_base> and
therefore handles only rules for a certain rewrite rule set.

=head2 rules_root

Display rewrite rule sets through F<rewrite/rules_list.tt> template.
The rules are stashed to rules hashref which contains the keys
"caller_in", "callee_in", "caller_out", "callee_out".

It swaps priority of two elements if "move" and "where" GET params are set.

It modifies match_pattern and replace_pattern field to a certain output format
using regex.

=head2 rules_base

Fetch a rewrite rule from the database by its id. Will only find rules under
the current rule_set.

=head2 rules_edit

Show a modal to edit a rewrite rule determined by L</rules_base>.
The form used is L<NGCP::Panel::Form::RewriteRule>.

=head2 rules_delete

Delete a rewrite rule determined by L</rules_base>.

=head2 rules_create

Show a modal to create a new rewrite rule using the form
L<NGCP::Panel::Form::RewriteRule>.

=head2 _sip_dialplan_reload

This is ported from ossbss.

Reloads dialplan cache of sip proxies.

=head1 AUTHOR

Gerhard Jungwirth C<< <gjungwirth@sipwise.com> >>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
