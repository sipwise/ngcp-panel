package NGCP::Panel::Form::Subscriber::TrustedSource;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
sub build_render_list {[qw/fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'src_ip' => (
    type => 'Text',
    label => 'Source IP',
    required => 1,
);

has_field 'protocol' => (
    type => 'Select',
    label => 'Protocol',
    required => 1,
    options => [
        { label => 'UDP', value => 'UDP' },
        { label => 'TCP', value => 'TCP' },
        { label => 'TLS', value => 'TLS' },
        { label => 'ANY', value => 'ANY' },
    ],
);

has_field 'from_pattern' => (
    type => 'Text',
    label => 'From Pattern',
    required => 0,
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
    render_list => [qw/src_ip protocol from_pattern/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;
# vim: set tabstop=4 expandtab:
