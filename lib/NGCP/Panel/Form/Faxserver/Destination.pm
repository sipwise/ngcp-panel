package NGCP::Panel::Form::Faxserver::Destination;

use HTML::FormHandler::Moose;
use parent 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

with 'NGCP::Panel::Render::RepeatableJs';

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'destination' => (
    type => 'Repeatable',
    setup_for_js => 1,
    do_wrapper => 1,
    do_label => 0,
    tags => { 
        controls_div => 1,
    },
    wrapper_class => [qw/hfh-rep/],
);

has_field 'destination.id' => (
    type => 'Hidden',
);

has_field 'destination.destination' => (
    type => 'Text',
    label => 'Destination',
    required => 1,
    wrapper_class => [qw/hfh-rep-field/],
);

has_field 'destination.filetype' => (
    type => 'Select',
    options => [
        { label => 'TIFF', value => 'TIFF' },
        { label => 'PS', value => 'PS' },
        { label => 'PDF', value => 'PDF' },
        { label => 'PDF14', value => 'PDF14' },
    ],
    label => 'File Type',
    required => 1,
    wrapper_class => [qw/hfh-rep-field/],
);

has_field 'destination.cc' => (
    type => 'Boolean',
    label => 'Incoming Email as CC',
    default => 0,
    wrapper_class => [qw/hfh-rep-field/],
);

has_field 'destination.incoming' => (
    type => 'Boolean',
    label => 'Deliver Incoming Faxes',
    default => 1,
    wrapper_class => [qw/hfh-rep-field/],
);

has_field 'destination.outgoing' => (
    type => 'Boolean',
    label => 'Deliver Outgoing Faxes',
    default => 1,
    wrapper_class => [qw/hfh-rep-field/],
);

has_field 'destination.status' => (
    type => 'Boolean',
    label => 'Receive Reports',
    default => 1,
    wrapper_class => [qw/hfh-rep-field/],
);

has_field 'destination.rm' => (
    type => 'RmElement',
    value => 'Remove',
    element_class => [qw/btn btn-primary pull-right/],
);

has_field 'destination_add' => (
    type => 'AddElement',
    repeatable => 'destination',
    value => 'Add another destination',
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
    render_list => [qw/destination destination_add/ ],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;

# vim: set tabstop=4 expandtab:
