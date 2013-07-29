package NGCP::Panel::Form::BillingProfile_reseller;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'id' => (
    type => 'Hidden'
);

has_field 'name' => (
    type => 'Text',
    required => 1,
    maxlength => 31,
    element_attr => {
        rel => ['tooltip'],
        title => ['human readable profile name']
    },
);

has_field 'handle' => (
    type => 'Text',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['unique identifier string']
    },
);

has_field 'prepaid' => (
    type => 'Boolean',
    default => 0,
);

has_field 'interval_charge' => (
    type => 'Money',
    element_attr => {
        rel => ['tooltip'],
        title => ['base fee charged per billing interval, float, specifying Euro']
    },
    default => '0',
);

has_field 'interval_free_time' => (
    type => 'Integer',
    element_attr => {
        rel => ['tooltip'],
        title => ['included time per billing interval, integer, specifying seconds']
    },
    default => '0',
);

has_field 'interval_free_cash' => (
    type => 'Money',
    element_attr => {
        rel => ['tooltip'],
        title => ['included money per billing interval, float, specifying EUR, USD, etc.']
    },
    default => '0',
);

has_field 'fraud_interval_limit' => (
    type => 'Integer',
    label => 'Fraud Monthly Limit',
    element_attr => {
        rel => ['tooltip'],
        title => ['fraud detection threshold, per month, float, specifying EUR, USD, etc.']
    },
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
    element_attr => {
        rel => ['tooltip'],
        title => ['lock accounts if the monthly limit is exceeded']
    },
);

has_field 'fraud_interval_notify' => (
    type => '+NGCP::Panel::Field::EmailList',
    label => 'Fraud Monthly Notify',
    maxlength => 255,
    element_attr => {
        rel => ['tooltip'],
        title => ['where e-mail notifications are sent, a list of e-mail addreses separated by comma']
    },
);

has_field 'fraud_daily_limit' => (
    type => 'Integer',
    element_attr => {
        rel => ['tooltip'],
        title => ['fraud detection threshold, per day, float, specifying EUR, USD, etc.']
    },
    required => 0,
    default => undef,
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
    element_attr => {
        rel => ['tooltip'],
        title => ['lock accounts if the daily limit is exceeded']
    },
);

has_field 'fraud_daily_notify' => (
    type => '+NGCP::Panel::Field::EmailList',
    maxlength => 255,
    element_attr => {
        rel => ['tooltip'],
        title => ['where e-mail notifications are sent, a list of e-mail addreses separated by comma']
    },
);

has_field 'currency' => (
    type => 'Text',
    maxlength => 31,
    element_attr => {
        rel => ['tooltip'],
        title => ['currency symbol or ISO code, string, will be used on invoices and webinterfaces']
    },
);

has_field 'vat_rate' => (
    type => 'Integer',
    label => 'VAT Rate',
    range_start => 0,
    range_end => 100,
    element_attr => {
        rel => ['tooltip'],
        title => ['integer, specifying the percentage']
    },
);

has_field 'vat_included' => (
    type => 'Boolean',
    label => 'VAT Included',
    element_attr => {
        rel => ['tooltip'],
        title => ['check if fees are inclusive VAT']
    },
    default => 0,
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
    render_list => [qw/handle name prepaid interval_charge interval_free_time interval_free_cash 
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
