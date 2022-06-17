package NGCP::Panel::Form::BillingProfile::Reseller;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;

use Storable qw();
use NGCP::Panel::Utils::Billing qw();

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
        title => ['A human readable profile name.']
    },
);

has_field 'handle' => (
    type => 'Text',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['A unique identifier string (only alphanumeric chars and _).']
    },
);

has_field 'ignore_domain' => (
    type => 'Boolean',
    default => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Ignore SIP domain part when matching fees.']
    },
);

has_field 'prepaid' => (
    type => 'Boolean',
    default => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Whether customers using this profile are handled prepaid.']
    },
);

has_field 'prepaid_library' => (
    type => 'Select',
    options => [
        { value => 'libswrate', label => 'libswrate' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['Which prepaid rating library to use.']
    },
);

has_field 'advice_of_charge' => (
    type => 'Boolean',
    default => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Enable Advice of Charge support for the billing profile.']
    },
);

has_field 'interval_charge' => (
    type => 'Money',
    element_attr => {
        rel => ['tooltip'],
        #title => ['The base fee charged per billing interval (a monthly fixed fee, e.g. 10) in Euro/Dollars/etc. This fee can be used on the invoice.'] #cents???
        title => ['The base fee charged per billing interval (a monthly fixed fee, e.g. 100) in cents. This fee can be used on the invoice.'] #cents???
    },
    default => '0',
);

has_field 'interval_free_time' => (
    type => 'Integer',
    element_attr => {
        rel => ['tooltip'],
        title => ['The included free calling time per billing interval (in seconds, e.g. 60000 for 1000 free minutes).']
    },
    default => '0',
);

has_field 'interval_free_cash' => (
    type => 'Money',
    element_attr => {
        rel => ['tooltip'],
        #title => ['The included free money per billing interval (in Euro, Dollars etc., e.g. 10).'] #cents???
        title => ['The included free money per billing interval (in cents, e.g. 10000).']
    },
    default => '0',
);

has_field 'fraud_interval_limit' => (
    type => 'Integer',
    label => 'Fraud Monthly Limit',
    element_attr => {
        rel => ['tooltip'],
        title => ['The fraud detection threshold per month (in cents, e.g. 10000).']
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
        { value => 5, label => 'ported (call forwarding only)' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['Options to lock customer if the monthly limit is exceeded.']
    },
);

has_field 'fraud_interval_notify' => (
    type => '+NGCP::Panel::Field::EmailList',
    label => 'Fraud Monthly Notify',
    maxlength => 255,
    element_attr => {
        rel => ['tooltip'],
        title => ['Comma-Separated list of Email addresses to send notifications when tresholds are exceeded.']
    },
);

has_field 'fraud_daily_limit' => (
    type => 'Integer',
    element_attr => {
        rel => ['tooltip'],
        title => ['The fraud detection threshold per day (in cents, e.g. 1000).']
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
        { value => 5, label => 'ported (call forwarding only)' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['Options to lock customer if the daily limit is exceeded.']
    },
);

has_field 'fraud_daily_notify' => (
    type => '+NGCP::Panel::Field::EmailList',
    maxlength => 255,
    element_attr => {
        rel => ['tooltip'],
        title => ['Comma-Separated list of Email addresses to send notifications when tresholds are exceeded.']
    },
);

has_field 'fraud_use_reseller_rates' => (
    type => 'Boolean',
    default => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ["Use rates of the reseller's billing profile for fraud control."]
    },
);

has_field 'currency' => (
    type => 'Text',
    maxlength => 31,
    element_attr => {
        rel => ['tooltip'],
        title => ['The currency symbol or ISO code, used on invoices and webinterfaces.']
    },
);

has_field 'status' => (
    type => 'Hidden',
    default => 'active',
    options => [
        { label => 'active', value => 'active' },
        { label => 'terminated', value => 'terminated' },
    ],
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
    render_list => [qw/handle name ignore_domain prepaid prepaid_library advice_of_charge interval_charge interval_free_time interval_free_cash
        fraud_interval_limit fraud_interval_lock fraud_interval_notify
        fraud_daily_limit fraud_daily_lock fraud_daily_notify fraud_use_reseller_rates
        currency id
        status/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

sub validate_handle {
    my ($self, $field) = @_;

    unless($field->value =~ /^\w+$/) {
        my $err_msg = 'Only lower-case, upper-case, digits and _ allowed';
        $field->add_error($err_msg);
    }
}

sub update_fields {
#IMPORTANT! redefined sub update_fields with no super call disable call of the update_field_list and defaults methods
    my $self = shift;
    my $c = $self->ctx;
    return unless $c;
    if ($c->stash->{no_prepaid_billing_profile} && $self->field('prepaid')) {
        $self->field('prepaid')->inactive(1);
    }
}

sub validate {
    my ($self) = @_;
    my $c = $self->ctx;
    return unless $c;

    my $resource = Storable::dclone($self->values);
    if (defined $resource->{reseller}) {
        $resource->{reseller_id} = $resource->{reseller}{id};
        delete $resource->{reseller};
    } else {
        $resource->{reseller_id} = ($c->user->is_superuser ? undef : $c->user->reseller_id);
    }

    NGCP::Panel::Utils::Billing::check_profile_update_item($c,$resource,$c->stash->{profile_result},sub {
                my ($err,@fields) = @_;
                foreach my $field (@fields) {
                    $self->field($field)->add_error($err);
                }
            });

}

1;

# vim: set tabstop=4 expandtab:
