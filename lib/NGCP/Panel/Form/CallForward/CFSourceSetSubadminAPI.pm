package NGCP::Panel::Form::CallForward::CFSourceSetSubadminAPI;
use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::CallForward::CFSourceSetSubAPI';

has_field 'subscriber_id' => (
    type => 'PosInteger',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The subscriber id this source set belongs to. Defaults to own subscriber id if not given.']
    },
);

1;

# vim: set tabstop=4 expandtab:
