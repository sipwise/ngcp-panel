package NGCP::Panel::Role::API::HeaderRuleConditions;

use parent qw/NGCP::Panel::Role::API/;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);
use NGCP::Panel::Utils::HeaderManipulations;
use NGCP::Panel::Utils::API;
use HTTP::Status qw(:constants);

sub item_name {
    return 'headerrulecondition';
}

sub resource_name {
    return 'headerruleconditions';
}

sub config_allowed_roles {
    return [qw/admin reseller/];
}

sub _item_rs {
    my ($self, $c, $type) = @_;

    my $item_rs = $c->model('DB')->resultset('voip_header_rule_conditions')->search_rs(undef, {
        join => { rule => 'ruleset' }
    });

    if ($c->user->roles eq "reseller") {
        $item_rs = $c->model('DB')->resultset('voip_header_rule_conditions')->search_rs({
            'ruleset.reseller_id' => $c->user->reseller_id,
        });
    }

    if (my $subscriber_id = $c->req->param('subscriber_id')) {
        my $prov_subscriber_id = NGCP::Panel::Utils::Subscriber::billing_to_prov_subscriber_id(
            c => $c, subscriber_id => $subscriber_id
        );
        $item_rs = $item_rs->search_rs(
            { 'ruleset.subscriber_id' => $prov_subscriber_id });
    } else {
        $item_rs = $item_rs->search_rs(
            { 'ruleset.subscriber_id' => undef });
    }

    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return ( NGCP::Panel::Form::get("NGCP::Panel::Form::Header::ConditionAPI", $c) );
}

sub hal_links {
    my ($self, $c, $item, $resource, $form) = @_;
    return [
        Data::HAL::Link->new(relation => "ngcp:headerrulesets", href => sprintf("/api/headerrulesets/%d", $item->rule->set_id)),
        Data::HAL::Link->new(relation => "ngcp:headerrules", href => sprintf("/api/headerrules/%d", $item->rule->id)),
    ];
}

sub post_process_hal_resource {
    my ($self, $c, $item, $resource, $form) = @_;
    my $dp_id = delete $resource->{rwr_dp_id};
    my @values = ();
    if ($item->rwr_set_id && $item->rwr_set) {
        my %rwr_set_cols = $item->rwr_set->get_inflated_columns;
        foreach my $dp_t (qw(callee_in callee_out caller_in caller_out)) {
            my $c_dp_id = $rwr_set_cols{$dp_t.'_dpid'} // next;
            if ($c_dp_id == $dp_id) {
                $resource->{rwr_dp} = $dp_t;
                last;
            }
        }
    }
    foreach my $r ($item->values->all) {
        push @values, $r->value;
    }
    $resource->{values} = \@values;
    return $resource;
}

sub resource_from_item {
    my ($self, $c, $item, $form) = @_;

    my %resource = $item->get_inflated_columns;
    my @values = ();

    foreach my $r ($item->values->all) {
        push @values, { $r->get_inflated_columns };
    }
    $resource{values} = \@values;

    return \%resource;
}

sub check_resource {
    my ($self, $c, $item, $old_resource, $resource, $form, $process_extras) = @_;
    my $schema = $c->model('DB');

    unless (defined $resource->{rule_id}) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Required: 'rule_id'");
        return;
    }

    if (!defined $resource->{rwr_set_id} && (defined $resource->{rwr_dp} || defined $resource->{rwr_dp_id})) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Missing 'rwr_set_id' (when rwr_dp is set).");
        return;
    }

    my $reseller_id;
    if ($c->user->roles eq "reseller") {
        $reseller_id = $c->user->reseller_id;
    }

    my $rule = $schema->resultset('voip_header_rules')->find({
        id => $resource->{rule_id},
        ($reseller_id ? ('ruleset.reseller_id' => $reseller_id) : ()),
    },{
        join => 'ruleset',
    });
    unless ($rule) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'rule_id'.");
        return;
    }
    return 1 unless $resource->{rwr_set_id};

    my $rwr_set = $schema->resultset('voip_rewrite_rule_sets')->find({
        id => $resource->{rwr_set_id},
        ($reseller_id ? ('ruleset.reseller_id' => $reseller_id) : ()),
    });
    unless ($rwr_set) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'rwr_set_id'.");
        return;
    }
    unless ($resource->{rwr_dp} || $resource->{rwr_dp_id}) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Missing 'rwr_dp' (when rwr_set_id is set).");
        return;
    }

    my %rwr_set_cols = $rwr_set->get_inflated_columns;

    # normally when resource already exists,
    # so to check if rwr_dp_id belongs to the same rwr_set
    # if somehow it is forcibly passed as a wrong value
    if ($resource->{rwr_dp_id}) {
        foreach my $dp_t (qw(callee_in callee_out caller_in caller_out)) {
            my $c_dp_id = $rwr_set_cols{$dp_t.'_dpid'} // next;
            return 1 if $c_dp_id == $resource->{rwr_dp_id};
        }
        # the provided rwr_dp_id does not belong to the rwr_set
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'rwr_dp_id' (does not belong to the rwr_set_id).");
        return;
    } else {
        my $rwr_dp = delete $resource->{rwr_dp};
        $resource->{rwr_dp_id} = $rwr_set_cols{$rwr_dp.'_dpid'};
    }

    return 1;
}

sub update_item_model {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    NGCP::Panel::Utils::HeaderManipulations::update_condition(
        c => $c, resource => $resource, item => $item
    );

    NGCP::Panel::Utils::HeaderManipulations::invalidate_ruleset(
        c => $c, set_id => $item->rule->ruleset->id
    );

    return $item;
}

1;
# vim: set tabstop=4 expandtab:
