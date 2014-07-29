package NGCP::Panel::Form::CCMapEntriesAPI;
use HTML::FormHandler::Moose;
use Moose::Util::TypeConstraints;
extends 'HTML::FormHandler';

sub build_render_list {return [qw/fields actions/]}
sub build_form_element_class {return [qw(form-horizontal)]}

has_field 'subscriber_id' => (
    type => 'Repeatable',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The subscriber ID.'],
    },
);

has_field 'mappings' => (
    type => 'Repeatable',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['An Array of mappings, each entry containing the mandatory key "auth_key".'],
    },
);

has_field 'mappings.auth_key' => (
    type => 'Text',
);

has_block 'fields' => (
    tag => 'div',
    class => [qw(modal-body)],
    render_list => [qw(cfu cfb cft cfna)],
);

1;

# vim: set tabstop=4 expandtab:
