package NGCP::Panel::Form::ProfilePackage::PackageAPI;
use HTML::FormHandler::Moose;
use HTML::FormHandler::Widget::Block::Bootstrap;
use Moose::Util::TypeConstraints;
extends 'HTML::FormHandler';

has_field 'id' => (
    type => 'Hidden',
);

has_field 'reseller_id' => (
    type => 'PosInteger',
    #required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The reseller id this profile package belongs to.']
    },
);

has_field 'name' => (
    type => 'Text',
    required => 1,
    maxlength => 255,
    element_attr => {
        rel => ['tooltip'],
        title => ['The unique name of the profile package.']
    },
);

has_field 'description' => (
    type => 'Text',
    required => 1,
    maxlength => 255,
    element_attr => {
        rel => ['tooltip'],
        title => ['Arbitrary text.'],
    },
);

has_field 'status' => (
    type => 'Hidden',
    options => [
        { value => 'active', label => 'active' },
        { value => 'terminated', label => 'terminated' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['The status of this package. Only active profile packages can be assigned to customers.']
    },
);


has_field 'initial_balance' => (
    type => 'Money',
    element_attr => {
        rel => ['tooltip'],
        title => ['The initial balance (in the effective profile\'s currency) that will be set for the very first balance interval.']
    },
);

has_field 'initial_profiles' => (
    type => 'Repeatable',
    element_attr => {
        rel => ['tooltip'],
        title => ['An array of objects with keys "profile_id" and "network_id" to create profile mappings from when applying this profile package to a customer.']
    },
);

#has_field 'blocks.id' => (
#    type => 'Hidden',
#);

has_field 'initial_profiles.profile_id' => (
    type => 'PosInteger',
    required => 1,
    #element_attr => {
    #    rel => ['tooltip'],
    #    title => ['The billing profile id.']
    #},  
    label => 'Billing profile id',
);

has_field 'initial_profiles.network_id' => (
    type => 'PosInteger',
    required => 0,
    #element_attr => {
    #    rel => ['tooltip'],
    #    title => ['An optional billing network id.']
    #},        
    label => 'Optional billing network id',
);

has_field 'balance_interval_unit' => (
    type => 'Select',
    options => [
        { value => 'day', label => 'day' },
        { value => 'week', label => 'week' },
        { value => 'month', label => 'month' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['The temporal unit for the balance interval.']
    },
);

has_field 'balance_interval_value' => (
    type => 'PosInteger',
    element_attr => {
        rel => ['tooltip'],
        title => ['The balance interval in temporal units.']
    },
);

has_field 'balance_interval_start_mode' => (
    type => 'Select',
    options => [
        { value => 'create', label => 'upon customer creation' },
        { value => '1st', label => '1st day of month' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['This mode determines when balance intervals start.']
    },
);


has_field 'carry_over_mode' => (
    type => 'Select',
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

#has_field 'timely_carry_over_mode' => (
#    type => 'Select',
#    options => [
#        { value => 'carry_over', label => 'carry over' },
#        { value => 'discard', label => 'discard' },
#    ],
#    element_attr => {
#        rel => ['tooltip'],
#        title => ['Options to carry over the customer\'s balance when topped-up during a "timely" interval before the end of the balance interval.']
#    },
#);

has_field 'timely_duration_unit' => (
    type => 'Select',
    options => [
        { value => 'day', label => 'day' },
        { value => 'week', label => 'week' },
        { value => 'month', label => 'month' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['The temporal unit for the "timely" interval.']
    },
);

has_field 'timely_duration_value' => (
    type => 'PosInteger',
    element_attr => {
        rel => ['tooltip'],
        title => ['The "timely" interval in temporal units.']
    },
);

has_field 'notopup_discard_intervals' => (
    type => 'PosInteger',
    element_attr => {
        rel => ['tooltip'],
        title => ['The balance will be discarded if no top-up happened for the the given number of balance intervals.']
    },
);


has_field 'underrun_lock_threshold' => (
    type => 'PosInteger',
    element_attr => {
        rel => ['tooltip'],
        title => ['The threshold in cents for the underrun lock level to come into effect.']
    },
);

has_field 'underrun_lock_level' => (
    type => '+NGCP::Panel::Field::SubscriberLockSelect',
    #options => [
    #    { value => 0, label => 'none' },
    #    { value => 1, label => 'foreign calls' },
    #    { value => 2, label => 'all outgoing calls' },
    #    { value => 3, label => 'incoming and outgoing' },
    #    { value => 4, label => 'global (including CSC)' },
    #],
    element_attr => {
        rel => ['tooltip'],
        title => ['The lock level to set the customer\'s subscribers to in case the balance underruns "underrun_lock_threshold".']
    },
);

has_field 'underrun_profile_threshold' => (
    type => 'PosInteger',
    element_attr => {
        rel => ['tooltip'],
        title => ['The threshold in cents for underrun profiles to come into effect.']
    },
);

has_field 'underrun_profiles' => (
    type => 'Repeatable',
    element_attr => {
        rel => ['tooltip'],
        title => ['An array of objects with keys "profile_id" and "network_id" to create profile mappings from when the balance underruns the "underrun_profile_threshold" value.']
    },
);

#has_field 'blocks.id' => (
#    type => 'Hidden',
#);

has_field 'underrun_profiles.profile_id' => (
    type => 'PosInteger',
    required => 1,
    #element_attr => {
    #    rel => ['tooltip'],
    #    title => ['The billing profile id.']
    #},
    label => 'Billing profile id',
);

has_field 'underrun_profiles.network_id' => (
    type => 'PosInteger',
    required => 0,
    #element_attr => {
    #    rel => ['tooltip'],
    #    title => ['An optional billing network id.']
    #},    
    label => 'Optional billing network id',
);


has_field 'topup_lock_level' => (
    type => '+NGCP::Panel::Field::SubscriberLockSelect',
    #options => [
    #    { value => 0, label => 'none' },
    #    { value => 1, label => 'foreign calls' },
    #    { value => 2, label => 'all outgoing calls' },
    #    { value => 3, label => 'incoming and outgoing' },
    #    { value => 4, label => 'global (including CSC)' },
    #],
    element_attr => {
        rel => ['tooltip'],
        title => ['The lock level to reset the customer\'s subscribers to after a successful top-up (usually 0).']
    },
);

#has_field 'topup_profiles' => (
#    type => 'Repeatable',
#    element_attr => {
#        rel => ['tooltip'],
#        title => ['An array of objects with keys "amount" and "profiles", with "profiles" being an array of objects with keys "profile_id" and "network_id" to create profile mappings from when the customer top-ups the corresponding "amount".']
#    },
#);

##has_field 'blocks.id' => (
##    type => 'Hidden',
##);

#has_field 'topup_profiles.amount' => (
#    type => 'Money',
#    element_attr => {
#        rel => ['tooltip'],
#        title => ['The amount in the currency of the profile in effect.']
#    },
#);

#has_field 'topup_profiles.profiles' => (
#    type => 'Repeatable',
#    element_attr => {
#        rel => ['tooltip'],
#        title => ['An array of objects with keys keys "profile_id" and "network_id".']
#    },
#);

#has_field 'topup_profiles.profiles.profile_id' => (
#    type => 'PosInteger',
#    required => 1,
#    label => 'The billing profile id.',
#);

#has_field 'topup_profiles.profiles.network_id' => (
#    type => 'PosInteger',
#    required => 0,
#    label => 'An optional billing network id.',
#);

has_field 'topup_profiles' => (
    type => 'Repeatable',
    element_attr => {
        rel => ['tooltip'],
        title => ['An array of objects with keys "profile_id" and "network_id" to create profile mappings from when a customer top-ups with a voucher associated with this profile package.']
    },
);

#has_field 'blocks.id' => (
#    type => 'Hidden',
#);

has_field 'topup_profiles.profile_id' => (
    type => 'PosInteger',
    required => 1,
    #element_attr => {
    #    rel => ['tooltip'],
    #    title => ['The billing profile id.']
    #},    
    label => 'Billing profile id',
);

has_field 'topup_profiles.network_id' => (
    type => 'PosInteger',
    required => 0,
    #element_attr => {
    #    rel => ['tooltip'],
    #    title => ['An optional billing network id.']
    #},    
    label => 'Optional billing network id',
);

1;