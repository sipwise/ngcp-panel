package NGCP::Panel::Form::SubscriberProfile::CatalogAdmin;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::SubscriberProfile::CatalogReseller';
use Moose::Util::TypeConstraints;

has_field 'reseller' => (
    type => '+NGCP::Panel::Field::Reseller',
    validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The reseller this Subscriber Profile Catalog belongs to.'],
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/reseller name description/],
);

1;

# vim: set tabstop=4 expandtab:
