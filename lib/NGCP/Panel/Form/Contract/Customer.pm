package NGCP::Panel::Form::Contract::Customer;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Contract::Base';

has_field 'contact' => (
    type => '+NGCP::Panel::Field::Contact',
    label => 'Contact',
    validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The contact id this contract belongs to.']
    },
);

has_field 'billing_profile_definition' => (
    type => 'Select',
    label => 'Set billing profiles',    
    options => [ 
        { value => 'id', label => 'single (actual billing mapping)' },
        { value => 'profiles', label => 'schedule (billing mapping intervals)' },
        { value => 'package', label => 'package (initial profiles of a profile package)' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['Choose to set a billing profile package or set billing profiles directly.'],
        javascript => ' onchange="switchBillingProfileDefinition(this);" ',        
    },
);

has_block 'all_mappings' => ( 
    type => '+NGCP::Panel::Block::Contract::ProfileNetworkMappings',
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
        title => ['The billing profile / billing network interval schedule used to charge this contract.']
    },
    deflate_value_method => \&_deflate_billing_mappings,
    inflate_default_method => \&_inflate_billing_mappings,
);

has_field 'billing_profiles.row' => (
    type => '+NGCP::Panel::Field::ProfileNetwork',
    label => 'Billing Profile/Network',
    do_label => 0,
    tags => {
        before_element => '<div class="ngcp-profile-network-row">',
       after_element => '</div>',
    },
);

has_field 'profile_package' => (
    type => '+NGCP::Panel::Field::ProfilePackage',
    #validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The profile package, whose initial profile/networks are to be used to charge this contract.']
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/contact billing_profile_definition billing_profile billing_profiles profile_add profile_package status external_id subscriber_email_template passreset_email_template invoice_email_template invoice_template vat_rate add_vat/],
);

sub _deflate_billing_mappings {
    my ($self,$value) = @_;
    my $mappings = Storable::dclone($value);
    foreach my $mapping (@$mappings) {
        $mapping->{network_id} = $mapping->{row}->{network_id};
        $mapping->{profile_id} = $mapping->{row}->{profile_id};
        $mapping->{start} = delete $mapping->{start};
        $mapping->{stop} = delete $mapping->{end};
        delete $mapping->{row};
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
        $row{row} = {};
        $row{row}->{network_id} = $mapping->{network_id};
        $row{row}->{profile_id} = $mapping->{billing_profile_id};
        push(@mappings,\%row);
    }
    return (scalar @mappings == 0 ? undef : \@mappings);
}

1;
# vim: set tabstop=4 expandtab: