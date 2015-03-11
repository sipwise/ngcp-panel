package NGCP::Panel::Form::Sound::AdminSet;

use HTML::FormHandler::Moose;
use parent 'NGCP::Panel::Form::Sound::ResellerSet';
use Moose::Util::TypeConstraints;

has_field 'reseller' => (
    type => '+NGCP::Panel::Field::Reseller',
    validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The reseller this sound set belongs to.'],
    },
);

has_field 'contract' => (
    type => '+NGCP::Panel::Field::CustomerContract',
    label => 'Customer',
    validate_when_empty => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The contract this sound set belongs to. If set, the sound set becomes a customer sound set instead of a system sound set.'],
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/reseller contract name description contract_default/],
);

1;

# vim: set tabstop=4 expandtab:
