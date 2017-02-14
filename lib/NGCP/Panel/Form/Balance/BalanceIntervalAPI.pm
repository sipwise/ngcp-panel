package NGCP::Panel::Form::Balance::BalanceIntervalAPI;
use HTML::FormHandler::Moose;
use HTML::FormHandler::Widget::Block::Bootstrap;
extends 'HTML::FormHandler';

has_field 'id' => (
    type => 'Hidden',
);

has_field 'is_actual' => (
    type => 'Boolean',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Is this balance interval the actual one?']
    },
);

has_field 'start' => (
    type => '+NGCP::Panel::Field::DateTime',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The datetime (YYYY-MM-DD HH:mm:ss) pointing the first second belonging to the balance interval.']
    },
);

has_field 'stop' => (
    type => '+NGCP::Panel::Field::DateTime',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The datetime (YYYY-MM-DD HH:mm:ss) pointing the last second belonging to the balance interval.']
    },
);

has_field 'timely_topup_start' => (
    type => '+NGCP::Panel::Field::DateTime',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The datetime (YYYY-MM-DD HH:mm:ss) pointing the begin of the time range when top-ups will be considered \'timely\'.']
    },
);
has_field 'timely_topup_stop' => (
    type => '+NGCP::Panel::Field::DateTime',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The datetime (YYYY-MM-DD HH:mm:ss) pointing the end of the time range until top-ups will be considered \'timely\'.']
    },
);

has_field 'notopup_discard_expiry' => (
    type => '+NGCP::Panel::Field::DateTime',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The datetime (YYYY-MM-DD HH:mm:ss) pointing the deadline, when the cash balance will be discarded if no top-up was performed.']
    },
);

has_field 'billing_profile_id' => (
    type => 'PosInteger',
    #required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The id of the billing profile at the first second of the balance interval.']
    },
);

#we leave this out for now
#has_field 'invoice_id' => (
#    type => 'PosInteger',
#    #required => 1,
#    element_attr => {
#        rel => ['tooltip'],
#        title => ['The id of the invoice containing this invoice.']
#    },
#);

has_field 'cash_balance' => (
    type => 'Money',
    #label => 'Cash Balance',
    #required => 1,
    #inflate_method => sub { return $_[1] * 100 },
    #deflate_method => sub { return $_[1] / 100 },
    element_attr => {
        rel => ['tooltip'],
        title => ['The interval\'s cash balance of the contract in EUR/USD/etc.']
    },
);

has_field 'cash_debit' => (
    type => 'Money',
    #label => 'Cash Balance',
    #required => 1,
    #inflate_method => sub { return $_[1] * 100 },
    #deflate_method => sub { return $_[1] / 100 },
    element_attr => {
        rel => ['tooltip'],
        title => ['The amount spent during this interval in EUR/USD/etc.']
    },
);

has_field 'free_time_balance' => (
    type => 'Integer',
    #label => 'Free-Time Balance',
    #required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The interval\'s free-time balance of the contract in seconds.']
    },
);

has_field 'free_time_spent' => (
    type => 'Integer',
    #label => 'Free-Time Balance',
    #required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The free-time spent during this interval in seconds.']
    },
);

has_field 'topup_count' => (
    type => 'Integer',
    #label => 'Free-Time Balance',
    #required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The number of top-ups performed in this interval.']
    },
);

has_field 'timely_topup_count' => (
    type => 'Integer',
    #label => 'Free-Time Balance',
    #required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The number of top-ups performed in the \'timely\' span of this interval.']
    },
);

has_field 'underrun_profiles' => (
    type => '+NGCP::Panel::Field::DateTime',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The datetime (YYYY-MM-DD HH:mm:ss) when the cash balance underran the profile package\'s underrun_profile_threshold and underrun profiles were applied.']
    },
);

has_field 'underrun_lock' => (
    type => '+NGCP::Panel::Field::DateTime',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The datetime (YYYY-MM-DD HH:mm:ss) when the cash balance underran the profile package\'s underrun_lock_threshold and subscribers\' lock levels were set.']
    },
);

1;

# vim: set tabstop=4 expandtab:
