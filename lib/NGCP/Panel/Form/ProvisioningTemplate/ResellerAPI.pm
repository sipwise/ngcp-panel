package NGCP::Panel::Form::ProvisioningTemplate::ResellerAPI;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use Storable qw();

has_field 'id' => (
    type => 'Hidden'
);

has_field 'name' => (
    type => 'Text',
    required => 1,
    maxlength => 255,
    element_attr => {
        rel => ['tooltip'],
        title => ['A unique template name.']
    },
);

has_field 'description' => (
    type => 'Text',
    label => 'Description',
    required => 1,
    maxlength => 255,
    element_attr => {
        rel => ['tooltip'],
        title => ['Arbitrary text.'],
    },
);

has_field 'lang' => (
    type => 'Select',
    label => 'Language',
    options => [
        { value => 'js', label => 'JavaScript' },
        { value => 'perl', label => 'Perl' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['Which scripting language used in the template.']
    },
);

has_field 'template' => (
    type => 'Compound',
    required => 1,
    label => 'Template',
    element_attr => {
        rel => ['tooltip'],
        title => ['The template definition.'],
    },
);

has_field 'create_timestamp' => (
    type => '+NGCP::Panel::Field::DateTime',
    required => 0,
    readonly => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The datetime (YYYY-MM-DD HH:mm:ss) of the creation.']
    },
);

has_field 'modify_timestamp' => (
    type => '+NGCP::Panel::Field::DateTime',
    required => 0,
    readonly => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The datetime (YYYY-MM-DD HH:mm:ss) of the modification.']
    },
);

1;
