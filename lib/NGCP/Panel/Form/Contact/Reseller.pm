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
    label => 'Country',
    element_attr => {
        rel => ['tooltip'],
        title => ['The two-letter ISO 3166-1 country code of the contact (e.g. US or DE).']
    },
);

has_field 'iban' => (
    type => 'Text',
    maxlength => 34,
    label => 'IBAN',
    element_attr => {
        rel => ['tooltip'],
        title => ['The IBAN (International Bank Account Number) of the contact bank details.']
    },
);

has_field 'bic' => (
    type => 'Text',
    minlength => 8,
    maxlength => 11,
    label => 'BIC/SWIFT',
    element_attr => {
        rel => ['tooltip'],
        title => ['The BIC (Business Identifier Code) of the contact bank details.']
    },
);

has_field 'bankname' => (
    type => 'Text',
    maxlength => 255,
    label => 'Bank Name',
    element_attr => {
        rel => ['tooltip'],
        title => ['The bank name of the contact bank details.']
    },
);

has_field 'vatnum' => (
    type => 'Text',
    label => 'VAT Number',
    maxlength => 127,
    element_attr => {
        rel => ['tooltip'],
        title => ['The VAT number of the contact.']
    },
);

has_field 'comregnum' => (
    type => 'Text',
    label => 'Company Reg. Number',
    maxlength => 31,
    element_attr => {
        rel => ['tooltip'],
        title => ['The company registration number of the contact.']
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

has_field 'mobilenumber' => (
    type => 'Text',
    maxlength => 31,
    label => 'Mobile Number',
    element_attr => {
        rel => ['tooltip'],
        title => ['The mobile number of the contact.']
    },
);

has_field 'faxnumber' => (
    type => 'Text',
    maxlength => 31,
    label => 'Fax Number',
    element_attr => {
        rel => ['tooltip'],
        title => ['The fax number of the contact.']
    },
);

has_field 'gpp0' => (
    type => 'Text',
    maxlength => 255,
    label => 'General Purpose 0',
    element_attr => {
        rel => ['tooltip'],
        title => ['A general purpose field for free use.']
    },
);

has_field 'gpp1' => (
    type => 'Text',
    maxlength => 255,
    label => 'General Purpose 1',
    element_attr => {
        rel => ['tooltip'],
        title => ['A general purpose field for free use.']
    },
);

has_field 'gpp2' => (
    type => 'Text',
    maxlength => 255,
    label => 'General Purpose 2',
    element_attr => {
        rel => ['tooltip'],
        title => ['A general purpose field for free use.']
    },
);

has_field 'gpp3' => (
    type => 'Text',
    maxlength => 255,
    label => 'General Purpose 3',
    element_attr => {
        rel => ['tooltip'],
        title => ['A general purpose field for free use.']
    },
);

has_field 'gpp4' => (
    type => 'Text',
    maxlength => 255,
    label => 'General Purpose 4',
    element_attr => {
        rel => ['tooltip'],
        title => ['A general purpose field for free use.']
    },
);

has_field 'gpp5' => (
    type => 'Text',
    maxlength => 255,
    label => 'General Purpose 5',
    element_attr => {
        rel => ['tooltip'],
        title => ['A general purpose field for free use.']
    },
);

has_field 'gpp6' => (
    type => 'Text',
    maxlength => 255,
    label => 'General Purpose 6',
    element_attr => {
        rel => ['tooltip'],
        title => ['A general purpose field for free use.']
    },
);

has_field 'gpp7' => (
    type => 'Text',
    maxlength => 255,
    label => 'General Purpose 7',
    element_attr => {
        rel => ['tooltip'],
        title => ['A general purpose field for free use.']
    },
);

has_field 'gpp8' => (
    type => 'Text',
    maxlength => 255,
    label => 'General Purpose 8',
    element_attr => {
        rel => ['tooltip'],
        title => ['A general purpose field for free use.']
    },
);

has_field 'gpp9' => (
    type => 'Text',
    maxlength => 255,
    label => 'General Purpose 9',
    element_attr => {
        rel => ['tooltip'],
        title => ['A general purpose field for free use.']
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
        country iban bic bankname vatnum comregnum phonenumber mobilenumber faxnumber
        gpp0 gpp1 gpp2 gpp3 gpp4 gpp5 gpp6 gpp7 gpp8 gpp9
        /],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;
# vim: set tabstop=4 expandtab:
