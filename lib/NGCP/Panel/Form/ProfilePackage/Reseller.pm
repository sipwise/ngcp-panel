package NGCP::Panel::Form::ProfilePackage::Reseller;
use HTML::FormHandler::Moose;
use HTML::FormHandler::Widget::Block::Bootstrap;
use Moose::Util::TypeConstraints;
extends 'HTML::FormHandler';

with 'NGCP::Panel::Render::RepeatableJs';

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'id' => (
    type => 'Hidden',
);

has_field 'name' => (
    type => 'Text',
    label => 'Profile Package Name',
    required => 1,
    maxlength => 255,
    element_attr => {
        rel => ['tooltip'],
        title => ['The name of the profile package.']
    },
);

has_field 'description' => (
    type => 'Text',
    label => 'Description',    
    required => 1,
    maxlength => 255,
    element_attr => {
        rel => ['tooltip'],
        title => ['Arbitrary text.'],
    },
);

#has_field 'status' => (
#    type => 'Hidden',
#    label => 'Status',    
#    options => [
#        { value => 'active', label => 'active' },
#        { value => 'terminated', label => 'terminated' },
#    ],
#    element_attr => {
#        rel => ['tooltip'],
#        title => ['The status of this package. Only active profile packages can be assigned to customers.']
#    },
#);


has_field 'initial_balance' => (
    type => 'Money',
    label => 'Initial Balance', 
    element_attr => {
        rel => ['tooltip'],
        title => ['The initial balance (in the effective profile\'s currency) that will be set for the very first balance interval.']
    },
    default => 0,
);

has_field 'initial_profiles' => (
    type => 'Repeatable',
    required => 0, #1,
    setup_for_js => 1,
    do_wrapper => 1,
    do_label => 0,
    tags => { 
        controls_div => 1,
    },
    wrapper_class => [qw/hfh-rep/],
    element_attr => {
        rel => ['tooltip'],
        title => ['An array of objects with keys "profile_id" and "network_id" to create profile mappings from when applying this profile package to a customer.']
    },
    deflate_value_method => \&_deflate_mappings,
    inflate_default_method => \&_inflate_mappings,    
);

#has_field 'blocks.id' => (
#    type => 'Hidden',
#);

has_field 'initial_profiles.row' => (
    type => '+NGCP::Panel::Field::ProfileNetwork',
    label => 'Initial Billing Profile/Network',
    do_label => 1,
    tags => {
        before_element => '<div class="ngcp-profile-network-row">',
        after_element => '</div>',
    },
);
has_field 'initial_profiles.rm' => (
    type => 'RmElement',
    value => 'Remove',
    element_class => [qw/btn btn-primary pull-right/],
);
has_field 'initial_profiles_add' => (
    type => 'AddElement',
    repeatable => 'initial_profiles',
    value => 'Add another initial billing profile/network',
    element_class => [qw/btn btn-primary pull-right/],
);


has_field 'balance_interval' => (
    type => '+NGCP::Panel::Field::Interval',
    #required => 1,
    label => 'Balance Interval', 
    do_label => 1,
    tags => {
        before_element => '<div class="ngcp-interval-row control-group">',
        after_element => '</div>',
    },
);

has_field 'balance_interval_start_mode' => (
    type => 'Select',
    label => 'Balance Interval Start',
    options => [
        { value => 'create', label => 'upon customer creation' },
        { value => '1st', label => '1st day of month' },
        { value => 'topup', label => 'restart interval upon top-up' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['This mode determines when balance intervals start.']
    },
);


has_field 'carry_over_mode' => (
    type => 'Select',
    label => 'Carry Over',
    options => [
        { value => 'carry_over', label => 'carry over' },
        { value => 'carry_over_timely', label => 'carry over only if topped-up timely' },
        { value => 'discard', label => 'discard' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['Options to carry over the customer\'s balance to the next balance interval.']
    },
);

has_field 'timely_duration' => (
    type => '+NGCP::Panel::Field::Interval',
    label => '"Timely" Duration', 
    do_label => 1,
    tags => {
        before_element => '<div class="ngcp-interval-row control-group">',
        after_element => '</div>',
    },
);

has_field 'notopup_discard_intervals' => (
    type => 'PosInteger',
    label => 'Discard balance after intervals', 
    element_attr => {
        rel => ['tooltip'],
        title => ['The balance will be discarded if no top-up happened for the the given number of balance intervals.']
    },
);


has_field 'underrun_lock_threshold' => (
    #type => 'PosInteger',
    type => 'Money',
    label => 'Underrun lock threshold', 
    element_attr => {
        rel => ['tooltip'],
        title => ['The balance threshold for the underrun lock level to come into effect.']
    },
);

has_field 'underrun_lock_level' => (
    type => '+NGCP::Panel::Field::SubscriberLockSelect',
    label => 'Underrun lock level', 
    element_attr => {
        rel => ['tooltip'],
        title => ['The lock level to set the customer\'s subscribers to in case the balance underruns "underrun_lock_threshold".']
    },
);

has_field 'underrun_profile_threshold' => (
    #type => 'PosInteger',
    type => 'Money',
    label => 'Underrun profile threshold', 
    element_attr => {
        rel => ['tooltip'],
        title => ['The balance threshold for underrun profiles to come into effect.']
    },
);

has_field 'underrun_profiles' => (
    type => 'Repeatable',
    required => 0,
    setup_for_js => 1,
    do_wrapper => 1,
    do_label => 0,
    tags => { 
        controls_div => 1,
    },
    wrapper_class => [qw/hfh-rep/],
    element_attr => {
        rel => ['tooltip'],
        title => ['An array of objects with keys "profile_id" and "network_id" to create profile mappings from when the balance underruns the "underrun_profile_threshold" value.']
    },
    deflate_value_method => \&_deflate_mappings,
    inflate_default_method => \&_inflate_mappings,      
);

#has_field 'blocks.id' => (
#    type => 'Hidden',
#);

has_field 'underrun_profiles.row' => (
    type => '+NGCP::Panel::Field::ProfileNetwork',
    label => 'Underrun Billing Profile/Network',
    do_label => 1,
    tags => {
        before_element => '<div class="ngcp-profile-network-row">',
        after_element => '</div>',
    },
);
has_field 'underrun_profiles.rm' => (
    type => 'RmElement',
    value => 'Remove',
    element_class => [qw/btn btn-primary pull-right/],
);
has_field 'underrun_profiles_add' => (
    type => 'AddElement',
    repeatable => 'underrun_profiles',
    value => 'Add another underrun billing profile/network',
    element_class => [qw/btn btn-primary pull-right/],
);

has_field 'topup_lock_level' => (
    type => '+NGCP::Panel::Field::SubscriberLockSelect',
    label => 'Top-up unlock',
    element_attr => {
        rel => ['tooltip'],
        title => ['The lock level to reset the customer\'s subscribers to after a successful top-up (usually 0).']
    },
);

has_field 'service_charge' => (
    type => 'Money',
    label => 'Service Charge', 
    element_attr => {
        rel => ['tooltip'],
        title => ['The service charge amount will be subtracted from the voucher amount.']
    },
    default => 0,
);

has_field 'topup_profiles' => (
    type => 'Repeatable',
    required => 0,
    setup_for_js => 1,
    do_wrapper => 1,
    do_label => 0,
    tags => { 
        controls_div => 1,
    },
    wrapper_class => [qw/hfh-rep/],
    element_attr => {
        rel => ['tooltip'],
        title => ['An array of objects with keys "profile_id" and "network_id" to create profile mappings from when a customer top-ups with a voucher associated with this profile package.']
    },      
    deflate_value_method => \&_deflate_mappings,
    inflate_default_method => \&_inflate_mappings,  
);

#has_field 'blocks.id' => (
#    type => 'Hidden',
#);

has_field 'topup_profiles.row' => (
    type => '+NGCP::Panel::Field::ProfileNetwork',
    label => 'Top-up Billing Profile/Network',
    do_label => 1,
    tags => {
        before_element => '<div class="ngcp-profile-network-row">',
        after_element => '</div>',
    },
);
has_field 'topup_profiles.rm' => (
    type => 'RmElement',
    value => 'Remove',
    element_class => [qw/btn btn-primary pull-right/],
);
has_field 'topup_profiles_add' => (
    type => 'AddElement',
    repeatable => 'topup_profiles',
    value => 'Add another top-up billing profile/network',
    element_class => [qw/btn btn-primary pull-right/],
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
    render_list => [qw/id
                    name
                    description
                    initial_balance
                    initial_profiles
                    initial_profiles_add
                    balance_interval
                    balance_interval_start_mode
                    carry_over_mode
                    timely_duration
                    notopup_discard_intervals
                    underrun_lock_threshold
                    underrun_lock_level
                    underrun_profile_threshold
                    underrun_profiles
                    underrun_profiles_add
                    topup_lock_level
                    service_charge
                    topup_profiles
                    topup_profiles_add/],
);                  #status

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

sub _deflate_mappings {
    my ($self,$value) = @_;
    my $mappings = Storable::dclone($value);
    foreach my $mapping (@$mappings) {
        $mapping->{network_id} = $mapping->{row}->{network_id};
        $mapping->{profile_id} = $mapping->{row}->{profile_id};
        $mapping->{discriminator} = NGCP::Panel::Utils::ProfilePackages::field_to_discriminator($self->accessor);
        delete $mapping->{row};
    }
    return $mappings;
}

sub _inflate_mappings {
    my ($field,$value) = @_;
    my @mappings = ();
    foreach my $mapping (@$value) {
        my %row = ();
        $row{network_id} = $mapping->{network_id};
        $row{profile_id} = $mapping->{profile_id};
        push(@mappings,{ row => \%row });
    }
    return (scalar @mappings == 0 ? undef : \@mappings);
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
    foreach(qw/balance_interval timely_duration/){
        $resource->{$_.'_unit'} = $resource->{$_}{unit} || undef;
        $resource->{$_.'_value'} = $resource->{$_}{value} || undef;
        delete $resource->{$_};
    }
    
    NGCP::Panel::Utils::ProfilePackages::check_balance_interval(
            c => $c,
            resource => $resource,
            err_code => sub {
                my ($err,@fields) = @_;
                foreach my $field (@fields) {
                    $self->field($field)->add_error($err);
                }
                return 1;
            });

    my $mappings_to_create = [];
    NGCP::Panel::Utils::ProfilePackages::prepare_profile_package(
            c => $c,
            resource => $resource,
            mappings_to_create => $mappings_to_create,
            err_code => sub {
                my ($err,@fields) = @_;
                foreach my $field (@fields) {
                    $self->field($field)->add_error($err);
                }
                return 1;
            });
    #$resource->{mappings_to_create} = $mappings_to_create;
    #$self->_set_value($resource);
    
}

1;