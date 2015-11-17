package NGCP::Panel::Field::PbxGroupAPI;
use HTML::FormHandler::Moose;

use parent 'HTML::FormHandler::Field';

has_field 'dummy' => (
    type => 'Text',
    required => 0,
    label => 'PBX Group IDs',
    do_label => 1,
);

1;

# vim: set tabstop=4 expandtab:
