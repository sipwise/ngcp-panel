package NGCP::Panel::Form::CallForward::CFDestinationSetSubadminAPI;
use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::CallForward::CFDestinationSetSubAPI';

has_field 'subscriber_id' => (
    type => 'PosInteger',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The subscriber id this destination set belongs to, or null to set it for own subscriber.']
    },
);

1;

# vim: set tabstop=4 expandtab:
