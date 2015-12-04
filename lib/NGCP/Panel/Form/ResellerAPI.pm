package NGCP::Panel::Form::ResellerAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Reseller';

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'enable_rtc' => (
    type => 'Boolean',
    required => 0,
    default => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Whether an RTC-entity should be created for this reseller.'],
    }
);

has_field 'rtc_networks' => (
    type => 'Multiple', # Select
    required => '0',
    widget => 'CheckboxGroup',
    options => [
        { value => 'sip', label => 'SIP Only' },
        { value => 'xmpp', label => 'XMPP Only' },
        { value => 'sipwise', label => 'SIP and XMPP' },
        { value => 'webrtc', label => 'WebRTC Only' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['The RTC networks that should be preinitialized for this reseller.'],
    }
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/contract name status enable_rtc rtc_networks/],
);

1;
# vim: set tabstop=4 expandtab:
