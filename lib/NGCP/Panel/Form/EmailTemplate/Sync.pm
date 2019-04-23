package NGCP::Panel::Form::EmailTemplate::Sync;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'id' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Missed email templates',
    do_label => 0,
    do_wrapper => 0,
    required => 1,
    no_pagination => 1,
    no_ordering => 1,
    only_visible_values => 1,
    template => 'helpers/datatables_multifield.tt',
    ajax_src => '/emailtemplate/ajax/missed',
    table_titles => ['#', 'Reseller', 'Email template'],
    table_fields => ['id', 'reseller_name', 'email_template_name'],
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/id/],
);

has_field 'save' => (
    type => 'Submit',
    value => 'Sync',
    element_class => [qw/btn btn-primary/],
    label => '',
);


has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;

# vim: set tabstop=4 expandtab:
