package NGCP::Panel::Field::PbxGroupMemberAPI;
use HTML::FormHandler::Moose;

use parent 'HTML::FormHandler::Field';

has_field 'dummy' => (
    type => 'Text',
    required => 0,
    label => 'PBX Subscriber IDs',
    do_label => 1,
);

1;

# vim: set tabstop=4 expandtab:
