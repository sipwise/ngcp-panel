package NGCP::Panel::Form::ProfilePackage::Admin;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::ProfilePackage::Reseller';
use Moose::Util::TypeConstraints;

has_field 'reseller' => (
    type => '+NGCP::Panel::Field::Reseller',
    #validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The reseller id to assign this profile package to.']
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/id
                    reseller
                    name
                    description
                    status
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
                    topup_profiles
                    topup_profiles_add/],
);

1;
# vim: set tabstop=4 expandtab:
