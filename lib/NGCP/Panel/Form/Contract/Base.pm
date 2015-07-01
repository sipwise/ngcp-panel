package NGCP::Panel::Form::Contract::Base;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;
use DateTime::Format::Strptime qw();

with 'NGCP::Panel::Render::RepeatableJs';

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'billing_profile_definition' => (
    type => 'Select',
    label => 'Set billing profiles',
    options => [ 
        { value => 'id', label => 'single (actual billing mapping)' },
        { value => 'profiles', label => 'schedule (billing mapping intervals)' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['Choose how to set billing profiles.'],
        javascript => ' onchange="switchBillingProfileDefinition(this);" ',
    },
);

has_field 'billing_profile' => (
    type => '+NGCP::Panel::Field::BillingProfile',
    element_attr => {
        rel => ['tooltip'],
        title => ['The billing profile used to charge this contract.']
    },
);

has_block 'all_mappings' => ( 
    type => '+NGCP::Panel::Block::Contract::ProfileMappings',
);

has_field 'billing_profiles' => (
    type => 'Repeatable',
    label => 'Billing Profiles',
    setup_for_js => 1,
    do_wrapper => 1,
    do_label => 1,
    tags => {
        controls_div => 1,
        before_element => '%all_mappings',
    },
    wrapper_class => [qw/hfh-rep-block/],
    element_attr => {
        rel => ['tooltip'],
        title => ['The billing profile schedule used to charge this contract.']
    },
    deflate_value_method => \&_deflate_billing_mappings,
    inflate_default_method => \&_inflate_billing_mappings,
);

has_field 'billing_profiles.start' => (
    type => '+NGCP::Panel::Field::DateTime',
    element_attr => {
        rel => ['tooltip'],
        title => ['The datetime (YYYY-MM-DD HH:mm:ss) when the billing profile gets active.']
    },
);

has_field 'billing_profiles.end' => (
    type => '+NGCP::Panel::Field::DateTime',
    element_attr => {
        rel => ['tooltip'],
        title => ['The datetime (YYYY-MM-DD HH:mm:ss) when the billing profile is revoked.']
    },
);

has_field 'billing_profiles.rm' => (
    type => 'RmElement',
    value => 'Remove',
    order => 100,
    element_class => [qw/btn btn-primary pull-right/],
);

has_field 'profile_add' => (
    type => 'AddElement',
    repeatable => 'billing_profiles',
    value => 'Add another profile mapping interval',
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



has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

sub _deflate_billing_mappings {
    my ($self,$value) = @_;
    my $mappings = Storable::dclone($value);
    foreach my $mapping (@$mappings) {
        $mapping->{profile_id} = $mapping->{profile}->{id};
        delete $mapping->{profile};
        $mapping->{network_id} = undef;
        delete $mapping->{network};
        $mapping->{start} = delete $mapping->{start};
        $mapping->{stop} = delete $mapping->{end};
    }
    return $mappings;
}

sub _inflate_billing_mappings {
    my ($field,$value) = @_;
    my @mappings = ();
    my $datetime_fmt = DateTime::Format::Strptime->new(
        pattern => '%F %T', 
    );   
    foreach my $mapping (@$value) {
        my %row = ();
        $row{start} = (defined $mapping->{start_date} ? $datetime_fmt->format_datetime($mapping->{start_date}) : undef);
        $row{end} = (defined $mapping->{end_date} ? $datetime_fmt->format_datetime($mapping->{end_date}) : undef);
        $row{network} = undef;
        $row{profile} = (defined $mapping->{billing_profile_id} ? { id => $mapping->{billing_profile_id} } : undef);
        push(@mappings,\%row);
    }
    return (scalar @mappings == 0 ? undef : \@mappings);
}

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

sub validate {
    my ($self) = @_;
    my $c = $self->ctx;
    return unless $c;
    
    my $resource = Storable::dclone($self->values);
    $resource->{contact_id} = $resource->{contact}->{id};
    delete $resource->{contact};

    $resource->{product_id} = $resource->{product}->{id} if exists $resource->{product};
    delete $resource->{product};
    
    $resource->{billing_profile_id} = $resource->{billing_profile}->{id};
    delete $resource->{billing_profile};
   
    $resource->{profile_package_id} = $resource->{profile_package}->{id} if exists $resource->{profile_package};
    delete $resource->{profile_package};
    
    my $old_resource = (exists $c->stash->{contract} ? { $c->stash->{contract}->get_inflated_columns } : undef);    
    
    my $mappings_to_create = [];
    NGCP::Panel::Utils::Contract::prepare_billing_mappings(
        c => $c,
        resource => $resource,
        old_resource => $old_resource,
        mappings_to_create => $mappings_to_create,
        billing_profile_field => 'billing_profile.id',
        billing_profiles_field => 'billing_profiles',
        profile_package_field => 'profile_package.id',
        billing_profile_definition_field => 'billing_profile_definition',
        err_code => sub {
            my ($err,@fields) = @_;
            foreach my $field (@fields) {
                $self->field($field)->add_error($err);
            }
        });    
    
}

1;
# vim: set tabstop=4 expandtab: