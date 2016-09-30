package NGCP::Panel::Form::Subscriber::UpnRewriteSet;

use Sipwise::Base;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

with 'NGCP::Panel::Render::RepeatableJs';

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {return [qw/submitid fields actions/]}
sub build_form_element_class {return [qw/form-horizontal/] }

has_field 'new_cli' => (
    type => 'Text',
    required => 1,
    maxlength => 45,
    element_attr => {
        rel => ['tooltip'],
        title => ['The new CLI to be used as UPN, when one of the patterns matches.'],
    },
);

has_field 'upn_rewrite_sources' => (
    type => 'Repeatable',
    required => 1,
    setup_for_js => 1,
    do_wrapper => 1,
    do_label => 0,
    tags => {
        controls_div => 1,
    },
    wrapper_class => [qw/hfh-rep/],
    element_attr => {
        rel => ['tooltip'],
        title => ['An Array of source CLI patterns'],
    },
);

has_field 'subscriber_id' => (
    type => 'Hidden',
    required => 0,
);

has_field 'upn_rewrite_sources.id' => (
    type => 'Hidden',
);

has_field 'upn_rewrite_sources.pattern' => (
    type => '+NGCP::Panel::Field::Regexp',
    maxlength => 45,
    required => 1,
    wrapper_class => [qw/hfh-rep-field/],
);

has_field 'upn_rewrite_sources.rm' => (
    type => 'RmElement',
    value => 'Remove',
    element_class => [qw/btn btn-primary pull-right/],
);


has_field 'upn_rewrite_sources_add' => (
    type => 'AddElement',
    repeatable => 'upn_rewrite_sources',
    value => 'Add another Pattern',
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
    render_list => [qw/new_cli upn_rewrite_sources upn_rewrite_sources_add subscriber_id/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;
# vim: set tabstop=4 expandtab:
