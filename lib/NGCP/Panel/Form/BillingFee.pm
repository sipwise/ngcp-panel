package NGCP::Panel::Form::BillingFee;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;
use NGCP::Panel::Field::BillingZone;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'id' => (
    type => 'Hidden'
);

has_field 'source' => (
    type => '+NGCP::Panel::Field::Regexp',
    maxlength => 255,
    element_attr => {
        rel => ['tooltip'],
        title => ['string, empty or POSIX regular expression, e.g.: ^431.+$']
    },
);

has_field 'destination' => (
    type => '+NGCP::Panel::Field::Regexp',
    maxlength => 255,
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['string, POSIX regular expression, e.g.: ^431.+$']
    },
);

has_field 'direction' => (
    type => 'Select',
    options => [
        { value => 'in', label => 'inbound' },
        { value => 'out', label => 'outbound' },
    ],
);

has_field 'billing_zone' => (
    type => '+NGCP::Panel::Field::BillingZone',
    label => 'Zone',
    not_nullable => 1,
);

has_field 'onpeak_init_rate' => (
    type => 'Float',
    element_attr => {
        rel => ['tooltip'],
        title => ['double precision float, e.g.: 0.15']
    },
);

has_field 'onpeak_init_interval' => (
    type => 'Integer',
    element_attr => {
        rel => ['tooltip'],
        title => ['integer, e.g.: 60']
    },
);

has_field 'onpeak_follow_rate' => (
    type => 'Float',
    element_attr => {
        rel => ['tooltip'],
        title => ['double precision float, e.g.: 0.15']
    },
);

has_field 'onpeak_follow_interval' => (
    type => 'Integer',
    element_attr => {
        rel => ['tooltip'],
        title => ['integer, e.g.: 30']
    },
);

has_field 'offpeak_init_rate' => (
    type => 'Float',
    element_attr => {
        rel => ['tooltip'],
        title => ['double precision float, e.g.: 0.1']
    },
);

has_field 'offpeak_init_interval' => (
    type => 'Integer',
    element_attr => {
        rel => ['tooltip'],
        title => ['integer, e.g.: 60']
    },
);

has_field 'offpeak_follow_rate' => (
    type => 'Float',
    element_attr => {
        rel => ['tooltip'],
        title => ['double precision float, e.g.: 0.1']
    },
);

has_field 'offpeak_follow_interval' => (
    type => 'Integer',
    element_attr => {
        rel => ['tooltip'],
        title => ['integer, e.g.: 30']
    },
);

has_field 'use_free_time' => (
    type => 'Boolean',
    element_attr => {
        rel => ['tooltip'],
        title => ['free minutes may be used when calling this destination']
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
    render_list => [qw/id source destination direction billing_zone
        onpeak_init_rate onpeak_init_interval onpeak_follow_rate
        onpeak_follow_interval offpeak_init_rate offpeak_init_interval
        offpeak_follow_rate offpeak_follow_interval use_free_time
        /],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

sub custom_get_values {
    my ($self) = @_;
    my $hashvalues = {%{$self->value}}; #prevents sideeffects
    foreach my $val(values %$hashvalues) {
        $val = '' unless defined($val);
    }
    return $hashvalues;
}

sub custom_get_values_to_update {
    my ($self) = @_;
    my $hashvalues = $self->custom_get_values;
    $hashvalues->{billing_zone_id} = defined $hashvalues->{billing_zone}->{id} ?
        $hashvalues->{billing_zone}->{id}+0 :
        '';
    delete $hashvalues->{billing_zone};
    return $hashvalues;
}

1;
# vim: set tabstop=4 expandtab:
