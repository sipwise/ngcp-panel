package NGCP::Panel::Controller::Header;
use NGCP::Panel::Utils::Generic qw(:all);
use Sipwise::Base;

use parent 'Catalyst::Controller';

use NGCP::Panel::Form;

use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::Rewrite;
use NGCP::Panel::Utils::Navigation;

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub set_list :Chained('/') :PathPart('header') :CaptureArgs(0) {
    my ( $self, $c ) = @_;

    $c->stash->{sets_rs} = $c->model('DB')->resultset('voip_header_rule_sets');
    unless($c->user->roles eq "admin") {
        $c->stash->{sets_rs} = $c->stash->{sets_rs}->search({
            reseller_id => $c->user->reseller_id
        });
    }
    $c->stash->{set_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'reseller.name', search => 1, title => $c->loc('Reseller') },
        { name => 'name', search => 1, title => $c->loc('Name') },
        { name => 'description', search => 1, title => $c->loc('Description') },
    ]);

    $c->stash(template => 'header/set_list.tt');
}

sub set_root :Chained('set_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub set_ajax :Chained('set_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    my $rs = $c->stash->{sets_rs};
    NGCP::Panel::Utils::Datatables::process($c, $rs, $c->stash->{set_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub set_base :Chained('set_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $set_id) = @_;

    unless($set_id && is_int($set_id)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Invalid header rule set id detected',
            desc  => $c->loc('Invalid header rule set id detected'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/header'));
    }

    my $res = $c->stash->{sets_rs}->find($set_id);
    unless(defined($res)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Header rule set does not exist',
            desc  => $c->loc('Header rule set does not exist'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/header'));
    }
    $c->stash(set_result => $res);
}

sub set_edit :Chained('set_base') :PathPart('edit') {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $params = { $c->stash->{set_result}->get_inflated_columns };
    $params->{reseller}{id} = delete $params->{reseller_id};
    $params = merge($params, $c->session->{created_objects});
    my $form;
    if($c->user->roles eq "admin") {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Header::AdminRuleSet", $c);
    } else {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Header::ResellerRuleSet", $c);
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
            if($c->user->roles eq "admin") {
                $form->values->{reseller_id} = $form->values->{reseller}{id};
                delete $form->values->{reseller};
            }
            $c->stash->{set_result}->update($form->values);
            delete $c->session->{created_objects}->{reseller};
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Header rule set successfully updated'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update header rule set'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/header'));
    }

    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
}

sub set_delete :Chained('set_base') :PathPart('delete') {
    my ($self, $c) = @_;

    try {
        $c->stash->{set_result}->delete;
        NGCP::Panel::Utils::Message::info(
            c    => $c,
            data => { $c->stash->{set_result}->get_inflated_columns },
            desc => $c->loc('Header rule set successfully deleted'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            desc  => $c->loc('Failed to delete header rule set'),
        );
    }
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/header'));
}

sub set_clone :Chained('set_base') :PathPart('clone') {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $params = { $c->stash->{set_result}->get_inflated_columns };
    $params = merge($params, $c->session->{created_objects});
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Header::CloneRuleSet", $c);
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
                my $new_set = $c->stash->{sets_rs}->create({
                    %{ $form->values }, ## no critic (ProhibitCommaSeparatedStatements)
                    reseller_id => $c->stash->{set_result}->reseller_id,
                });
                my @old_rules = $c->stash->{set_result}->voip_header_rules->all;
                for my $rule (@old_rules) {
                    $new_set->voip_rewrite_rules->create({
                        match_pattern => $rule->match_pattern,
                        replace_pattern => $rule->replace_pattern,
                        description => $rule->description,
                        direction => $rule->direction,
                        field => $rule->field,
                        priority => $rule->priority,
                        enabled => $rule->enabled,
                    });
                }
            });
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Header rule set successfully cloned'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to clone header rule set.'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/header'));
    }

    $c->stash(form => $form);
    $c->stash(create_flag => 1);
    $c->stash(clone_flag => 1);
}

sub set_create :Chained('set_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $params = {};
    $params = merge($params, $c->session->{created_objects});
    my $form;
    if($c->user->roles eq "admin") {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Header::AdminRuleSet", $c);
    } else {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Header::ResellerRuleSet", $c);
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
            if($c->user->roles eq "admin") {
                $form->values->{reseller_id} = $form->values->{reseller}{id};
                delete $form->values->{reseller};
            } else {
                $form->values->{reseller_id} = $c->user->reseller_id;
            }
            $c->stash->{sets_rs}->create($form->values);
            delete $c->session->{created_objects}->{reseller};
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Header rule set successfully created'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create header rule set'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/header'));
    }

    $c->stash(form => $form);
    $c->stash(create_flag => 1);
}

sub rules_list :Chained('set_base') :PathPart('rules') :CaptureArgs(0) {
    my ( $self, $c ) = @_;

    my $rules_rs = $c->stash->{set_result}->voip_header_rules({
    },{
        order_by => { -asc => 'priority' },
    });
    $c->stash(rules_rs => $rules_rs);
    $c->stash(rules_uri => $c->uri_for_action("/header/rules_root", [$c->req->captures->[0]]));

    $c->stash(template => 'header/rules_list.tt');
    return;
}

sub rules_root :Chained('rules_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;

    my $rules_rs    = $c->stash->{rules_rs};
    my $param_move  = $c->req->params->{move};
    my $param_where = $c->req->params->{where};

    if ($param_move && is_int($param_move) && $param_where) {
        my $elem = $rules_rs->find($param_move);
        my $use_next = ($param_where eq "down") ? 1 : 0;
        my $swap_elem = $rules_rs->search({
            priority => { ($use_next ? '>' : '<') => $elem->priority },
        },{
            order_by => {($use_next ? '-asc' : '-desc') => 'priority'},
        })->first;
        try {
            if ($swap_elem) {
                my $tmp_priority = $swap_elem->priority;
                $swap_elem->priority($elem->priority);
                $elem->priority($tmp_priority);
                $swap_elem->update;
                $elem->update;
            } elsif ($use_next) {
                my $last_priority = $c->stash->{rules_rs}->get_column('priority')->max() || 99;
                $elem->priority(int($last_priority) + 1);
                $elem->update;
            } else {
                my $last_priority = $c->stash->{rules_rs}->get_column('priority')->min() || 1;
                $elem->priority(int($last_priority) - 1);
                $elem->update;
            }
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to move header rule.'),
            );
        }
    }

    $c->stash(rules => [ $rules_rs->all ]);
    return;
}

sub rules_base :Chained('rules_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $rule_id) = @_;

    unless($rule_id && is_int($rule_id)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Invalid header rule id detected',
            desc  => $c->loc('Invalid header rule id detected'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{rules_uri});
    }

    my $res = $c->stash->{rules_rs}->find($rule_id);
    unless(defined($res)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Header rule does not exist',
            desc  => $c->loc('Header rule does not exist'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{rules_uri});
    }
    $c->stash(rule_result => $res);
    return;
}

sub rules_edit :Chained('rules_base') :PathPart('edit') {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Header::Rule", $c);
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
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Header rule successfully updated'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update header rule'),
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
        NGCP::Panel::Utils::Message::info(
            c    => $c,
            data => { $c->stash->{rule_result}->get_inflated_columns },
            desc => $c->loc('Header rule successfully deleted'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            desc  => $c->loc('Failed to delete header rule'),
        );
    };
    NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{rules_uri});
}

sub rules_create :Chained('rules_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Header::Rule", $c);
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
            my $last_priority = $c->stash->{rules_rs}->get_column('priority')->max() || 99;
            $form->values->{priority} = int($last_priority) + 1;
            $c->stash->{rules_rs}->create($form->values);
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Header rule successfully created'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create a header rule'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{rules_uri});
    }

    $c->stash(form => $form);
    $c->stash(create_flag => 1);
}

sub conditions_list :Chained('rules_base') :PathPart('conditions') :CaptureArgs(0) {
    my ( $self, $c ) = @_;

    my $conditions_rs = $c->stash->{rule_result}->conditions;
    $c->stash(conditions_rs => $conditions_rs);

    $c->stash(conditions_uri => $c->uri_for_action("/header/conditions_root", $c->req->captures));

    $c->stash(template => 'header/conditions_list.tt');
    return;
}

sub conditions_root :Chained('conditions_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;

    my $conditions_rs = $c->stash->{conditions_rs};

    my @conditions = ();

    foreach my $condition ($conditions_rs->all) {
        my $row = { $condition->get_inflated_columns };
        @{$row->{values}} = map { $_->value } $condition->values->all;
        push @conditions, $row;
        if ($row->{rwr_set_id}) {
                my $rwr_set = { $condition->rwr_set->get_inflated_columns };
                $row->{rwr_set} = $rwr_set->{name};
                my $dp_id = $row->{rwr_dp_id} // 0;
                ($row->{rwr_dp}) =
                    grep { $_ =~ /_dpid/ && $rwr_set->{$_} eq $dp_id }
                        keys %{$rwr_set};
        }
    }

    $c->stash(conditions => \@conditions);
    return;
}

sub conditions_base :Chained('conditions_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $condition_id) = @_;

    $c->stash(conditions_uri => $c->uri_for_action("/header/conditions_root",
        [$c->stash->{set_result}->id, $c->stash->{rule_result}->id])
    );

    unless ($condition_id && is_int($condition_id)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Invalid header rule condition id detected',
            desc  => $c->loc('Invalid header rule condition id detected'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{conditions_uri});
    }

    my $res = $c->stash->{conditions_rs}->find($condition_id);
    unless (defined($res)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Header rule condition does not exist',
            desc  => $c->loc('Header rule condition does not exist'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{conditions_uri});
    }
    $c->stash(condition_result => $res);

    return;
}

sub conditions_edit :Chained('conditions_base') :PathPart('edit') {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Header::Condition", $c);
    my $condition = $c->stash->{condition_result};
    my $params = {};

    unless ($posted) {
        $params = { $condition->get_inflated_columns };
        @{$params->{values}} =
            map { { $_->get_inflated_columns } } $condition->values->all;
        if ($params->{rwr_set_id}) {
                my $rwr_set = { $condition->rwr_set->get_inflated_columns };
                $params->{rwr_set} = $rwr_set->{id};
                my $dp_id = $params->{rwr_dp_id} // 0;
                ($params->{rwr_dp}) =
                    grep { $_ =~ /_dpid/ && $rwr_set->{$_} eq $dp_id }
                        keys %{$rwr_set};
        }
    }

    $form->process(params => $posted ? $c->req->params : $params);
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            my $guard = $c->model('DB')->txn_scope_guard;
            {
                my $data = $form->values;
                my $values = delete $data->{values};
                map { $_->{group_id} = $data->{value_group_id} } @{$values};

                if ($data->{rwr_set}) {
                    $data->{rwr_set_id} = delete $data->{rwr_set};
                    my $rwr_rs = $c->model('DB')
                                ->resultset('voip_rewrite_rule_sets')
                                ->search({ id => $data->{rwr_set_id} });
                    if ($rwr_rs->count) {
                        my $rwr_set = { $rwr_rs->first->get_inflated_columns };
                        $data->{rwr_dp_id} = $rwr_set->{$data->{rwr_dp}} // undef;
                    } else {
                        $data->{rwr_set_id} = undef;
                        $data->{rwr_dp_id} = undef;
                    }
                } else {
                    $data->{rwr_set_id} = undef;
                    $data->{rwr_dp_id} = undef;
                }
                delete $data->{rwr_set};
                delete $data->{rwr_dp};

                $condition->update($data);
                map { $_->delete } $condition->values->all;
                $condition->values->populate($values);
            }
            $guard->commit;
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Header rule condition successfully updated'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update header rule condition'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{conditions_uri});
    }

    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
}

sub conditions_delete :Chained('conditions_base') :PathPart('delete') {
    my ($self, $c) = @_;

    try {
        $c->stash->{condition_result}->delete;
        NGCP::Panel::Utils::Message::info(
            c    => $c,
            data => { $c->stash->{condition_result}->get_inflated_columns },
            desc => $c->loc('Header rule condition successfully deleted'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            desc  => $c->loc('Failed to delete header rule condition'),
        );
    };
    NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{conditions_uri});
}

sub conditions_create :Chained('conditions_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Header::Condition", $c);
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
            my $guard = $c->model('DB')->txn_scope_guard;
            {
                my $data = $form->values;
                $data->{rule_id} = $c->stash->{rule_result}->id;
                delete $data->{value_group_id};
                my $values = delete $data->{values} // [];

                if ($data->{rwr_set}) {
                    $data->{rwr_set_id} = delete $data->{rwr_set};
                    my $rwr_rs = $c->model('DB')
                                ->resultset('voip_rewrite_rule_sets')
                                ->search({ id => $data->{rwr_set_id} });
                    if ($rwr_rs->count) {
                        my $rwr_set = { $rwr_rs->first->get_inflated_columns };
                        $data->{rwr_dp_id} = $rwr_set->{$data->{rwr_dp}} // undef;
                    } else {
                        $data->{rwr_set_id} = undef;
                        $data->{rwr_dp_id} = undef;
                    }
                } else {
                    $data->{rwr_set_id} = undef;
                    $data->{rwr_dp_id} = undef;
                }
                delete $data->{rwr_set};
                delete $data->{rwr_dp};

                my $rs = $c->stash->{conditions_rs};
                my $new_condition = $rs->create($data);

                my $group = $c->model('DB')
                            ->resultset('voip_header_rule_condition_value_groups')
                            ->create({ condition_id => $new_condition->id });

                map { $_->{group_id} = $group->id } @{$values};
                $c->model('DB')
                    ->resultset('voip_header_rule_condition_values')
                    ->populate($values);

                $new_condition->update({ value_group_id => $group->id });
            }
            $guard->commit;
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Header rule condition successfully created'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create a header rule condition'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{conditions_uri});
    }

    $c->stash(form => $form);
    $c->stash(create_flag => 1);
}

sub actions_list :Chained('rules_base') :PathPart('actions') :CaptureArgs(0) {
    my ( $self, $c ) = @_;

    my $actions_rs = $c->stash->{rule_result}->actions({
    },{
        order_by => { -asc => 'priority' },
    });
    $c->stash(actions_rs => $actions_rs);

    $c->stash(actions_uri => $c->uri_for_action("/header/actions_root", $c->req->captures));

    $c->stash(template => 'header/actions_list.tt');
    return;
}

sub actions_root :Chained('actions_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;

    my $actions_rs = $c->stash->{actions_rs};
    my $param_move  = $c->req->params->{move};
    my $param_where = $c->req->params->{where};

    if ($param_move && is_int($param_move) && $param_where) {
        my $elem = $actions_rs->find($param_move);
        my $use_next = ($param_where eq "down") ? 1 : 0;
        my $swap_elem = $actions_rs->search({
            priority => { ($use_next ? '>' : '<') => $elem->priority },
        },{
            order_by => {($use_next ? '-asc' : '-desc') => 'priority'},
        })->first;
        try {
            if ($swap_elem) {
                my $tmp_priority = $swap_elem->priority;
                $swap_elem->priority($elem->priority);
                $elem->priority($tmp_priority);
                $swap_elem->update;
                $elem->update;
            } elsif ($use_next) {
                my $last_priority = $c->stash->{actions_rs}->get_column('priority')->max() || 99;
                $elem->priority(int($last_priority) + 1);
                $elem->update;
            } else {
                my $last_priority = $c->stash->{actions_rs}->get_column('priority')->min() || 1;
                $elem->priority(int($last_priority) - 1);
                $elem->update;
            }
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to move action.'),
            );
        }
    }

    my @actions = ();

    foreach my $action ($actions_rs->all) {
        my $row = { $action->get_inflated_columns };
        push @actions, $row;
        if ($row->{rwr_set_id}) {
                my $rwr_set = { $action->rwr_set->get_inflated_columns };
                $row->{rwr_set} = $rwr_set->{name};
                my $dp_id = $row->{rwr_dp_id} // 0;
                ($row->{rwr_dp}) =
                    grep { $_ =~ /_dpid/ && $rwr_set->{$_} eq $dp_id }
                        keys %{$rwr_set};
        }
    }

    $c->stash(actions => \@actions);
    return;
}

sub actions_base :Chained('actions_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $action_id) = @_;

    $c->stash(actions_uri => $c->uri_for_action("/header/actions_root",
        [$c->stash->{set_result}->id, $c->stash->{rule_result}->id])
    );

    unless ($action_id && is_int($action_id)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Invalid header rule action id detected',
            desc  => $c->loc('Invalid header rule action id detected'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{actions_uri});
    }

    my $res = $c->stash->{actions_rs}->find($action_id);
    unless (defined($res)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Header rule action does not exist',
            desc  => $c->loc('Header rule action does not exist'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{actions_uri});
    }
    $c->stash(action_result => $res);

    return;
}

sub actions_edit :Chained('actions_base') :PathPart('edit') {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Header::Action", $c);
    my $action = $c->stash->{action_result};
    my $params = {};

    unless ($posted) {
        $params = { $action->get_inflated_columns };
        if ($params->{rwr_set_id}) {
                my $rwr_set = { $action->rwr_set->get_inflated_columns };
                $params->{rwr_set} = $rwr_set->{id};
                my $dp_id = $params->{rwr_dp_id} // 0;
                ($params->{rwr_dp}) =
                    grep { $_ =~ /_dpid/ && $rwr_set->{$_} eq $dp_id }
                        keys %{$rwr_set};
        }
    }

    $form->process(params => $posted ? $c->req->params : $params);
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            my $guard = $c->model('DB')->txn_scope_guard;
            {
                my $data = $form->values;

                if ($data->{rwr_set}) {
                    $data->{rwr_set_id} = delete $data->{rwr_set};
                    my $rwr_rs = $c->model('DB')
                                ->resultset('voip_rewrite_rule_sets')
                                ->search({ id => $data->{rwr_set_id} });
                    if ($rwr_rs->count) {
                        my $rwr_set = { $rwr_rs->first->get_inflated_columns };
                        $data->{rwr_dp_id} = $rwr_set->{$data->{rwr_dp}} // undef;
                    } else {
                        $data->{rwr_set_id} = undef;
                        $data->{rwr_dp_id} = undef;
                    }
                } else {
                    $data->{rwr_set_id} = undef;
                    $data->{rwr_dp_id} = undef;
                }
                delete $data->{rwr_set};
                delete $data->{rwr_dp};

                $action->update($data);
            }
            $guard->commit;
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Header rule action successfully updated'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update header rule action'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{actions_uri});
    }

    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
}

sub actions_delete :Chained('actions_base') :PathPart('delete') {
    my ($self, $c) = @_;

    try {
        $c->stash->{action_result}->delete;
        NGCP::Panel::Utils::Message::info(
            c    => $c,
            data => { $c->stash->{action_result}->get_inflated_columns },
            desc => $c->loc('Header rule action successfully deleted'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            desc  => $c->loc('Failed to delete header rule action'),
        );
    };
    NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{actions_uri});
}

sub actions_create :Chained('actions_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Header::Action", $c);
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
            my $guard = $c->model('DB')->txn_scope_guard;
            {
                my $data = $form->values;
                $data->{rule_id} = $c->stash->{rule_result}->id;

                if ($data->{rwr_set}) {
                    $data->{rwr_set_id} = delete $data->{rwr_set};
                    my $rwr_rs = $c->model('DB')
                                ->resultset('voip_rewrite_rule_sets')
                                ->search({ id => $data->{rwr_set_id} });
                    if ($rwr_rs->count) {
                        my $rwr_set = { $rwr_rs->first->get_inflated_columns };
                        $data->{rwr_dp_id} = $rwr_set->{$data->{rwr_dp}} // undef;
                    } else {
                        $data->{rwr_set_id} = undef;
                        $data->{rwr_dp_id} = undef;
                    }
                } else {
                    $data->{rwr_set_id} = undef;
                    $data->{rwr_dp_id} = undef;
                }
                delete $data->{rwr_set};
                delete $data->{rwr_dp};

                my $last_priority = $c->stash->{actions_rs}->get_column('priority')->max() || 99;
                $data->{priority} = int($last_priority) + 1;

                $c->stash->{actions_rs}->create($data);
            }
            $guard->commit;
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Header rule action successfully created'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create a header rule action'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{actions_uri});
    }

    $c->stash(form => $form);
    $c->stash(create_flag => 1);
}

1;

=head1 NAME

NGCP::Panel::Controller::Header - Manage Header Rules

=head1 DESCRIPTION

Show/Edit/Create/Delete Header Rule Sets.

Show/Edit/Create/Delete Header Rules within Header Rule Sets.

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

Sipwise Development Team C<< <support@sipwise.com> >>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
