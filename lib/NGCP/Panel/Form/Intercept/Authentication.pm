package NGCP::Panel::Form::Intercept::Authentication;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

has_field 'username' => (
    type => 'Text',
    label => 'username',
    required => 1,
);

has_field 'password' => (
    type => 'Text',
    label => 'password',
    required => 1,
);

has_field 'type' => (
    type => 'Select',
    label => 'type',
    required => 1,
    options => [
        { value => 'admin', 'label' => 'admin' },
    ],
);

1;
# vim: set tabstop=4 expandtab:
