package NGCP::Panel::Field::PbxGroupAPI;
use HTML::FormHandler::Moose;

extends 'HTML::FormHandler::Field';

has_field 'dummy' => (
    type => 'Text',
    required => 0,
    label => 'PBX Group IDs',
    do_label => 1,
);

no Moose;
1;

# vim: set tabstop=4 expandtab:
