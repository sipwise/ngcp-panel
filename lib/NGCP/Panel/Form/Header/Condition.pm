package NGCP::Panel::Form::Header::Condition;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;

with 'NGCP::Panel::Render::RepeatableJs';

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'match_type' => (
    type => 'Select',
    options => [
        { label => 'header', value => 'header' },
        { label => 'preference', value => 'preference' },
        { label => 'avp', value => 'avp' },
    ],
    label => 'Match',
    required => 1,
);

has_field 'match_part' => (
    type => 'Select',
    options => [
        { label => 'full', value => 'full' },
        { label => 'username', value => 'username' },
        { label => 'domain', value => 'domain' },
        { label => 'port', value => 'port' },
    ],
    label => 'Part',
    required => 1,
);

has_field 'match_name' => (
    type => 'Text',
    label => 'Name',
    required => 1,
);

has_field 'expression' => (
    type => 'Select',
    options => [
        { label => 'is', value => 'is' },
        { label => 'contains', value => 'contains' },
        { label => 'matches', value => 'matches' },
        { label => 'regexp', value => 'regexp' },
    ],
    label => 'Expression',
    required => 1,
);

has_field 'expression_negation' => (
    type => 'Boolean',
    label => 'Not',
    default => 0,
);

has_field 'value_type' => (
    type => 'Select',
    options => [
        { label => 'input', value => 'input' },
        { label => 'preference', value => 'preference' },
        { label => 'avp', value => 'avp' },
    ],
    label => 'Type',
    required => 1,
);

has_field 'rwr_set' => (
    type => 'Select',
    label => 'Rewrite Rule Set',
    required => 0,
);

has_field 'rwr_set_id' => (
    type => 'Hidden',
    required => 0,
);

has_field 'rwr_dp' => (
    type => 'Select',
    label => 'Rewrite Rules',
    options => [
        { label => '', value => '' },
        { label => 'Inbound for Caller', value => 'caller_in_dpid' },
        { label => 'Inbound for Callee', value => 'callee_in_dpid' },
        { label => 'Outbound for Caller', value => 'caller_out_dpid' },
        { label => 'Outbound for Callee', value => 'callee_out_dpid' },
    ],
    required => 0,
);

has_field 'rwr_dp_id' => (
    type => 'Hidden',
    required => 0,
);

has_field 'enabled' => (
    type => 'Boolean',
    default => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Enables or disables the condition from being included in the headers processing logic'],
    },
);

has_field 'values' => (
    type => 'Repeatable',
    setup_for_js => 1,
    do_wrapper => 1,
    do_label => 0,
    tags => {
        controls_div => 1,
    },
    wrapper_class => [qw/hfh-rep/],
);

has_field 'rule_id' => (
    type => 'Hidden',
);

has_field 'value_group_id' => (
    type => 'Hidden',
);

has_field 'values.id' => (
    type => 'Hidden',
);

has_field 'values.group_id' => (
    type => 'Hidden',
);

has_field 'values.value' => (
    type => 'Text',
    label => 'Value',
    required => 1,
    wrapper_class => [qw/hfh-rep-field/],
);

has_field 'values.rm' => (
    type => 'RmElement',
    value => 'Remove',
    element_class => [qw/btn btn-primary pull-right/],
);

has_field 'value_add' => (
    type => 'AddElement',
    repeatable => 'values',
    value => 'Add value',
    element_class => [qw/btn btn-primary pull-right/],
);

has_field 'save' => (
    type => 'Submit',
    value => 'Save',
    element_class => [qw/btn btn-primary/],
    label => '',
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/match_type match_part match_name expression expression_negation value_type rule_id value_group_id rwr_set rwr_set_id rwr_dp rwr_dp_id enabled values value_add/ ],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

sub options_rwr_set {
    my ($self, $field) = @_;

    my $c = $self->ctx;
    return unless($c);

    my $rwr_rs = $c->model('DB')->resultset('voip_rewrite_rule_sets')->search({
        reseller_id => $c->stash->{set_result}->reseller_id,
    });

    $field->options([
        { label => '', value => '' },
        map { { label => $_->name, value => $_->id } } $rwr_rs->all
    ]);

    return;
}

1;

__END__

sub update_fields {
        my $condition = $c->stash->{condition_result};

        my $rwr_set_id = $condition ? $condition->rwr_set_id // 0 : 0;
     
        my $rwr = $rwr_rs->find($rwr_set_id);
        if ($rwr_set_id) {
            $self->field('rwr_set')->default($rwr->name);
        }
        my $dp_id = $condition ? $condition->rwr_dp_id // 0 : 0;
        my $dp = $self->field('rwr_dp')->options();
        if ($dp_id > 0 && $rwr) {
            my $row = { $rwr->get_inflated_columns };
            foreach my $opt (@{$dp}) {
                if ($row->{$opt->{value}.'_dpid'} == $dp_id) {
                }
            }
        }
    #}
    return;
}

# vim: set tabstop=4 expandtab:
