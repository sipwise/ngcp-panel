package NGCP::Panel::Form::Contract::Basic;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

with 'NGCP::Panel::Render::RepeatableJs';

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'contact' => (
    type => '+NGCP::Panel::Field::Contact',
    label => 'Contact',
    validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The contact id this contract belongs to.']
    },
);

has_field 'billing_profiles' => (
    type => 'Repeatable',
    label => 'Billing Profiles',
    setup_for_js => 1,
    do_wrapper => 1,
    do_label => 1,
    required => 1,
    tags => {
        controls_div => 1,
    },
    wrapper_class => [qw/hfh-rep-block/],
    element_attr => {
        rel => ['tooltip'],
        title => ['The billing profile / billing network interval schedule used to charge this contract.']
    },
);

has_field 'billing_profiles.id' => (
    type => 'Hidden',
);

has_field 'billing_profiles.profile' => (
    type => '+NGCP::Panel::Field::BillingProfile',
    validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The billing profile id used to charge this contract.']
    },
);

has_field 'billing_profiles.start' => (
    type => '+NGCP::Panel::Field::DateTime',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The datetime (YYYY-MM-DD HH:mm:ss) when the billing profile gets active.']
    },
);

has_field 'billing_profiles.stop' => (
    type => '+NGCP::Panel::Field::DateTime',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The datetime (YYYY-MM-DD HH:mm:ss) when the billing profile is revoked.']
    },
);

has_field 'billing_profiles.rm' => (
    type => 'RmElement',
    value => 'Remove Profile',
    order => 100,
    element_class => [qw/btn btn-primary pull-right/],
);

has_field 'profile_add' => (
    type => 'AddElement',
    repeatable => 'billing_profiles',
    value => 'Add Profile',
    element_class => [qw/btn btn-primary pull-right/],
);



has_field 'status' => (
    type => 'Select',
    required => 1,
    label => 'Status',
    options => [ 
        { label => 'active', value => 'active' },
        { label => 'pending', value => 'pending' },
        { label => 'locked', value => 'locked' },
        { label => 'terminated', value => 'terminated' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['The status of the contract.']
    },
);

has_field 'external_id' => (
    type => 'Text',
    label => 'External #',
    required => 0,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['An external id, e.g. provided by a 3rd party provisioning'] 
    },
);

has_field 'subscriber_email_template' => (
    type => '+NGCP::Panel::Field::EmailTemplate',
    label => 'Subscriber Creation Email Template',
    do_label => 1,
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The email template used to notify users about subscriber creation.']
    },
);

has_field 'passreset_email_template' => (
    type => '+NGCP::Panel::Field::EmailTemplate',
    label => 'Password Reset Email Template',
    do_label => 1,
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The email template used to notify users about password reset.']
    },
);

has_field 'invoice_email_template' => (
    type => '+NGCP::Panel::Field::EmailTemplate',
    label => 'Invoice Email Template',
    do_label => 1,
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The email template used to notify users about invoice.']
    },
);
has_field 'invoice_template' => (
    type => '+NGCP::Panel::Field::InvoiceTemplate',
    label => 'Invoice Template',
    do_label => 1,
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The invoice template for invoice generation. If none is assigned, no invoice will be generated for this customer.']
    },
);

has_field 'vat_rate' => (
    type => 'Integer',
    label => 'VAT Rate',
    range_start => 0,
    range_end => 100,
    default => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The VAT rate in percentage (e.g. 20).']
    },
);

has_field 'add_vat' => (
    type => 'Boolean',
    label => 'Charge VAT',
    element_attr => {
        rel => ['tooltip'],
        title => ['Whether to charge VAT in invoices.']
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
    render_list => [qw/contact billing_profiles profile_add status external_id subscriber_email_template passreset_email_template invoice_email_template invoice_template vat_rate add_vat/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

sub update_fields {
    my $self = shift;
    my $c = $self->ctx;
    return unless $c;

    foreach my $field(qw/subscriber_email_template passreset_email_template invoice_email_template/) {
        my $email = $self->field($field);
        if($email && $c->stash->{contract}) {
            $email->field('id')->ajax_src(
                $c->uri_for_action('/emailtemplate/tmpl_ajax_reseller', [$c->stash->{contract}->contact->reseller_id])->as_string
            );
        }
    }
}

1;
# vim: set tabstop=4 expandtab:
