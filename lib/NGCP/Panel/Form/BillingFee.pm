package NGCP::Panel::Form::BillingFee;

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

has_field 'source' => (
    type => 'Text', #Regexp
    maxlength => 255,
);

has_field 'destination' => (
    type => 'Text', #Regexp nonepty
    maxlength => 255,
    required => 1,
);

has_field 'direction' => (
    type => 'Select',
    options => [
        { value => 'in', label => 'inbound' },
        { value => 'out', label => 'outbound' },
    ],
);

has_field 'onpeak_init_rate' => (
    type => 'Float',
);

has_field 'onpeak_init_interval' => (
    type => 'Integer',
);

has_field 'onpeak_follow_rate' => (
    type => 'Float',
);

has_field 'onpeak_follow_interval' => (
    type => 'Integer',
);

has_field 'offpeak_init_rate' => (
    type => 'Float',
);

has_field 'offpeak_init_interval' => (
    type => 'Integer',
);

has_field 'offpeak_follow_rate' => (
    type => 'Float',
);

has_field 'offpeak_follow_interval' => (
    type => 'Integer',
);

has_field 'use_free_time' => (
    type => 'Boolean',
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
    render_list => [qw/id source destination direction
        onpeak_init_rate onpeak_init_interval onpeak_follow_rate
        onpeak_follow_interval offpeak_init_rate offpeak_init_interval
        offpeak_follow_rate offpeak_follow_interval use_free_time/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;
# vim: set tabstop=4 expandtab:
