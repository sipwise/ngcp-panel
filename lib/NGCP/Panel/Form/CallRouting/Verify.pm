package NGCP::Panel::Form::CallRouting::Verify;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use Storable qw();

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields verify/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'caller' => (
    type => 'Text',
    label => 'Caller number/uri',
    required => 1,
    maxlength => 255,
    element_attr => {
        rel => ['tooltip'],
        title => ['Caller number or SIP uri']
    },
);

has_field 'caller_type' => (
    type => 'Select',
    label => 'Caller Type',
    widget => 'RadioGroup',
    options => [ { checked => 1, label => 'Subscriber', value => 'subscriber' },
                 { value => 'peer', label => 'Peer'} ],
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Caller type, Subscriber or Peer'],
    },
);

has_field 'callee' => (
    type => 'Text',
    label => 'Callee number/uri',
    required => 1,
    maxlength => 255,
    element_attr => {
        rel => ['tooltip'],
        title => ['Callee number or SIP uri'],
    },
);

has_field 'caller_subscriber_id' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Caller Subscriber',
    do_label => 1,
    do_wrapper => 0,
    required => 0,
    template => 'helpers/datatables_field.tt',
    ajax_src => '/subscriber/ajax',
    table_titles => ['#', 'Username', 'Domain', 'UUID', 'Number'],
    table_fields => ['id', 'username', 'domain.domain', 'uuid', 'number'],
    validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Caller subscriber']
    },
);

has_field 'caller_peer_id' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Caller Peer',
    do_label => 1,
    do_wrapper => 0,
    required => 0,
    template => 'helpers/datatables_field.tt',
    ajax_src => '/peering/ajax',
    table_titles => ['#', 'Name', 'Description'],
    table_fields => ['id', 'name', 'description'],
    validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Caller peering group']
    },
);

has_field 'caller_rewrite_id' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Caller Rewrite Rule Set',
    do_label => 0,
    do_wrapper => 1,
    required => 0,
    template => 'helpers/datatables_field.tt',
    ajax_src => '/rewrite/ajax',
    table_titles => ['#', 'Name', 'Description'],
    table_fields => ['id', 'name', 'description'],
    validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Caller rewrite rule set to override']
    },
);

has_field 'callee_peer_id' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Callee Peer',
    do_label => 0,
    do_wrapper => 0,
    required => 0,
    template => 'helpers/datatables_field.tt',
    ajax_src => '/peering/ajax',
    table_titles => ['#', 'Name', 'Description'],
    table_fields => ['id', 'name', 'description'],
    validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Caller peering group']
    },
);

has_field 'callee_rewrite_id' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Callee Rewrite Rule Set',
    do_label => 0,
    do_wrapper => 0,
    required => 0,
    template => 'helpers/datatables_field.tt',
    ajax_src => '/rewrite/ajax',
    table_titles => ['#', 'Name', 'Description'],
    table_fields => ['id', 'name', 'description'],
    validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Callee rewrite rule set to override']
    },
);

has_block 'fields' => (
    tag => 'div',
    render_list => [qw/caller callee caller_type caller_subscriber_id caller_peer_id caller_rewrite_id callee_peer_id callee_rewrite_id/],
);

has_field 'verify' => (
    type => 'Submit',
    value => 'Verify',
    element_class => [qw/btn btn-primary btn-large/],
    label => '',
);

sub validate_caller {
    my ($self, $field) = @_;
    my $c = $self->form->ctx;
    return unless $c;

    NGCP::Panel::Utils::Form::validate_number_uri(c => $c, field => $field);
}

sub validate_callee {
    my ($self, $field) = @_;
    my $c = $self->form->ctx;
    return unless $c;

    NGCP::Panel::Utils::Form::validate_number_uri(c => $c, field => $field);
}

1;
# vim: set tabstop=4 expandtab:
