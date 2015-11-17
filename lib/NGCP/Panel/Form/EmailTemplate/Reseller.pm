package NGCP::Panel::Form::EmailTemplate::Reseller;

use HTML::FormHandler::Moose;
use parent 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'name' => (
    type => 'Text',
    label => 'Name',
    required => 1,
    maxlength => 255,
);

has_field 'from_email' => (
    type => 'Email',
    label => 'From Email Address',
    required => 1,
);

has_field 'subject' => (
    type => 'Text',
    label => 'Subject',
    required => 1,
    maxlength => 255,
);

has_field 'body' => (
    type => 'TextArea',
    required => 1,
    label => 'Body Template',
    cols => 200,
    rows => 10,
    maxlength => '67108864', # 64MB
    element_class => [qw/ngcp-autoconf-area/],
    default =>
'Dear Customer,

A new subscriber [% subscriber %] has been created for you.

Please go to [% url %] to set your password and log into your self-care interface.

Your faithful Sipwise system

-- 
This is an automatically generated message. Do not reply. '
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
    render_list => [qw/name from_email subject body/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;

# vim: set tabstop=4 expandtab:
