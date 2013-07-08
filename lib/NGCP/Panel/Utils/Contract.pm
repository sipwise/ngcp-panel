package NGCP::Panel::Utils::Contract;
use strict;
use warnings;

use Sipwise::Base;
use DBIx::Class::Exception;

sub create_contract_balance {
    my %params = @_;

    my $c = $params{c};
    my $contract = $params{contract};
    my $profile = $params{profile};

    my ($cash_balance, $cash_balance_interval,
        $free_time_balance, $free_time_balance_interval) = (0,0,0,0);

    # first, calculate start and end time of current billing profile
    # (we assume billing interval of 1 month)
    my $stime = DateTime->now->truncate(to => 'month');
    my $etime = $stime->clone->add(months => 1)->subtract(seconds => 1);

    # calculate free_time/cash ratio
    my $free_time = $profile->interval_free_time || 0;
    my $free_cash = $profile->interval_free_cash || 0;
    if($free_time or $free_cash) {
        $etime->add(seconds => 1);
        my $ctime = DateTime->now->truncate(to => 'day');
        my $ratio = ($etime->epoch - $ctime->epoch) / ($etime->epoch - $stime->epoch);
        
        $cash_balance = sprintf("%.4f", $free_cash * $ratio);
        $cash_balance_interval = 0;

        $free_time_balance = sprintf("%.0f", $free_time * $ratio);
        $free_time_balance_interval = 0;
        $etime->subtract(seconds => 1);
    }

    try {
        $c->model('DB')->resultset('contract_balances')->create({
            contract_id => $contract->id,
            cash_balance => $cash_balance,
            cash_balance_interval => $cash_balance_interval,
            free_time_balance => $free_time_balance,
            free_time_balance_interval => $free_time_balance_interval,
            start => $stime,
            end => $etime,
        });
    } catch($e) {
        $c->log->error("Creating contract balance failed: " . $e);
        $e->rethrow;
    }
}

1;

=head1 NAME

NGCP::Panel::Utils::Contract

=head1 DESCRIPTION

A temporary helper to manipulate Contract related data

=head1 METHODS

=head2 create_contract_balance

Parameters:
    c               The controller
    contract        The contract resultset
    profile         The billing_profile resultset

Creates a contract balance for the current month, if none exists yet
for this contract.

=head1 AUTHOR

Andreas Granig,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
# vim: set tabstop=4 expandtab:
