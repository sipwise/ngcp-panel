package NGCP::Panel::Form::Rtc::Sessions;
use HTML::FormHandler::Moose;
use HTML::FormHandler::Widget::Block::Bootstrap;
extends 'HTML::FormHandler';

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {return [qw/submitid fields actions/]}
sub build_form_element_class {return [qw(form-horizontal)]}

has_field 'id' => (
    type => 'Hidden',
);

has_field 'rtc_app_name' => (
    type => 'Text', # TODO: datatables
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['RTC app this session is associated with. Default app if empty.'],
    },
);

has_field 'rtc_browser_token' => (
    # readonly
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Token, that will be created. It can then be used with the cdk. (readonly).'],
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
    render_list => [qw/id rtc_app_name/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;