package NGCP::Panel::Form::Contact::Reseller;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'firstname' => (
    type => 'Text',
    label => 'First Name',
    maxlength => 127,
    element_attr => {
        rel => ['tooltip'],
        title => ['The given name of the contact.']
    },
);

has_field 'lastname' => (
    type => 'Text',
    label => 'Last Name',
    maxlength => 127,
    element_attr => {
        rel => ['tooltip'],
        title => ['The surname of the contact.']
    },
);

has_field 'company' => (
    type => 'Text',
    label => 'Company',
    maxlength => 127,
    element_attr => {
        rel => ['tooltip'],
        title => ['The company name of the contact.']
    },
);

has_field 'email' => (
    type => 'Email',
    required => 1,
    maxlength => 255,
    element_attr => {
        rel => ['tooltip'],
        title => ['The email address of the contact.']
    },
);

has_field 'street' => (
    type => 'Text',
    maxlength => 127,
    element_attr => {
        rel => ['tooltip'],
        title => ['The street name of the contact.']
    },
);

has_field 'postcode' => (
    type => 'Text',
    maxlength => 16,
    element_attr => {
        rel => ['tooltip'],
        title => ['The postal code of the contact.']
    },
);

has_field 'city' => (
    type => 'Text',
    maxlength => 127,
    element_attr => {
        rel => ['tooltip'],
        title => ['The city name of the contact.']
    },
);

has_field 'country' => (
    type => '+NGCP::Panel::Field::Country',
    validate_when_empty => 1,
    label => 'Country',
    element_attr => {
        rel => ['tooltip'],
        title => ['The two-letter ISO 3166-1 country code of the contact (e.g. US or DE).']
    },
);

has_field 'phonenumber' => (
    type => 'Text',
    maxlength => 31,
    label => 'Phone Number',
    element_attr => {
        rel => ['tooltip'],
        title => ['The phone number of the contact.']
    },
);

has_field 'save' => (
    type => 'Submit',
    value => 'Save',
    element_class => [qw/btn btn-primary/],
    label => '',
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/firstname lastname email company street postcode city
        country phonenumber/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;
# vim: set tabstop=4 expandtab:
