package NGCP::Panel::Utils::HeaderManipulations;
use NGCP::Panel::Utils::Generic qw(:all);

use strict;
use warnings;

use Sipwise::Base;
use NGCP::Panel::Utils::Datatables;
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Message;

sub update_condition {
    my %params = @_;
    my ($c, $item, $resource) = @params{qw/c item resource/};

    my $schema = $c->model('DB');

    my $values = delete $resource->{values} // [];
    map { $_->{condition_id} = $item->id } @{$values};

    $item->update($resource);
    $item->values->delete;

    $schema->resultset('voip_header_rule_condition_values')
        ->populate($values);

    $resource->{values} = $values;
    $item->discard_changes()
}

sub invalidate_ruleset {
    my %params = @_;
    my ($c, $set_id) = @params{qw/c set_id/};

    my $schema = $c->model('DB');
    my $path   = "/hm_invalidate_ruleset/";
    my $target = "proxy-ng";

    $c->log->info("invalidate ruleset to target=$target path=$path set_id=$set_id");

    my $hosts;
    my $host_rs = $schema->resultset('xmlgroups')
        ->search_rs({name => $target})
        ->search_related('xmlhostgroups')->search_related('host', {}, { order_by => 'id' });
    $hosts = [map { +{ip => $_->ip, port => $_->port,
                      id => $_->id} } $host_rs->all];

    my %headers = (
                    "User-Agent" => "Sipwise HTTP Dispatcher",
                    "Content-Type" => "text/plain",
                    "P-NGCP-HM-Invalidate-Rule-Set" => $set_id,
                  );

    my @err;

    foreach my $host (@$hosts) {
        my ($method, $ip, $port, $id) =
            ("http", $host->{ip}, $host->{port}, $host->{id});
        my $hostid = "id=$id $ip:$port";
        $c->log->info("dispatching http request to ".$hostid.$path);

        eval {
            my $s = Net::HTTP->new(Host => $ip, KeepAlive => 0, PeerPort => $port, Timeout => 5);
            $s or die "could not connect to server $hostid";

            my $res = $s->write_request("POST", $path || "/", %headers, $set_id);
            $res or die "did not get result from $hostid";

            my ($code, $status, @hdrs) = $s->read_response_headers();
            unless ($code == 200) {
                push @err, "$hostid: $code $status";
            }
        };

        if ($@) {
            my $msg = "$hostid: $@";
            push @err, $msg;
            $c->log->info("failure: $msg");
        }
    }

    return \@err;
}

sub get_subscriber_set {
    my %params = @_;
    my ($c, $prov_subscriber_id) = @params{qw/c subscriber_id/};

    return unless $prov_subscriber_id;

    my $schema = $c->model('DB');

    return $schema->resultset('voip_header_rule_sets')->find({
        subscriber_id => $prov_subscriber_id
    });
}

sub create_subscriber_set {
    my %params = @_;
    my ($c, $prov_subscriber_id) = @params{qw/c subscriber_id/};

    return unless $prov_subscriber_id;

    my $schema = $c->model('DB');

    my $sub_set = $schema->resultset('voip_header_rule_sets')->find({
        subscriber_id => $prov_subscriber_id
    });

    return $sub_set if $sub_set;

    my $prov_subscriber = $schema->resultset('provisioning_voip_subscribers')->find($prov_subscriber_id);
    return unless $prov_subscriber;
    my $subscriber = $prov_subscriber->voip_subscriber;
    $sub_set = $schema->resultset('voip_header_rule_sets')->create({
        reseller_id => $subscriber->contract->contact->reseller_id,
        subscriber_id => $prov_subscriber_id,
        name => 'subscriber_'.$subscriber->id,
        description => '',
    });
    $sub_set->discard_changes;

    return $sub_set;
}

sub cleanup_subscriber_set {
    my %params = @_;
    my ($c, $prov_subscriber_id) = @params{qw/c subscriber_id/};

    return unless $prov_subscriber_id;

    my $schema = $c->model('DB');

    my $set_rs = $schema->resultset('voip_header_rule_sets')->search({
        subscriber_id => $prov_subscriber_id
    });

    return unless $set_rs && $set_rs->first;

    return if $set_rs->first->voip_header_rules->count;

    $set_rs->first->delete;

    return;
}

sub ui_rules_list {
    my %params = @_;
    my ($c) = @params{qw/c/};

    my $schema = $c->model('DB');

    my $rules_rs;
    if ($c->stash->{hm_set_result}) {
        $rules_rs = $c->stash->{hm_set_result}->voip_header_rules({
        },{
            order_by => { -asc => 'priority' },
        });
    } else {
        $rules_rs = $schema->resultset('voip_header_rules')->search({
            set_id => 0
        });
    }
    $c->stash(hm_rules_rs => $rules_rs);

    $c->stash->{hm_rule_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'priority', search => 0, title => $c->loc('Priority') },
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'name', search => 1, title => $c->loc('Name') },
        { name => 'description', search => 1, title => $c->loc('Description') },
        { name => 'direction', search => 1, title => $c->loc('Direction') },
        { name => 'stopper', search => 1, title => $c->loc('Stopper') },
        { name => 'enabled', search => 1, title => $c->loc('Enabled') },
    ]);

    return;
}

sub ui_rules_root {
    my %params = @_;
    my ($c) = @params{qw/c/};

    my $rules_rs    = $c->stash->{hm_rules_rs};
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
                my $last_priority = $c->stash->{hm_rules_rs}->get_column('priority')->max() || 99;
                $elem->priority(int($last_priority) + 1);
                $elem->update;
            } else {
                my $last_priority = $c->stash->{hm_rules_rs}->get_column('priority')->min() || 1;
                $elem->priority(int($last_priority) - 1);
                $elem->update;
            }
            NGCP::Panel::Utils::HeaderManipulations::invalidate_ruleset(
                c => $c, set_id => $c->stash->{hm_set_result}->id
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to move header rule.'),
            );
        }
    }

    $c->stash(hm_rules => [ $rules_rs->all ]);
    return;
}

sub ui_rules_ajax {
    my %params = @_;
    my ($c) = @params{qw/c/};

    my $rs = $c->stash->{hm_rules_rs};
    NGCP::Panel::Utils::Datatables::process($c, $rs, $c->stash->{hm_rule_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub ui_rules_base {
    my %params = @_;
    my ($c, $rule_id) = @params{qw/c rule_id/};

    unless($rule_id && is_int($rule_id)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Invalid header rule id detected',
            desc  => $c->loc('Invalid header rule id detected'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{hm_rules_uri});
    }

    my $res = $c->stash->{hm_rules_rs}->find($rule_id);
    unless(defined($res)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Header rule does not exist',
            desc  => $c->loc('Header rule does not exist'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{hm_rules_uri});
    }
    $c->stash(hm_rule_result => $res);
    return;
}

sub ui_rules_edit {
    my %params = @_;
    my ($c) = @params{qw/c/};

    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Header::Rule", $c);
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item   => $c->stash->{hm_rule_result},
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            $c->stash->{hm_rule_result}->update($form->values);
            NGCP::Panel::Utils::HeaderManipulations::invalidate_ruleset(
                c => $c, set_id => $c->stash->{hm_set_result}->id
            );
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
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{hm_rules_uri});
    }

    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
}

sub ui_rules_delete {
    my %params = @_;
    my ($c) = @params{qw/c/};

    try {
        my $rule_res = delete $c->stash->{hm_rule_result};
        my %hm_rule_columns = $rule_res->get_inflated_columns;
        $rule_res->delete;
        NGCP::Panel::Utils::HeaderManipulations::invalidate_ruleset(
            c => $c, set_id => $c->stash->{hm_set_result}->id
        );
        if ($c->stash->{subscriber}) {
            $rule_res->discard_changes;
            my $rules_cnt = NGCP::Panel::Utils::HeaderManipulations::cleanup_subscriber_set(
                c => $c,
                subscriber_id =>
                    $c->stash->{subscriber}->provisioning_voip_subscriber->id
            );
            if ($c->stash->{subscriber} && !$rules_cnt) {
                delete $c->stash->{hm_set_result};
            }
        }
        NGCP::Panel::Utils::Message::info(
            c    => $c,
            data => \%hm_rule_columns,
            desc => $c->loc('Header rule successfully deleted'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            desc  => $c->loc('Failed to delete header rule'),
        );
    };
    NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{hm_rules_uri});
    return;
}

sub ui_rules_create {
    my %params = @_;
    my ($c) = @params{qw/c/};

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
            if (!$c->stash->{hm_set_result} && $c->stash->{subscriber}) {
                $c->stash->{hm_set_result} =
                    NGCP::Panel::Utils::HeaderManipulations::create_subscriber_set(
                        c => $c,
                        subscriber_id =>
                            $c->stash->{subscriber}->provisioning_voip_subscriber->id
                    ) || die "could not create a subscriber header rule set";
                $c->stash->{hm_rules_rs} = $c->stash->{hm_set_result}->voip_header_rules;
            }
            my $last_priority = $c->stash->{hm_rules_rs}->get_column('priority')->max() || 99;
            $form->values->{priority} = int($last_priority) + 1;
            $c->stash->{hm_rules_rs}->create($form->values)->discard_changes;
            NGCP::Panel::Utils::HeaderManipulations::invalidate_ruleset(
                c => $c, set_id => $c->stash->{hm_set_result}->id
            );
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
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{hm_rules_uri});
    }

    $c->stash(form => $form);
    $c->stash(create_flag => 1);
    return;
}

sub ui_conditions_list {
    my %params = @_;
    my ($c) = @params{qw/c/};

    my $conditions_rs = $c->stash->{hm_rule_result}->conditions;

    $c->stash(hm_conditions_rs => $conditions_rs);

    $c->stash->{hm_condition_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'match_type', search => 1, title => $c->loc('Match') },
        { name => 'match_part', search => 1, title => $c->loc('Part') },
        { name => 'match_name', search => 1, title => $c->loc('Name') },
        { name => 'expression', search => 1, title => $c->loc('Expression') },
        { name => 'value_type', search => 1, title => $c->loc('Type') },
        { name => 'c_values', search => 0, title => $c->loc('Values') },
        { name => 'c_rwr_set', search => 0, title => $c->loc('Rewrite Rule Set') },
        { name => 'enabled', search => 1, title => $c->loc('Enabled') },
    ]);

    return;
}

sub ui_conditions_root {
    my %params = @_;
    my ($c) = @params{qw/c/};

    my $conditions_rs = $c->stash->{hm_conditions_rs};

    $c->stash(hm_conditions => [ $conditions_rs->all ] );

    return;
}

sub ui_conditions_ajax {
    my %params = @_;
    my ($c) = @params{qw/c/};

    my $rs = $c->stash->{hm_conditions_rs};
    NGCP::Panel::Utils::Datatables::process($c, $rs, $c->stash->{hm_condition_dt_columns}, sub {
        my $item = shift;
        my %cols = $item->get_inflated_columns;
        my ($c_rwr_set, $c_rwr_dp) = ('','');
        if ($cols{rwr_set_id}) {
            my %rwr_set = $item->rwr_set->get_inflated_columns;
            $c_rwr_set = $rwr_set{name};
            my $dp_id = $cols{rwr_dp_id} // 0;
            ($c_rwr_dp) =
                grep { $_ =~ /_dpid/ && $rwr_set{$_} eq $dp_id }
                    keys %rwr_set;
            $c_rwr_dp =~ s/_dpid$//;
        }
        return (
            expression => ($cols{expression_negation} ? ' ! ' : ' ') . $cols{expression},
            c_values => join("<br/>", map { $_->value } $item->values->all) // '',
            c_rwr_set => $c_rwr_set ? "$c_rwr_set ($c_rwr_dp)" : '',
        );
    });
    $c->detach( $c->view("JSON") );
}

sub ui_conditions_base {
    my %params = @_;
    my ($c, $condition_id) = @params{qw/c condition_id/};

    $c->stash(hm_conditions_uri => $c->uri_for_action("/header/conditions_root",
        [$c->stash->{hm_set_result}->id, $c->stash->{hm_rule_result}->id])
    );

    unless ($condition_id && is_int($condition_id)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Invalid header rule condition id detected',
            desc  => $c->loc('Invalid header rule condition id detected'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{hm_conditions_uri});
    }

    my $res = $c->stash->{hm_conditions_rs}->find($condition_id);
    unless (defined($res)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Header rule condition does not exist',
            desc  => $c->loc('Header rule condition does not exist'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{hm_conditions_uri});
    }
    $c->stash(hm_condition_result => $res);

    return;
}

sub ui_conditions_edit {
    my %params = @_;
    my ($c) = @params{qw/c/};

    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Header::Condition", $c);
    my $condition = $c->stash->{hm_condition_result};
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

                NGCP::Panel::Utils::HeaderManipulations::update_condition(
                    c => $c, resource => $data, item => $condition
                );
            }
            $guard->commit;
            NGCP::Panel::Utils::HeaderManipulations::invalidate_ruleset(
                c => $c, set_id => $c->stash->{hm_set_result}->id
            );
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
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{hm_conditions_uri});
    }

    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
}

sub ui_conditions_delete {
    my %params = @_;
    my ($c) = @params{qw/c/};

    try {
        $c->stash->{hm_condition_result}->delete;
        NGCP::Panel::Utils::HeaderManipulations::invalidate_ruleset(
            c => $c, set_id => $c->stash->{hm_set_result}->id
        );
        NGCP::Panel::Utils::Message::info(
            c    => $c,
            data => { $c->stash->{hm_condition_result}->get_inflated_columns },
            desc => $c->loc('Header rule condition successfully deleted'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            desc  => $c->loc('Failed to delete header rule condition'),
        );
    };
    NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{hm_conditions_uri});
}

sub ui_conditions_create {
    my %params = @_;
    my ($c) = @params{qw/c/};

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
                $data->{rule_id} = $c->stash->{hm_rule_result}->id;

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

                $c->stash->{hm_conditions_rs}->create($data);
            }
            $guard->commit;
            NGCP::Panel::Utils::HeaderManipulations::invalidate_ruleset(
                c => $c, set_id => $c->stash->{hm_set_result}->id
            );
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
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{hm_conditions_uri});
    }

    $c->stash(form => $form);
    $c->stash(create_flag => 1);
}

sub ui_actions_list {
    my %params = @_;
    my ($c) = @params{qw/c/};

    my $actions_rs = $c->stash->{hm_rule_result}->actions({
    },{
        order_by => { -asc => 'priority' },
    });
    $c->stash(hm_actions_rs => $actions_rs);

    $c->stash->{hm_action_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'priority', search => 0, title => $c->loc('Priority') },
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'header', search => 1, title => $c->loc('Header') },
        { name => 'header_part', search => 1, title => $c->loc('Part') },
        { name => 'action_type', search => 1, title => $c->loc('Type') },
        { name => 'value_part', search => 1, title => $c->loc('Value Part') },
        { name => 'value', search => 1, title => $c->loc('Value') },
        { name => 'c_rwr_set', search => 0, title => $c->loc('Rewrite Rule Set') },
        { name => 'enabled', search => 1, title => $c->loc('Enabled') },
    ]);

    return;
}

sub ui_actions_root {
    my %params = @_;
    my ($c) = @params{qw/c/};

    my $actions_rs = $c->stash->{hm_actions_rs};
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
                my $last_priority = $c->stash->{hm_actions_rs}->get_column('priority')->max() || 99;
                $elem->priority(int($last_priority) + 1);
                $elem->update;
            } else {
                my $last_priority = $c->stash->{hm_actions_rs}->get_column('priority')->min() || 1;
                $elem->priority(int($last_priority) - 1);
                $elem->update;
            }
            NGCP::Panel::Utils::HeaderManipulations::invalidate_ruleset(
                c => $c, set_id => $c->stash->{hm_set_result}->id
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to move action.'),
            );
        }
    }

    $c->stash(hm_actions => [ $actions_rs->all ]);

    return;
}

sub ui_actions_ajax {
    my %params = @_;
    my ($c) = @params{qw/c/};

    my $rs = $c->stash->{hm_actions_rs};
    NGCP::Panel::Utils::Datatables::process($c, $rs, $c->stash->{hm_action_dt_columns}, sub {
        my $item = shift;
        my %cols = $item->get_inflated_columns;
        my ($c_rwr_set, $c_rwr_dp) = ('','');
        if ($cols{rwr_set_id}) {
            my %rwr_set = $item->rwr_set->get_inflated_columns;
            $c_rwr_set = $rwr_set{name};
            my $dp_id = $cols{rwr_dp_id} // 0;
            ($c_rwr_dp) =
                grep { $_ =~ /_dpid/ && $rwr_set{$_} eq $dp_id }
                    keys %rwr_set;
            $c_rwr_dp =~ s/_dpid$//;
        }
        return (
            c_rwr_set => $c_rwr_set ? "$c_rwr_set ($c_rwr_dp)" : '',
        );
    });
    $c->detach( $c->view("JSON") );
}

sub ui_actions_base {
    my %params = @_;
    my ($c, $action_id) = @params{qw/c action_id/};

    $c->stash(hm_actions_uri => $c->uri_for_action("/header/actions_root",
        [$c->stash->{hm_set_result}->id, $c->stash->{hm_rule_result}->id])
    );

    unless ($action_id && is_int($action_id)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Invalid header rule action id detected',
            desc  => $c->loc('Invalid header rule action id detected'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{hm_actions_uri});
    }

    my $res = $c->stash->{hm_actions_rs}->find($action_id);
    unless (defined($res)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Header rule action does not exist',
            desc  => $c->loc('Header rule action does not exist'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{hm_actions_uri});
    }
    $c->stash(hm_action_result => $res);

    return;
}

sub ui_actions_edit {
    my %params = @_;
    my ($c) = @params{qw/c/};

    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Header::Action", $c);
    my $action = $c->stash->{hm_action_result};
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
            NGCP::Panel::Utils::HeaderManipulations::invalidate_ruleset(
                c => $c, set_id => $c->stash->{hm_set_result}->id
            );
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
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{hm_actions_uri});
    }

    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
}

sub ui_actions_delete {
    my %params = @_;
    my ($c) = @params{qw/c/};

    try {
        $c->stash->{hm_action_result}->delete;
        NGCP::Panel::Utils::HeaderManipulations::invalidate_ruleset(
            c => $c, set_id => $c->stash->{hm_set_result}->id
        );
        NGCP::Panel::Utils::Message::info(
            c    => $c,
            data => { $c->stash->{hm_action_result}->get_inflated_columns },
            desc => $c->loc('Header rule action successfully deleted'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            desc  => $c->loc('Failed to delete header rule action'),
        );
    };
    NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{hm_actions_uri});
}

sub ui_actions_create {
    my %params = @_;
    my ($c) = @params{qw/c/};

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
                $data->{rule_id} = $c->stash->{hm_rule_result}->id;

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

                my $last_priority = $c->stash->{hm_actions_rs}->get_column('priority')->max() || 99;
                $data->{priority} = int($last_priority) + 1;

                $c->stash->{hm_actions_rs}->create($data);
            }
            $guard->commit;
            NGCP::Panel::Utils::HeaderManipulations::invalidate_ruleset(
                c => $c, set_id => $c->stash->{hm_set_result}->id
            );
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
        NGCP::Panel::Utils::Navigation::back_or($c, $c->stash->{hm_actions_uri});
    }

    $c->stash(form => $form);
    $c->stash(create_flag => 1);
}

1;
