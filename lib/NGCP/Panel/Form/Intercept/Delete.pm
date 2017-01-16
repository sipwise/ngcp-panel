package NGCP::Panel::Form::Intercept::Delete;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

has_field 'id' => (
    type => 'PosInteger',
    label => 'id',
    required => 1,
);

1;
# vim: set tabstop=4 expandtab:
