package NGCP::Panel::Form::Rtc::AppsReseller;
use HTML::FormHandler::Moose;
use HTML::FormHandler::Widget::Block::Bootstrap;
extends 'HTML::FormHandler';

# with 'NGCP::Panel::Render::RepeatableJs';  # only used in API currently

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {return [qw/submitid fields actions/]}
sub build_form_element_class {return [qw(form-horizontal)]}

has_field 'rtc_user_id' => (
    # readonly
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['ID in the backend RTC API (readonly).'],
    },
);

has_field 'apps' => (
    type => 'Repeatable',
    required => 0, #1,
    setup_for_js => 1,
    do_wrapper => 1,
    do_label => 0,
    tags => { 
        controls_div => 1,
    },
    wrapper_class => [qw/hfh-rep/],
    element_attr => {
        rel => ['tooltip'],
        title => ['An array of objects with keys "name", "domain", "secret" and "api_key" to create RTC apps for this reseller'],
    },
);

has_field 'apps.domain' => (
    type => 'Text',
    element_attr => {
        rel => ['tooltip'],
        title => ['Domain where the cdk is included.'],
    },
);

has_field 'apps.name' => (
    type => 'Text',
    element_attr => {
        rel => ['tooltip'],
        title => ['Arbitrary text. Name of the app.'],
    },
);

has_field 'apps.secret' => (
    type => 'Text',
    element_attr => {
        rel => ['tooltip'],
        title => ['The secret (readonly).'],
    },
);

has_field 'apps.api_key' => (
    type => 'Text',
    element_attr => {
        rel => ['tooltip'],
        title => ['The API key (readonly).'],
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
    render_list => [qw/rtc_user_id apps/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;