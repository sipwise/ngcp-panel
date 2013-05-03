package NGCP::Panel::Form::BillingProfile;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
sub build_render_list {[qw/fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'id' => (
    type => 'Hidden'
);

has_field 'name' => (
    type => 'Text',
    required => 1,
    maxlength => 31,
);

has_field 'interval_charge' => (
    type => 'Money',
);

has_field 'interval_free_time' => (
    type => 'Integer',
);

has_field 'interval_free_cash' => (
    type => 'Money',
);

has_field 'fraud_interval_limit' => (
    type => 'Integer',
    label => 'Fraud Monthly Limit',
);

has_field 'fraud_interval_lock' => (
    type => 'Select',
    label => 'Fraud Monthly Lock',
    options => [
        { value => 0, label => 'none' },
        { value => 1, label => 'foreign calls' },
        { value => 2, label => 'all outgoing calls' },
        { value => 3, label => 'incoming and outgoing' },
        { value => 4, label => 'global (including CSC)' },
    ],
);

has_field 'fraud_interval_notify' => (
    type => 'Text', #Email?
    label => 'Fraud Monthly Notify',
    maxlength => 255,
);

has_field 'fraud_daily_limit' => (
    type => 'Integer',
);

has_field 'fraud_daily_lock' => (
    type => 'Select',
    options => [
        { value => 0, label => 'none' },
        { value => 1, label => 'foreign calls' },
        { value => 2, label => 'all outgoing calls' },
        { value => 3, label => 'incoming and outgoing' },
        { value => 4, label => 'global (including CSC)' },
    ],
);

has_field 'fraud_daily_notify' => (
    type => 'Text', #Email?
    maxlength => 255,
);

has_field 'currency' => (
    type => 'Text',
    maxlength => 31,
);

has_field 'vat_rate' => (
    type => 'Integer',
    label => 'VAT Rate',
    range_start => 0,
    range_end => 100,
);

has_field 'vat_included' => (
    type => 'Boolean',
    label => 'VAT Included',
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
    render_list => [qw/name interval_charge interval_free_time interval_free_cash 
        fraud_interval_limit fraud_interval_lock fraud_interval_notify
        fraud_daily_limit fraud_daily_lock fraud_daily_notify
        currency vat_rate vat_included id/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;
# vim: set tabstop=4 expandtab:
