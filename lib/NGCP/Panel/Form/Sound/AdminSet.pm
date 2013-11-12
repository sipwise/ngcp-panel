package NGCP::Panel::Form::Sound::AdminSet;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Sound::ResellerSet';
use Moose::Util::TypeConstraints;

has_field 'reseller' => (
    type => '+NGCP::Panel::Field::Reseller',
    not_nullable => 1,
);

has_field 'contract' => (
    type => '+NGCP::Panel::Field::CustomerContract',
    label => 'Customer',
    not_nullable => 0,
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/reseller contract name description contract_default/],
);

1;

# vim: set tabstop=4 expandtab:
