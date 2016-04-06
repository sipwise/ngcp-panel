package NGCP::Panel::Form::Contract::ProductSelect;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Contract::Customer';

has_field 'product' => (
    type => '+NGCP::Panel::Field::Product',
    label => 'Product',
    validate_when_empty => 1,
);

has_field 'max_subscribers' => (
    type => 'PosInteger',
    label => 'Max Subscribers',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Optionally set the maximum number of subscribers for this contract. Leave empty for unlimited.']
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/contact billing_profile_definition billing_profile billing_profiles profile_add profile_package product max_subscribers status external_id subscriber_email_template passreset_email_template invoice_email_template invoice_template vat_rate add_vat/],
);

sub validate {
    my $self = shift;

    my $product = $self->field('product');
    my $max_subscribers = $self->field('max_subscribers');
    my $c = $self->ctx;

    return unless $c;

    my $sipaccount = $c->schema('DB')->resultset('products')->find({class => 'sipaccount'});
    return unless $sipaccount;
    my $sipaccount_id = $sipaccount->id // 0;

    if($max_subscribers->value && $product->field('id')->value == $sipaccount_id) {
        $max_subscribers->add_error('Max Subscribers should not be set when the Product is "Basic SIP Account"');
    }
    return;
}

1;
# vim: set tabstop=4 expandtab:
