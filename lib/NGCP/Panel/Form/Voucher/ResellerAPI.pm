package NGCP::Panel::Form::Voucher::ResellerAPI;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
#use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'id' => (
    type => 'Hidden'
);

has_field 'code' => (
    type => 'Text',
    required => 1,
    maxlength => 128,
    element_attr => {
        rel => ['tooltip'],
        title => ['The voucher code.']
    },
);

has_field 'amount' => (
    type => 'Money',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The amount of the voucher in cents of Euro/USD/etc.']
    },
    default => '0',
);

has_field 'valid_until' => (
    type => '+NGCP::Panel::Field::DateTime',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The date until this voucher is valid (YYYY-MM-DD hh:mm:ss).']
    },
);

has_field 'customer' => (
    type => '+NGCP::Panel::Field::CustomerContract',
    element_attr => {
        rel => ['tooltip'],
        title => ['The customer contract this voucher can be used by (optional).']
    },
);

has_field 'package_id' => (
    type => 'PosInteger',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The package this voucher belongs to.']
    },
);

has_field 'package' => (
    type => '+NGCP::Panel::Field::ProfilePackage',
    #required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The profile package the customer will switch with the top-up.']
    },
);

sub validate_valid_until {
    my ($self, $field) = @_;

    unless($field->value =~ /^(\d{4})\-\d{2}\-\d{2}(T| )\d{2}:\d{2}:\d{2}(\+\d{2}:\d{2})?$/) {
        my $err_msg = 'Invalid date format, must be YYYY-MM-DD';
        $field->add_error($err_msg);
    }
    if(int($1) > 2037) {
        my $err_msg = 'Invalid date format, YYYY must not be greater than 2037';
        $field->add_error($err_msg);
    }
}

sub update_fields {
    my $self = shift;
    my $c = $self->ctx;
    return unless $c;

    unless($c->user->billing_data) {
        $self->field('code')->inactive(1);
    }
}

1
# vim: set tabstop=4 expandtab:
