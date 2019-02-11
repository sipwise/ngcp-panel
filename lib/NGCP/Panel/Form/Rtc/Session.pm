package NGCP::Panel::Form::Rtc::Session;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

has_field 'subscriber_id' => (
    type => 'PosInteger',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The ID of the rtc session subscriber']
    },
);

has_field 'rtc_app_name' => (
    type => 'Text',
    required => 0,
    label => 'RTC application',
    maxlength => 255,
    element_attr => {
        rel => ['tooltip'],
        title => ['Rtc application name']
    },
);

1;
# vim: set tabstop=4 expandtab:
