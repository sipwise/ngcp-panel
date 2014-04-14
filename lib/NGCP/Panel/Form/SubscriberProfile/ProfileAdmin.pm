package NGCP::Panel::Form::SubscriberProfile::ProfileAdmin;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::SubscriberProfile::ProfileReseller';
use Moose::Util::TypeConstraints;

has_field 'catalog' => (
    type => '+NGCP::Panel::Field::SubscriberProfileCatalog',
    validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The subscriber profile catalog this profile belongs to.'],
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/catalog name description/],
);

1;

# vim: set tabstop=4 expandtab:
