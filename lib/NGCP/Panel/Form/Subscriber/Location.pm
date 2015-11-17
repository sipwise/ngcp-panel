package NGCP::Panel::Form::Subscriber::Location;

use HTML::FormHandler::Moose;
use parent 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'contact' => (
    type => 'Text',
    label => 'Contact URI',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['A full SIP URI like sip:user@ip:port']
    },
);

has_field 'q' => (
    type => 'Float',
    label => 'Priority (q-value)',
    required => 1,
    range_start => -1,
    range_end => 1,
    decimal_symbol => '.',
    default => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The contact priority for serial forking (float value, higher is stronger) between -1.00 to 1.00']
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
    render_list => [qw/contact q/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;
# vim: set tabstop=4 expandtab:
