package NGCP::Panel::Form::EmergencyMapping::UploadAdmin;
use Sipwise::Base;
use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::EmergencyMapping::Upload';

use HTML::FormHandler::Widget::Block::Bootstrap;

has_field 'reseller' => (
    type => '+NGCP::Panel::Field::Reseller',
    validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The reseller id this CSV upload belongs to.']
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/upload_mapping reseller purge_existing/],
);

1;

# vim: set tabstop=4 expandtab:
