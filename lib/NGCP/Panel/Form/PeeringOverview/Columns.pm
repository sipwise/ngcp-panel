package NGCP::Panel::Form::PeeringOverview::Columns;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'rule_direction' => (
    type => 'Select',
    label => 'Direction',
    widget => 'RadioGroup',
    options => [ { checked => 1, label => 'Outbound', value => 'outbound' },
                 { label => 'Inbound', value => 'inbound'} ],
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Peering rules direction (outbound or inbound).'],
    },
);

has_field 'out_callee_prefix' => (
    type => 'Boolean',
    label => 'Prefix',
    default => 1,
    element_attr => {
        type => 'outbound',
        field => 'callee_prefix',
    },
);

has_field 'out_callee_pattern' => (
    type => 'Boolean',
    label => 'Callee Pattern',
    default => 0,
    element_attr => {
        type => 'outbound',
        field => 'callee_pattern',
    },
);

has_field 'out_caller_pattern' => (
    type => 'Boolean',
    label => 'Caller Pattern',
    default => 0,
    element_attr => {
        type => 'outbound',
        field => 'caller_pattern',
    },
);

has_field 'out_enabled' => (
    type => 'Boolean',
    label => 'State',
    default => 1,
    element_attr => {
        type => 'outbound',
        field => 'enabled',
    },
);

has_field 'out_description' => (
    type => 'Boolean',
    label => 'Description',
    default => 1,
    element_attr => {
        type => 'outbound',
        field => 'description',
    },
);

has_field 'out_group_name' => (
    type => 'Boolean',
    label => 'Peer Group',
    default => 1,
    element_attr => {
        type => 'outbound',
        field => 'group.name',
    },
);

has_field 'out_peer_name' => (
    type => 'Boolean',
    label => 'Peer Name',
    default => 1,
    element_attr => {
        type => 'outbound',
        field => 'group.voip_peer_hosts.name',
    },
);

has_field 'out_peer_host' => (
    type => 'Boolean',
    label => 'Peer Host',
    default => 1,
    element_attr => {
        type => 'outbound',
        field => 'group.voip_peer_hosts.host',
    },
);

has_field 'out_peer_ip' => (
    type => 'Boolean',
    label => 'Peer IP',
    default => 1,
    element_attr => {
        type => 'outbound',
        field => 'group.voip_peer_hosts.ip',
    },
);

has_field 'out_peer_port' => (
    type => 'Boolean',
    label => 'Peer Port',
    default => 0,
    element_attr => {
        type => 'outbound',
        field => 'group.voip_peer_hosts.port',
    },
);

has_field 'out_peer_transport' => (
    type => 'Boolean',
    label => 'Peer Proto',
    default => 0,
    element_attr => {
        type => 'outbound',
        field => 'group.voip_peer_hosts.transport',
    },
);

has_field 'out_peer_state' => (
    type => 'Boolean',
    label => 'Peer State',
    default => 1,
    element_attr => {
        type => 'outbound',
        field => 'group.voip_peer_hosts.enabled',
    },
);

has_field 'out_group_priority' => (
    type => 'Boolean',
    label => 'Priority',
    default => 1,
    element_attr => {
        type => 'outbound',
        field => 'group.priority',
    },
);

has_field 'out_peer_weight' => (
    type => 'Boolean',
    label => 'Weight',
    default => 1,
    element_attr => {
        type => 'outbound',
        field => 'group.voip_peer_hosts.weight',
    },
);

has_field 'in_field' => (
    type => 'Boolean',
    label => 'Field',
    default => 1,
    element_attr => {
        type => 'inbound',
        field => 'field',
    },
);

has_field 'in_pattern' => (
    type => 'Boolean',
    label => 'Pattern',
    default => 1,
    element_attr => {
        type => 'inbound',
        field => 'pattern',
    },
);

has_field 'in_reject_code' => (
    type => 'Boolean',
    label => 'Reject Code',
    default => 1,
    element_attr => {
        type => 'inbound',
        field => 'reject_code',
    },
);

has_field 'in_reject_reason' => (
    type => 'Boolean',
    label => 'Reject Reason',
    default => 1,
    element_attr => {
        type => 'inbound',
        field => 'reject_reason',
    },
);

has_field 'in_priority' => (
    type => 'Boolean',
    label => 'Rule Priority',
    default => 1,
    element_attr => {
        type => 'inbound',
        field => 'priority',
    },
);

has_field 'in_enabled' => (
    type => 'Boolean',
    label => 'State',
    default => 1,
    element_attr => {
        type => 'inbound',
        field => 'enabled',
    },
);

has_field 'in_group_name' => (
    type => 'Boolean',
    label => 'Peer Group',
    default => 1,
    element_attr => {
        type => 'inbound',
        field => 'group.name',
    },
);

has_field 'in_peer_name' => (
    type => 'Boolean',
    label => 'Peer Name',
    default => 1,
    element_attr => {
        type => 'inbound',
        field => 'group.voip_peer_hosts.name',
    },
);

has_field 'in_peer_host' => (
    type => 'Boolean',
    label => 'Peer Host',
    default => 1,
    element_attr => {
        type => 'inbound',
        field => 'group.voip_peer_hosts.host',
    },
);

has_field 'in_peer_ip' => (
    type => 'Boolean',
    label => 'Peer IP',
    default => 1,
    element_attr => {
        type => 'inbound',
        field => 'group.voip_peer_hosts.ip',
    },
);

has_field 'in_peer_port' => (
    type => 'Boolean',
    label => 'Peer Port',
    default => 0,
    element_attr => {
        type => 'inbound',
        field => 'group.voip_peer_hosts.port',
    },
);

has_field 'in_peer_transport' => (
    type => 'Boolean',
    label => 'Peer Proto',
    default => 0,
    element_attr => {
        type => 'inbound',
        field => 'group.voip_peer_hosts.transport',
    },
);

has_field 'in_peer_state' => (
    type => 'Boolean',
    label => 'Peer State',
    default => 1,
    element_attr => {
        type => 'inbound',
        field => 'group.voip_peer_hosts.enabled',
    },
);

has_field 'in_group_priority' => (
    type => 'Boolean',
    label => 'Priority',
    default => 1,
    element_attr => {
        type => 'inbound',
        field => 'group.priority',
    },
);

has_field 'in_peer_weight' => (
    type => 'Boolean',
    label => 'Weight',
    default => 1,
    element_attr => {
        type => 'inbound',
        field => 'group.voip_peer_hosts.weight',
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
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;

# vim: set tabstop=4 expandtab:
