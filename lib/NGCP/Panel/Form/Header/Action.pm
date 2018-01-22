package NGCP::Panel::Form::Header::Action;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'rule_id' => (
    type => 'Hidden',
);

has_field 'header' => (
    type => 'Text',
    label => 'Header',
    required => 1,
    id => 'c_header',
);

has_field 'header_part' => (
    type => 'Select',
    options => [
        { label => 'full', value => 'full' },
        { label => 'username', value => 'username' },
        { label => 'domain', value => 'domain' },
        { label => 'port', value => 'port' },
    ],
    label => 'Header Part',
    required => 1,
);

has_field 'action_type' => (
    type => 'Select',
    options => [
        { label => 'set', value => 'set' },
        { label => 'add', value => 'add' },
        { label => 'remove', value => 'remove' },
        { label => 'rsub', value => 'rsub' },
        { label => 'header', value => 'header' },
        { label => 'preference', value => 'preference' },
    ],
    label => 'Type',
    required => 1,
);

has_field 'value_part' => (
    type => 'Select',
    options => [
        { label => 'full', value => 'full' },
        { label => 'username', value => 'username' },
        { label => 'domain', value => 'domain' },
        { label => 'port', value => 'port' },
    ],
    label => 'Value Part',
    required => 1,
);

has_field 'value' => (
    type => 'Text',
    label => 'Value',
    required => 0,
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
        title => ['Enables or disables the action from being included in the headers processing logic'],
    },
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
    render_list => [qw/rule_id header header_part action_type value_part value rwr_set rwr_set_id rwr_dp rwr_dp_id enabled/ ],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

sub update_fields {
    my ($self) = @_;

    my $c = $self->ctx;
    return unless($c);

    #if ($c->stash->{create_flag} || $c->stash->{edit_flag}) {
        my $rwr_rs = $c->model('DB')->resultset('voip_rewrite_rule_sets')->search({
            reseller_id => $c->stash->{set_result}->reseller_id,
        });

      #  my $condition = $c->stash->{condition_result};

      #  my $rwr_set_id = $condition ? $condition->rwr_set_id // 0 : 0;
        $self->field('rwr_set')->options([
            { label => '', value => '' },
            map { { label => $_->name, value => $_->id } } $rwr_rs->all
        ]);
        #my $rwr = $rwr_rs->find($rwr_set_id);
        #if ($rwr_set_id) {
        #    $self->field('rwr_set')->default($rwr->name);
        #}
        #my $dp_id = $condition ? $condition->rwr_dp_id // 0 : 0;
        #my $dp = $self->field('rwr_dp')->options();
        #if ($dp_id > 0 && $rwr) {
        #    my $row = { $rwr->get_inflated_columns };
        #    foreach my $opt (@{$dp}) {
        #        if ($row->{$opt->{value}.'_dpid'} == $dp_id) {
        #        }
        #    }
        #}
    #}
    return;
}


1;

# vim: set tabstop=4 expandtab:
