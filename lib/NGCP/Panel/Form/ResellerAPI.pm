package NGCP::Panel::Form::ResellerAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Reseller';

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/contract name status/],
);

1;
# vim: set tabstop=4 expandtab:
