package NGCP::Panel::Form::CustomerMonthlyFraud;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Model::DBIC';

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'fraud_interval_limit' => (
    type => 'Integer',
    label => 'Monthly Fraud Limit',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['fraud detection threshold per month, specifying cents']
    },
);

has_field 'fraud_interval_lock' => (
    type => 'Select',
    label => 'Lock Level',
    options => [
        { value => 0, label => 'none' },
        { value => 1, label => 'foreign calls' },
        { value => 2, label => 'all outgoing calls' },
        { value => 3, label => 'incoming and outgoing' },
        { value => 4, label => 'global (including CSC)' },
        { value => 5, label => 'ported (call forwarding only)' },
    ],
);

has_field 'fraud_interval_notify' => (
    type => '+NGCP::Panel::Field::EmailList',
    label => 'Notify Emails',
    maxlength => 255,
    element_attr => {
        rel => ['tooltip'],
        title => ['where e-mail notifications are sent, a list of e-mail addreses separated by comma']
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
    render_list => [qw/fraud_interval_limit fraud_interval_lock fraud_interval_notify/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;

=head1 NAME

NGCP::Panel::Form::NCOSPattern

=head1 DESCRIPTION

Form to modify a billing.ncos_pattern_list row.

=head1 METHODS

=head1 AUTHOR

Gerhard Jungwirth

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
