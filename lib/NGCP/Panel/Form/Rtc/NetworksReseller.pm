package NGCP::Panel::Form::Rtc::NetworksReseller;
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

has_field 'networks' => (
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
        title => ['An array of objects with keys "config", "connector" and "tag" to create RTC networks for this reseller'],
    },
);
# webrtc, conference, xmpp-connector, sip-connector, sipwise-connector
has_field 'networks.connector' => (
    type => 'Select',
    options => [
        { value => 'webrtc', label => 'webrtc' },
        { value => 'conference', label => 'conference' },
        { value => 'xmpp-connector', label => 'xmpp-connector' },
        { value => 'sip-connector', label => 'sip-connector' },
        { value => 'sipwise-connector', label => 'sipwise-connector' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['One of the available options. This defines, to which networks rtc subscribers will be able to connect to.'],
    },
);

has_field 'networks.tag' => (
    type => 'Text',
    element_attr => {
        rel => ['tooltip'],
        title => ['An arbitrary name, to address that network instance'],
    },
);

has_field 'networks.config' => (
    type => 'Compound',  # Text
    element_attr => {
        rel => ['tooltip'],
        title => ['An arbitrary hash of additional config contents; e.g. {"xms": false}'],
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
    render_list => [qw/rtc_user_id networks/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;