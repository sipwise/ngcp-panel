package NGCP::Panel::Form::Topup::Log;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

has_field 'id' => (
    type => 'Hidden'
);

has_field 'username' => (
    type => 'Text',
    label => 'The user that attempted the topup.',
    required => 1,
);

has_field 'timestamp' => (
    type => '+NGCP::Panel::Field::DateTime',
    label => 'The timestamp of the topup attempt.',
    required => 1,
);

has_field 'type' => (
    type => 'Select',
    label => 'The top-up request type.',
    options => [
        { value => 'cash', label => 'Cash top-up' },
        { value => 'voucher', label => 'Voucher top-up' },
        { value => 'set_balance', label => 'Balance edited' },
    ],
    required => 1,
);

has_field 'outcome' => (
    type => 'Select',
    label => 'The top-up operation outcome.',
    options => [
        { value => 'ok', label => 'OK' },
        { value => 'failed', label => 'FAILED' },
    ],
    required => 1,
);

has_field 'message' => (
    type => 'Text',
    label => 'The top-up request response message (error reason).',
    required => 0,
);

has_field 'subscriber_id' => (
    type => 'PosInteger',
    label => 'The subscriber for which to topup the balance.',
    required => 0,
);

has_field 'contract_id' => (
    type => 'PosInteger',
    label => 'The subscriber\'s customer contract.',
    required => 0,
    element_attr => {
        expand => {
            class => 'NGCP::Panel::Role::API::Customers',
            allowed_roles => [qw(admin reseller)],
        },
    },
);

has_field 'amount' => (
    type => 'Money',
    required => 0,
    inflate_method => \&inflate_money,
    deflate_method => \&deflate_money,
    label => 'The top-up amount in Euro/USD/etc.',
);

has_field 'voucher_id' => (
    type => 'PosInteger',
    label => 'The voucher in case of a voucher top-up.',
    required => 0,
);

has_field 'voucher_id' => (
    type => 'PosInteger',
    label => 'The voucher in case of a voucher top-up.',
    required => 0,
);

has_field 'cash_balance_before' => (
    type => 'Money',
    required => 0,
    inflate_method => \&inflate_money,
    deflate_method => \&deflate_money,
    label => 'The contract\'s cash balance before the top-up in Euro/USD/etc.',
);

has_field 'cash_balance_after' => (
    type => 'Money',
    required => 0,
    inflate_method => \&inflate_money,
    deflate_method => \&deflate_money,
    label => 'The contract\'s cash balance after the top-up in Euro/USD/etc.',
);

has_field 'package_before_id' => (
    type => 'PosInteger',
    label => 'The contract\'s profile package before the top-up.',
    required => 0,
);

has_field 'package_after_id' => (
    type => 'PosInteger',
    label => 'The contract\'s profile package after the top-up.',
    required => 0,
);

has_field 'profile_before_id' => (
    type => 'PosInteger',
    label => 'The contract\'s actual billing profile before the top-up.',
    required => 0,
);

has_field 'profile_after_id' => (
    type => 'PosInteger',
    label => 'The contract\'s actual billing profile after the top-up.',
    required => 0,
);

has_field 'lock_level_before' => (
    type => 'Select',
    label => 'The contract\'s subscribers\' lock levels before the top-up.',
    options => [
        { value => '', label => '' },
        { value => '0', label => 'no lock (unlock)' },
        { value => '1', label => 'foreign' },
        { value => '2', label => 'outgoing' },
        { value => '3', label => 'all calls' },
        { value => '4', label => 'global' },
        { value => '5', label => 'ported (call forwarding only)' },
    ],
    deflate_value_method => \&_deflate_lock_level,
    inflate_default_method => \&_deflate_lock_level,
    required => 0,
);

has_field 'lock_level_after' => (
    type => 'Select',
    label => 'The contract\'s subscribers\' lock levels after the top-up.',
    options => [
        { value => '', label => '' },
        { value => '0', label => 'no lock (unlock)' },
        { value => '1', label => 'foreign' },
        { value => '2', label => 'outgoing' },
        { value => '3', label => 'all calls' },
        { value => '4', label => 'global' },
        { value => '5', label => 'ported (call forwarding only)' },
    ],
    deflate_value_method => \&_deflate_lock_level,
    inflate_default_method => \&_deflate_lock_level,
    required => 0,
);

has_field 'contract_balance_before_id' => (
    type => 'PosInteger',
    label => 'The contract\'s balance interval before the top-up.',
    required => 0,
);

has_field 'contract_balance_after_id' => (
    type => 'PosInteger',
    label => 'The contract\'s balance interval after the top-up.',
    required => 0,
);

has_field 'request_token' => (
    type => 'Text',
    label => 'The external ID to identify top-up request.',
    required => 0,
);

sub inflate_money {
    return $_[1] * 100.0 if defined $_[1];
}

sub deflate_money {
    return $_[1] / 100.0 if defined $_[1];
}

sub _deflate_lock_level {
    my ($self,$value) = @_;
    if (defined $value and length($value) == 0) {
        return;
    }
    return $value;
}
sub _inflate_lock_level {
    my ($self,$value) = @_;
    if (!defined $value) {
        return '';
    }
    return $value;
}

1;
