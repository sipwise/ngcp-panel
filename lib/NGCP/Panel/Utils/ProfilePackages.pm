package NGCP::Panel::Utils::ProfilePackages;
use strict;
use warnings;

#use TryCatch;
use NGCP::Panel::Utils::DateTime qw();
use NGCP::Panel::Utils::Subscriber qw();

use constant INITIAL_PROFILE_DISCRIMINATOR => 'initial';
use constant UNDERRUN_PROFILE_DISCRIMINATOR => 'underrun';
use constant TOPUP_PROFILE_DISCRIMINATOR => 'topup';

use constant _DISCRIMINATOR_MAP => { initial_profiles => INITIAL_PROFILE_DISCRIMINATOR,
                                     underrun_profiles => UNDERRUN_PROFILE_DISCRIMINATOR,
                                     topup_profiles => TOPUP_PROFILE_DISCRIMINATOR};

use constant _CARRY_OVER_TIMELY_MODE => 'carry_over_timely';
use constant _CARRY_OVER_MODE => 'carry_over';

use constant _DEFAULT_CARRY_OVER_MODE => _CARRY_OVER_MODE;

use constant _DEFAULT_INITIAL_BALANCE => 0.0;

use constant _TOPUP_START_MODE => 'topup';
use constant _1ST_START_MODE => '1st';
use constant _CREATE_START_MODE => 'create';
use constant _TOPUP_INTERVAL_START_MODE => 'topup_interval';

use constant _START_MODE_PRESERVE_EOM => { _TOPUP_START_MODE . '' => 0,
                                     _1ST_START_MODE . '' => 0,
                                     _CREATE_START_MODE . '' => 1};

use constant _DEFAULT_START_MODE => '1st';
use constant _DEFAULT_PROFILE_INTERVAL_UNIT => 'month';
use constant _DEFAULT_PROFILE_INTERVAL_COUNT => 1;
use constant _DEFAULT_PROFILE_FREE_TIME => 0;
use constant _DEFAULT_PROFILE_FREE_CASH => 0.0;

#use constant _DEFAULT_NOTOPUP_DISCARD_INTERVALS => undef;
use constant ENABLE_PROFILE_PACKAGES => 1;
use constant _ENABLE_UNDERRUN_PROFILES => 1;
use constant _ENABLE_UNDERRUN_LOCK => 1;

sub get_contract_balance {
    my %params = @_;
    my($c,$contract,$now,$schema,$stime,$etime) = @params{qw/c contract now schema stime etime/};
    
    #$schema //= $c->model('DB');
    $now //= NGCP::Panel::Utils::DateTime::current_local;
    
    my $balance = catchup_contract_balances(c => $c, contract => $contract, now => $now);
    
    if (defined $stime || defined $etime) { #supported for backward compat only
        $balance = $contract->contract_balances->search({
            start => { '>=' => $stime },
            end => { '<=' => $etime },
        },{ order_by => { '-desc' => 'end'},})->first;
    }
    return $balance;

}

sub resize_actual_contract_balance {
    my %params = @_;
    my($c,$contract,$old_package,$actual_balance,$is_topup,$topup_amount,$now,$schema,$profiles_added) = @params{qw/c contract old_package balance is_topup topup_amount now schema profiles_added/};

    $schema //= $c->model('DB');
    $contract = lock_contracts(schema => $schema, contract_id => $contract->id);
    $is_topup //= 0;
    $topup_amount //= 0.0;
    $profiles_added //= 0;

    return $actual_balance unless defined $contract->contact->reseller_id;
    
    $now //= $contract->modify_timestamp;
    my $new_package = $contract->profile_package;
    my ($old_start_mode,$new_start_mode);
    my ($underrun_profile_threshold,$underrun_lock_threshold);
    
    my $create_next_balance = 0;
    if (defined $old_package && !defined $new_package) {
        $old_start_mode = $old_package->balance_interval_start_mode if $old_package->balance_interval_start_mode ne _DEFAULT_START_MODE;
        $new_start_mode = _DEFAULT_START_MODE;
    } elsif (!defined $old_package && defined $new_package) {
        $old_start_mode = _DEFAULT_START_MODE;
        $new_start_mode = $new_package->balance_interval_start_mode if $new_package->balance_interval_start_mode ne _DEFAULT_START_MODE;
        $create_next_balance = (_TOPUP_START_MODE eq $new_package->balance_interval_start_mode ||
            _TOPUP_INTERVAL_START_MODE eq $new_package->balance_interval_start_mode) && $is_topup;
        $underrun_profile_threshold = $new_package->underrun_profile_threshold;
        $underrun_lock_threshold = $new_package->underrun_lock_threshold;
    } elsif (defined $old_package && defined $new_package) {
        if ($old_package->balance_interval_start_mode ne $new_package->balance_interval_start_mode) {
            $old_start_mode = $old_package->balance_interval_start_mode;
            $new_start_mode = $new_package->balance_interval_start_mode;
            $create_next_balance = (_TOPUP_START_MODE eq $new_package->balance_interval_start_mode ||
               _TOPUP_INTERVAL_START_MODE eq $new_package->balance_interval_start_mode) && $is_topup;
        } elsif (_TOPUP_START_MODE eq $new_package->balance_interval_start_mode && $is_topup) {
            $old_start_mode = _TOPUP_START_MODE;
            $new_start_mode = _TOPUP_START_MODE;
            $create_next_balance = 1;
        } elsif (_TOPUP_INTERVAL_START_MODE eq $new_package->balance_interval_start_mode && $is_topup
                 && NGCP::Panel::Utils::DateTime::is_infinite_future($actual_balance->end)) {
            $old_start_mode = _TOPUP_INTERVAL_START_MODE;
            $new_start_mode = _TOPUP_INTERVAL_START_MODE;
            $create_next_balance = 1;
        }
        
        if ((!defined $old_package->underrun_profile_threshold && defined $new_package->underrun_profile_threshold)
            || (defined $old_package->underrun_profile_threshold && defined $new_package->underrun_profile_threshold
                && ($new_package->underrun_profile_threshold > $old_package->underrun_profile_threshold || $profiles_added > 0))) {
            $underrun_profile_threshold = $new_package->underrun_profile_threshold;
        }
        if ((!defined $old_package->underrun_lock_threshold && defined $new_package->underrun_lock_threshold)
            || (defined $old_package->underrun_lock_threshold && defined $new_package->underrun_lock_threshold
                && ($new_package->underrun_lock_threshold > $old_package->underrun_lock_threshold || $profiles_added > 0))) {
            $underrun_lock_threshold = $new_package->underrun_lock_threshold;
        }
    }
    
    if ($actual_balance->start < $now) {
        if ($old_start_mode && $new_start_mode) {
            my $end_of_resized_interval = _get_resized_interval_end(ctime => $now,
                                                                    create_timestamp => $contract->create_timestamp // $contract->modify_timestamp,
                                                                    start_mode => $new_start_mode,
                                                                    is_topup => $is_topup);
            my $resized_balance_values = _get_resized_balance_values(schema => $schema,
                                                                    balance => $actual_balance,
                                                                    #old_start_mode => $old_start_mode,
                                                                    #new_start_mode => $new_start_mode,
                                                                    etime => $end_of_resized_interval);
    
            $actual_balance->update({
                end => $end_of_resized_interval,
                @$resized_balance_values,                  
            });
            $actual_balance->discard_changes();
            if ($create_next_balance) {
                $actual_balance = catchup_contract_balances(c => $c,
                        contract => $contract,
                        old_package => $new_package, #$old_package,
                        now => $end_of_resized_interval->clone->add(seconds => 1),
                        #suppress_underrun => 1,
                        topup_amount => $topup_amount,
                        profiles_added => $profiles_added,
                    );
                return $actual_balance;
            }
        }

        #underruns due to increased thresholds:
        my $update = {};
        if (_ENABLE_UNDERRUN_LOCK && defined $underrun_lock_threshold && ($actual_balance->cash_balance + $topup_amount) < $underrun_lock_threshold) {
            if (defined $new_package->underrun_lock_level) {
                set_subscriber_lock_level(c => $c, contract => $contract, lock_level => $new_package->underrun_lock_level);
                $update->{underrun_lock} = $now;
            }
        }        
        if (_ENABLE_UNDERRUN_PROFILES && defined $underrun_profile_threshold && ($actual_balance->cash_balance + $topup_amount) < $underrun_profile_threshold) {
            #my $bm_actual = get_actual_billing_mapping(schema => $schema, contract => $contract, now => $now); 
            if (add_profile_mappings(c => $c,
                    contract => $contract,
                    package => $new_package,
                    #bm_actual => $bm_actual,
                    stime => $now,
                    profiles => 'underrun_profiles',
                    now => $now) > 0) {
                $update->{underrun_profiles} = $now;
            }
        }
        if ((scalar keys %$update) > 0) {
            $actual_balance->update($update);
            $actual_balance->discard_changes();
        }

    } else {
        die("Another action finished meanwhile, please try again.");
    }
    
    return $actual_balance;
    
}

sub catchup_contract_balances {
    my %params = @_;
    my($c,$contract,$old_package,$now,$suppress_underrun,$topup_amount,$profiles_added) = @params{qw/c contract old_package now suppress_underrun topup_amount profiles_added/};
    
    my $schema = $c->model('DB');
    $contract = lock_contracts(schema => $schema, contract_id => $contract->id);
    $now //= $contract->modify_timestamp;
    $old_package = $contract->profile_package if !exists $params{old_package};
    my $contract_create = $contract->create_timestamp // $contract->modify_timestamp;
    $suppress_underrun //= 0;
    $topup_amount //= 0.0;
    $profiles_added //= 0;

    #$c->log->debug('catchup contract ' . $contract->id . ' contract_balances (now = ' . NGCP::Panel::Utils::DateTime::to_string($now) . ')') if $c;
    
    my ($start_mode,$interval_unit,$interval_value,$carry_over_mode,$has_package,$notopup_discard_intervals,$underrun_profile_threshold,$underrun_lock_threshold);
    
    if (defined $contract->contact->reseller_id && $old_package) {
        $start_mode = $old_package->balance_interval_start_mode;
        $interval_unit = $old_package->balance_interval_unit;
        $interval_value = $old_package->balance_interval_value;
        $carry_over_mode = $old_package->carry_over_mode;
        $notopup_discard_intervals = $old_package->notopup_discard_intervals;
        $underrun_profile_threshold = $old_package->underrun_profile_threshold;
        $underrun_lock_threshold = $old_package->underrun_lock_threshold;
        $has_package = 1;
    } else {
        $start_mode = _DEFAULT_START_MODE;
        $carry_over_mode = _DEFAULT_CARRY_OVER_MODE;
        $has_package = 0;
    }
    
    my ($underrun_lock_applied,$underrun_profiles_applied) = (0,0);
    my ($notopup_expiration,$is_notopup_expiration_calculated) = (undef,0);

    my $last_balance = $contract->contract_balances->search(undef,{ order_by => { '-desc' => 'end'},})->first;
    my $last_profile;
    while ($last_balance && !NGCP::Panel::Utils::DateTime::is_infinite_future($last_balance->end) && $last_balance->end < $now) { #comparison takes 100++ sec if loaded lastbalance contains +inf
        my $start_of_next_interval = $last_balance->end->clone->add(seconds => 1);

        if ($has_package && !$is_notopup_expiration_calculated) {
            #we have two queries here, so do it only if really creating contract_balances
            $notopup_expiration = _get_notopup_expiration(contract => $contract,
                notopup_discard_intervals => $notopup_discard_intervals,
                interval_unit => $interval_unit,
                start_mode => $start_mode);
            $is_notopup_expiration_calculated = 1;
        }
        
        my $bm_actual;
        unless ($last_profile) {
            $bm_actual = get_actual_billing_mapping(schema => $schema, contract => $contract, now => $last_balance->start);
            $last_profile = $bm_actual->billing_mappings->first->billing_profile;
        }
        my ($underrun_profiles_ts,$underrun_lock_ts) = (undef,undef);
PREPARE_BALANCE_CATCHUP:
        $bm_actual = get_actual_billing_mapping(schema => $schema, contract => $contract, now => $start_of_next_interval);
        my $profile = $bm_actual->billing_mappings->first->billing_profile;
        $interval_unit = $has_package ? $interval_unit : ($profile->interval_unit // _DEFAULT_PROFILE_INTERVAL_UNIT);
        $interval_value = $has_package ? $interval_value : ($profile->interval_count // _DEFAULT_PROFILE_INTERVAL_COUNT);
        
        my ($stime,$etime) = _get_balance_interval_start_end(
                                                      last_etime => $last_balance->end,
                                                      start_mode => $start_mode,
                                                      #now => $start_of_next_interval,
                                                      interval_unit => $interval_unit,
                                                      interval_value => $interval_value,
                                                      create => $contract_create);

        my $balance_values = _get_balance_values(schema => $schema,
            stime => $stime,
            etime => $etime,
            #start_mode => $start_mode,
            contract => $contract,
            profile => $profile,
            carry_over_mode => $carry_over_mode,
            last_balance => $last_balance,
            last_profile => $last_profile,
            notopup_expiration => $notopup_expiration,
        );

        if (_ENABLE_UNDERRUN_LOCK && !$suppress_underrun && !$underrun_lock_applied && defined $underrun_lock_threshold && $last_balance->cash_balance >= $underrun_lock_threshold && ({ @$balance_values }->{cash_balance} + $topup_amount) < $underrun_lock_threshold) {
            $underrun_lock_applied = 1;
            if (defined $old_package->underrun_lock_level) {
                set_subscriber_lock_level(c => $c, contract => $contract, lock_level => $old_package->underrun_lock_level);
                $underrun_lock_ts = $now;
            }
        }        
        if (_ENABLE_UNDERRUN_PROFILES && !$suppress_underrun && !$underrun_profiles_applied && defined $underrun_profile_threshold && ($profiles_added > 0 || $last_balance->cash_balance >= $underrun_profile_threshold) && ({ @$balance_values }->{cash_balance} + $topup_amount) < $underrun_profile_threshold) {
            $underrun_profiles_applied = 1;
            if (add_profile_mappings(c=> $c,
                    contract => $contract,
                    package => $old_package,
                    #bm_actual => $bm_actual,
                    stime => $start_of_next_interval,
                    profiles => 'underrun_profiles',
                    now => $now) > 0) {
                $underrun_profiles_ts = $now;
                goto PREPARE_BALANCE_CATCHUP;
            }
        }

        $last_profile = $profile;
        
        $last_balance = $schema->resultset('contract_balances')->create({
            contract_id => $contract->id,
            start => $stime,
            end => $etime,
            underrun_profiles => $underrun_profiles_ts,
            underrun_lock => $underrun_lock_ts,
            @$balance_values,
        });
        $last_balance->discard_changes();
    }

	# in case of "topup" or "topup_interval" start modes, the current interval end can be
	# infinite and no new contract balances are created. for this infinite end interval,
	# the interval start represents the time the last topup happened in case of "topup".
	# in case of "topup_interval", the interval start represents the contract creation.
	# the cash balance should be discarded when
	#  1. the current/call time is later than than $notopup_discard_intervals periods
	#  after the interval start, or
	#  2. we have the "carry_over_timely" mode, and the current/call time is beyond
	#  the timely end already
    if ($has_package && $last_balance && NGCP::Panel::Utils::DateTime::is_infinite_future($last_balance->end)) {
        $notopup_expiration = _get_notopup_expiration(contract => $contract,
            notopup_discard_intervals => $notopup_discard_intervals,
            interval_unit => $interval_unit,
            last_balance => $last_balance,
            start_mode => $start_mode);
        my $timely_end = (_CARRY_OVER_TIMELY_MODE eq $carry_over_mode ? _add_interval($last_balance->start,$interval_unit,$interval_value,undef)->subtract(seconds => 1) : undef);
        if ((defined $notopup_expiration && $now >= $notopup_expiration)
            || (defined $timely_end && $now > $timely_end)) {
            my $update = {
                cash_balance => 0
            };
            if (_ENABLE_UNDERRUN_LOCK && !$suppress_underrun && !$underrun_lock_applied && defined $underrun_lock_threshold && $last_balance->cash_balance >= $underrun_lock_threshold && ($update->{cash_balance} + $topup_amount) < $underrun_lock_threshold) {
                $underrun_lock_applied = 1;
                if (defined $old_package->underrun_lock_level) {
                    set_subscriber_lock_level(c => $c, contract => $contract, lock_level => $old_package->underrun_lock_level);
                    $update->{underrun_lock} = $now;
                }
            }        
            if (_ENABLE_UNDERRUN_PROFILES && !$suppress_underrun && !$underrun_profiles_applied && defined $underrun_profile_threshold && ($profiles_added > 0 || $last_balance->cash_balance >= $underrun_profile_threshold) && ($update->{cash_balance} + $topup_amount) < $underrun_profile_threshold) {
                $underrun_profiles_applied = 1;
                if (add_profile_mappings(c=> $c,
                        contract => $contract,
                        package => $old_package,
                        #bm_actual => $bm_actual,
                        stime => $now,
                        profiles => 'underrun_profiles',
                        now => $now) > 0) {
                    $update->{underrun_profiles} = $now;
                }
            }            
            $last_balance->update($update);
            $last_balance->discard_changes();
        }
    }
    
    return $last_balance;
    
}

sub topup_contract_balance {
    my %params = @_;
    my($c,$contract,$package,$voucher,$amount,$now,$schema) = @params{qw/c contract package voucher amount now schema/};
    
    $schema //= $c->model('DB');
    $contract = lock_contracts(schema => $schema, contract_id => $contract->id);
    $now //= NGCP::Panel::Utils::DateTime::current_local;
    
    my $voucher_package = ($voucher ? $voucher->profile_package : $package);
    my $old_package = $contract->profile_package;
    $package = $voucher_package // $old_package;
    my $topup_amount = ($voucher ? $voucher->amount : $amount) // 0.0;
    
    $voucher_package = undef unless ENABLE_PROFILE_PACKAGES;
    $package = undef unless ENABLE_PROFILE_PACKAGES;
    
    my $profiles_added = 0;
    if ($package) { #always apply (old or new) topup profiles
        $topup_amount -= $package->service_charge;
        
        #my $bm_actual = get_actual_billing_mapping(c => $c, contract => $contract, now => $now);
        $profiles_added = add_profile_mappings(c => $c,
            contract => $contract,
            package => $package,
            #bm_actual => $bm_actual,
            stime => $now,
            profiles => 'topup_profiles',
            now => $now);
    }
               
    if ($voucher_package && (!$old_package || $voucher_package->id != $old_package->id)) {
        $contract->update({ profile_package_id => $voucher_package->id,
                            #modify_timestamp => $now,
        });
        $contract->discard_changes();
    }

    my $balance = catchup_contract_balances(c => $c,
        contract => $contract,
        old_package => $old_package,
        now => $now);

    my ($is_timely,$timely_duration_unit,$timely_duration_value) = (0,undef,undef);
    if ($old_package
        && ($timely_duration_unit = $old_package->timely_duration_unit)
        && ($timely_duration_value = $old_package->timely_duration_value)) {
        my $timely_end;
        #if (_TOPUP_START_MODE ne $old_package->balance_interval_start_mode) {
        if (!NGCP::Panel::Utils::DateTime::is_infinite_future($balance->end)) {
            $timely_end = $balance->end;
        } else {
            $timely_end = _add_interval($balance->start,$old_package->balance_interval_unit,$old_package->balance_interval_value,
                        _START_MODE_PRESERVE_EOM->{$old_package->balance_interval_start_mode} ? $contract->create_timestamp // $contract->modify_timestamp : undef)->subtract(seconds => 1);
        }
        my $timely_start = _add_interval($timely_end,$timely_duration_unit,-1 * $timely_duration_value)->add(seconds => 1);
        $timely_start = $balance->start if $timely_start < $balance->start;
        
        $is_timely = ($now >= $timely_start && $now <= $timely_end ? 1 : 0);
    }
    
    $balance->update({ topup_count => $balance->topup_count + 1,
                       timely_topup_count => $balance->timely_topup_count + $is_timely});    
    
    $balance = resize_actual_contract_balance(c => $c,
        contract => $contract,
        old_package => $old_package,
        balance => $balance,
        now => $now,
        is_topup => 1,
        topup_amount => $topup_amount,
        profiles_added => $profiles_added,
    );            

    $balance->update({ cash_balance => $balance->cash_balance + $topup_amount }); #add in new interval
    $contract->discard_changes();
    
    if ($package) {
        set_subscriber_lock_level(c => $c, contract => $contract, lock_level => $package->topup_lock_level) if defined $package->topup_lock_level;
    }
    
    return $balance;
}

sub create_initial_contract_balances {
    my %params = @_;
    my($c,$contract,$now) = @params{qw/c contract now/};

    my $schema = $c->model('DB');
    $contract = lock_contracts(schema => $schema, contract_id => $contract->id);
    $now //= $contract->create_timestamp // $contract->modify_timestamp;
    
    my ($start_mode,$interval_unit,$interval_value,$initial_balance,$underrun_profile_threshold,$underrun_lock_threshold);
    
    my $package = $contract->profile_package;

    my ($underrun_lock_ts,$underrun_profiles_ts) = (undef,undef);
    my ($underrun_lock_applied,$underrun_profiles_applied) = (0,0);
PREPARE_BALANCE_INITIAL:
    my $bm_actual = get_actual_billing_mapping(schema => $schema, contract => $contract, now => $now);
    my $profile = $bm_actual->billing_mappings->first->billing_profile;
    if (defined $contract->contact->reseller_id && $package) {
        $start_mode = $package->balance_interval_start_mode;
        $interval_unit = $package->balance_interval_unit;
        $interval_value = $package->balance_interval_value;
        $initial_balance = $package->initial_balance; #euro
        $underrun_profile_threshold = $package->underrun_profile_threshold;
        $underrun_lock_threshold = $package->underrun_lock_threshold;
    } else {
        $start_mode = _DEFAULT_START_MODE;
        $interval_unit = $profile->interval_unit // _DEFAULT_PROFILE_INTERVAL_UNIT; #'month';
        $interval_value = $profile->interval_count // _DEFAULT_PROFILE_INTERVAL_COUNT; #1;
        $initial_balance = _DEFAULT_INITIAL_BALANCE;
    }

    my ($stime,$etime) = _get_balance_interval_start_end(
                                                      now => $now,
                                                      start_mode => $start_mode,
                                                      interval_unit => $interval_unit,
                                                      interval_value => $interval_value,
                                                      create => $contract->create_timestamp // $contract->modify_timestamp);
        
    my $balance_values = _get_balance_values(schema => $schema,
            stime => $stime,
            etime => $etime,
            #start_mode => $start_mode,
            now => $now,
            profile => $profile,
            initial_balance => $initial_balance, # * 100.0,
        );    

    if (_ENABLE_UNDERRUN_LOCK && !$underrun_lock_applied && defined $package && defined $underrun_lock_threshold && { @$balance_values }->{cash_balance} < $underrun_lock_threshold) {
        $underrun_lock_applied = 1;
        if (defined $package->underrun_lock_level) {
            set_subscriber_lock_level(c => $c, contract => $contract, lock_level => $package->underrun_lock_level);
            $underrun_lock_ts = $now;
        }
    }
    if (_ENABLE_UNDERRUN_PROFILES && !$underrun_profiles_applied && defined $package && defined $underrun_profile_threshold && { @$balance_values }->{cash_balance} < $underrun_profile_threshold) {
        $underrun_profiles_applied = 1;
        if (add_profile_mappings(c => $c,
                contract => $contract,
                package => $package,
                bm_actual => $bm_actual,
                stime => $now,
                profiles => 'underrun_profiles',
                now => $now) > 0) { #starting from now, not $stime, see prepare_billing_mappings
            $underrun_profiles_ts = $now;
            #$bm_actual = get_actual_billing_mapping(schema => $schema, contract => $contract, now => $now);
            goto PREPARE_BALANCE_INITIAL;
        }
    }

    my $balance = $schema->resultset('contract_balances')->create({
        contract_id => $contract->id,
        start => $stime,
        end => $etime,
        underrun_profiles => $underrun_profiles_ts,
        underrun_lock => $underrun_lock_ts,
        @$balance_values,
    });
    $balance->discard_changes();
    
    if ('hour' eq $interval_unit
        || 'day' eq $interval_unit
        || 'week' eq $interval_unit) {
        $balance = catchup_contract_balances(c => $c, contract => $contract, now => $now);
    }

    return $balance;
    
}

sub _get_resized_balance_values {
    my %params = @_;
    my ($c,$balance,$etime,$schema) = @params{qw/c balance etime schema/};
    
    $schema //= $c->model('DB');
    my ($cash_balance, $free_time_balance) = ($balance->cash_balance,$balance->free_time_balance);
    
    my $contract = $balance->contract;
    my $contract_create = $contract->create_timestamp // $contract->modify_timestamp;
    if ($balance->start <= $contract_create && (NGCP::Panel::Utils::DateTime::is_infinite_future($balance->end) || $balance->end >= $contract_create)) {
        my $bm = get_actual_billing_mapping(schema => $schema, contract => $contract, now => $contract_create); #now => $balance->start); #end); !?
        my $profile = $bm->billing_mappings->first->billing_profile;
        my $old_ratio = _get_free_ratio($contract_create,$balance->start,$balance->end);
        my $old_free_cash = $old_ratio * ($profile->interval_free_cash // _DEFAULT_PROFILE_FREE_CASH);
        my $old_free_time = $old_ratio * ($profile->interval_free_time // _DEFAULT_PROFILE_FREE_TIME);
        my $new_ratio = _get_free_ratio($contract_create,$balance->start,$etime);
        my $new_free_cash = $new_ratio * ($profile->interval_free_cash // _DEFAULT_PROFILE_FREE_CASH);
        my $new_free_time = $new_ratio * ($profile->interval_free_time // _DEFAULT_PROFILE_FREE_TIME);
        $cash_balance += $new_free_cash - $old_free_cash;
        #$cash_balance = 0.0 if $cash_balance < 0.0;
        $free_time_balance += $new_free_time - $old_free_time;
        #$free_time_balance = 0.0 if $free_time_balance < 0.0;
    }
    
    return [cash_balance => sprintf("%.4f",$cash_balance), free_time_balance => sprintf("%.0f",$free_time_balance)];
    
}

sub _get_balance_values {
    my %params = @_;
    my($c, $profile, $last_profile, $contract, $last_balance, $stime, $etime, $initial_balance, $carry_over_mode, $now, $notopup_expiration, $schema) = @params{qw/c profile last_profile contract last_balance stime etime initial_balance carry_over_mode now notopup_expiration schema/};    
    
    $schema //= $c->model('DB');
    $now //= $contract->create_timestamp // $contract->modify_timestamp;
    my ($cash_balance,$cash_balance_interval, $free_time_balance, $free_time_balance_interval) = (0.0,0.0,0,0);
    
    my $ratio;
    if ($last_balance) {
        if ((_CARRY_OVER_MODE eq $carry_over_mode
             || (_CARRY_OVER_TIMELY_MODE eq $carry_over_mode && $last_balance->timely_topup_count > 0)
            ) && (!$notopup_expiration || $stime < $notopup_expiration)) {
            #if (!defined $last_profile) {
            #    my $bm_last = get_actual_billing_mapping(schema => $schema, contract => $contract, now => $last_balance->start); #end); !?
            #    $last_profile = $bm_last->billing_mappings->first->billing_profile;
            #}
            my $contract_create = $contract->create_timestamp // $contract->modify_timestamp;
            $ratio = 1.0;
            if ($last_balance->start <= $contract_create && $last_balance->end >= $contract_create) { #$last_balance->end is never +inf here
                $ratio = _get_free_ratio($contract_create,$last_balance->start,$last_balance->end);
            }
            my $old_free_cash = $ratio * ($last_profile->interval_free_cash // _DEFAULT_PROFILE_FREE_CASH);
            $cash_balance = $last_balance->cash_balance;
            if ($last_balance->cash_balance_interval < $old_free_cash) {
                $cash_balance += $last_balance->cash_balance_interval - $old_free_cash;
            }
            #$ratio * $last_profile->interval_free_time // _DEFAULT_PROFILE_FREE_TIME
        }
        $ratio = 1.0;
    } else {
        $cash_balance = (defined $initial_balance ? $initial_balance : _DEFAULT_INITIAL_BALANCE);
        $ratio = _get_free_ratio($now,$stime, $etime);
    }
    
    my $free_cash = $ratio * ($profile->interval_free_cash // _DEFAULT_PROFILE_FREE_CASH);
    $cash_balance += $free_cash;
    $cash_balance_interval = 0.0;

    my $free_time = $ratio * ($profile->interval_free_time // _DEFAULT_PROFILE_FREE_TIME);
    $free_time_balance = $free_time;
    $free_time_balance_interval = 0;
    
    return [cash_balance => sprintf("%.4f",$cash_balance),
            cash_balance_interval => sprintf("%.4f",$cash_balance_interval),
            free_time_balance => sprintf("%.0f",$free_time_balance),
            free_time_balance_interval => sprintf("%.0f",$free_time_balance_interval)];

}

sub _get_free_ratio {
    my ($now,$stime,$etime) = @_;
    if (!NGCP::Panel::Utils::DateTime::is_infinite_future($etime)) {
        my $ctime;
        if (defined $now) {
            $ctime = ($now->clone->truncate(to => 'day') > $stime ? $now->clone->truncate(to => 'day') : $now);
        } else {
            $now = NGCP::Panel::Utils::DateTime::current_local;
            $ctime = $now->clone->truncate(to => 'day') > $stime ? $now->truncate(to => 'day') : $now;
        }
        #my $ctime = (defined $now ? $now->clone : NGCP::Panel::Utils::DateTime::current_local);
        #$ctime->truncate(to => 'day') if $ctime->clone->truncate(to => 'day') > $stime;
        my $start_of_next_interval = $etime->clone->add(seconds => 1);
        return ($start_of_next_interval->epoch - $ctime->epoch) / ($start_of_next_interval->epoch - $stime->epoch);
    }
    return 1.0;
}

sub _get_balance_interval_start_end {
    my (%params) = @_;
    my ($now,$start_mode,$last_etime,$interval_unit,$interval_value,$create) = @params{qw/now start_mode last_etime interval_unit interval_value create/};

    my ($stime,$etime,$ctime) = (undef,undef,$now // NGCP::Panel::Utils::DateTime::current_local);
    
    unless ($last_etime) { #initial interval
        $stime = _get_interval_start($ctime,$start_mode);
    } else {
        $stime = $last_etime->clone->add(seconds => 1);
    }
    
    if (defined $stime) {
        #if (_TOPUP_START_MODE ne $start_mode) {
        #    $etime = _add_interval($stime,$interval_unit,$interval_value,_START_MODE_PRESERVE_EOM->{$start_mode} ? $create : undef)->subtract(seconds => 1);
        #} else {
        #    $etime = NGCP::Panel::Utils::DateTime::infinite_future;
        #}
        if (_TOPUP_START_MODE eq $start_mode) {
            $etime = NGCP::Panel::Utils::DateTime::infinite_future;
        } elsif (_TOPUP_INTERVAL_START_MODE eq $start_mode) {
            if ($last_etime) {
                $etime = _add_interval($stime,$interval_unit,$interval_value)->subtract(seconds => 1); #no eom preserve, since we don't store the begin of the first interval
            } else { #initial interval
                $etime = NGCP::Panel::Utils::DateTime::infinite_future;
            }
        } else {
            $etime = _add_interval($stime,$interval_unit,$interval_value,_START_MODE_PRESERVE_EOM->{$start_mode} ? $create : undef)->subtract(seconds => 1);
        }        
    }
    
    return ($stime,$etime);
}

sub _get_resized_interval_end {
    my (%params) = @_;
    my ($ctime, $create, $start_mode,$is_topup) = @params{qw/ctime create_timestamp start_mode is_topup/};    
    if (_CREATE_START_MODE eq $start_mode) {
        my $start_of_next_interval;
        if ($ctime->day >= $create->day) {
            #e.g. ctime=30. Jan 2015 17:53, create=30. -> 28. Feb 2015 00:00
            $start_of_next_interval = $ctime->clone->set(day => $create->day)->truncate(to => 'day')->add(months => 1, end_of_month => 'limit');
        } else {
            my $last_day_of_month = NGCP::Panel::Utils::DateTime::last_day_of_month($ctime);
            if ($create->day > $last_day_of_month) {
                #e.g. ctime=28. Feb 2015 17:53, create=30. -> 30. Mar 2015 00:00
                $start_of_next_interval = $ctime->clone->add(months => 1)->set(day => $create->day)->truncate(to => 'day');
            } else {
                #e.g. ctime=15. Jul 2015 17:53, create=16. -> 16. Jul 2015 00:00
                $start_of_next_interval = $ctime->clone->set(day => $create->day)->truncate(to => 'day');    
            }
        }
        return $start_of_next_interval->subtract(seconds => 1);
    } elsif (_1ST_START_MODE eq $start_mode) {
        return $ctime->clone->truncate(to => 'month')->add(months => 1)->subtract(seconds => 1);
    } elsif (_TOPUP_START_MODE eq $start_mode) {
        return $ctime->clone; #->add(seconds => 1);
        #return NGCP::Panel::Utils::DateTime::infinite_future;
    } elsif (_TOPUP_INTERVAL_START_MODE eq $start_mode) {
        #return $ctime->clone; #->add(seconds => 1);
        if ($is_topup) {
            return $ctime->clone; #->add(seconds => 1);
        } else {
            return NGCP::Panel::Utils::DateTime::infinite_future;
        }
    }    
    return undef;    
}

sub _get_interval_start {
    my ($ctime,$start_mode) = @_;    
    if (_CREATE_START_MODE eq $start_mode) {
        return $ctime->clone->truncate(to => 'day');
    } elsif (_1ST_START_MODE eq $start_mode) {
        return $ctime->clone->truncate(to => 'month');
    } elsif (_TOPUP_START_MODE eq $start_mode) {
        return $ctime->clone; #->truncate(to => 'day');
    } elsif (_TOPUP_INTERVAL_START_MODE eq $start_mode) {
        return $ctime->clone; #->truncate(to => 'day');
    }
    return undef;
}

sub _add_interval {
    my ($from,$interval_unit,$interval_value,$align_eom_dt) = @_;
    if ('day' eq $interval_unit) {
        return $from->clone->add(days => $interval_value);
    } elsif ('hour' eq $interval_unit) {
        return $from->clone->add(hours => $interval_value);        
    } elsif ('week' eq $interval_unit) {
        return $from->clone->add(weeks => $interval_value);
    } elsif ('month' eq $interval_unit) {
        my $to = $from->clone->add(months => $interval_value, end_of_month => 'preserve');
        #DateTime's "preserve" mode would get from 30.Jan to 30.Mar, when adding 2 months
        #When adding 1 month two times, we get 28.Mar or 29.Mar, so we adjust:
        if (defined $align_eom_dt
            && $to->day > $align_eom_dt->day
            && $from->day == NGCP::Panel::Utils::DateTime::last_day_of_month($from)) {
            my $delta = NGCP::Panel::Utils::DateTime::last_day_of_month($align_eom_dt) - $align_eom_dt->day;
            $to->set(day => NGCP::Panel::Utils::DateTime::last_day_of_month($to) - $delta);
        }
        return $to;
    }
    return undef;
}

sub _get_notopup_expiration {
    my %params = @_;
    my($contract,$start_mode,$notopup_discard_intervals,$interval_unit,$last_balance)= @params{qw/contract $start_mode notopup_discard_intervals interval_unit last_balance/};
    my $notopup_expiration = undef;
    if ($notopup_discard_intervals) {
        #take the start of the latest interval where a topup occured,
        #add the allowed number+1 of the current package' intervals.
        #the balance is discarded  if the start of the next package
        #exceed this calculated expiration date.
        my $last_balance_w_topup;
        if ($last_balance) {
            $last_balance_w_topup = $last_balance;
        } else {
            $last_balance_w_topup = $contract->contract_balances->search({ topup_count => { '>' => 0 } },{ order_by => { '-desc' => 'end'},})->first;
            $last_balance_w_topup = $contract->contract_balances->search(undef,{ order_by => { '-asc' => 'start'},})->first unless $last_balance_w_topup;
            $notopup_discard_intervals += 1;
        }
        $notopup_expiration = _add_interval($last_balance_w_topup->start,$interval_unit,$notopup_discard_intervals,
            _START_MODE_PRESERVE_EOM->{$start_mode} ? $contract->create_timestamp // $contract->modify_timestamp : undef) if $last_balance_w_topup;
    }
    return $notopup_expiration;
}

sub get_actual_billing_mapping {
    my %params = @_;
    my ($c,$schema,$contract,$now) = @params{qw/c schema contract now/};
    $schema //= $c->model('DB');
    $now //= NGCP::Panel::Utils::DateTime::current_local;
    my $contract_create = $contract->create_timestamp // $contract->modify_timestamp;
    my $dtf = $schema->storage->datetime_parser;
    $now = $contract_create if $now < $contract_create; #if there is no mapping starting with or before $now, it would returns the mapping with max(id):
    return $schema->resultset('billing_mappings_actual')->search({ contract_id => $contract->id },{bind => [ ( $dtf->format_datetime($now) ) x 2],})->first;
}

sub set_subscriber_lock_level {
    my %params = @_;
    my ($c,$contract,$lock_level) = @params{qw/c contract lock_level/};
    for my $subscriber ($contract->voip_subscribers->search_rs({ 'me.status' => { '!=' => 'terminated' } })->all) {
        NGCP::Panel::Utils::Subscriber::lock_provisoning_voip_subscriber(
            c => $c,
            prov_subscriber => $subscriber->provisioning_voip_subscriber,
            level => $lock_level // 0,
        ) if ($subscriber->provisioning_voip_subscriber);
    }
}

sub underrun_lock_subscriber {
    my %params = @_;
    my ($c,$subscriber,$contract) = @params{qw/c subscriber contract/};
    $contract //= $subscriber->contract;
    my $balance = get_contract_balance(c => $c,contract => $contract);
    my $package = $contract->profile_package;
    my ($underrun_lock_threshold,$underrun_lock_level);
    if (defined $contract->contact->reseller_id && $package) {
        $underrun_lock_threshold = $package->underrun_lock_threshold;
        $underrun_lock_level = $package->underrun_lock_level;
    }
    if (defined $underrun_lock_threshold && defined $underrun_lock_level && $balance->cash_balance < $underrun_lock_threshold) {
        NGCP::Panel::Utils::Subscriber::lock_provisoning_voip_subscriber(
            c => $c,
            prov_subscriber => $subscriber->provisioning_voip_subscriber,
            level => $underrun_lock_level,
        ) if ($subscriber->provisioning_voip_subscriber);
    }
}

sub underrun_update_balance {
    my %params = @_;
    my ($c,$balance,$new_cash_balance,$now,$schema) = @params{qw/c balance new_cash_balance now schema/};
    $schema //= $c->model('DB');
    $now //= NGCP::Panel::Utils::DateTime::current_local;
    my $contract = $balance->contract;
    my $package = $contract->profile_package;
    my ($underrun_lock_threshold,$underrun_profile_threshold);
    if (defined $contract->contact->reseller_id && $package) {
        $underrun_lock_threshold = $package->underrun_lock_threshold;
        $underrun_profile_threshold = $package->underrun_profile_threshold;
    }
    my $update = {};
    if (_ENABLE_UNDERRUN_LOCK && defined $underrun_lock_threshold && $balance->cash_balance >= $underrun_lock_threshold && $new_cash_balance < $underrun_lock_threshold) {
        if (defined $package->underrun_lock_level) {
            set_subscriber_lock_level(c => $c, contract => $contract, lock_level => $package->underrun_lock_level);
            $update->{underrun_lock} = $now;
        }
    }
    if (_ENABLE_UNDERRUN_PROFILES && defined $underrun_profile_threshold && $balance->cash_balance >= $underrun_profile_threshold && $new_cash_balance < $underrun_profile_threshold) {
        #my $bm_actual = get_actual_billing_mapping(schema => $schema, contract => $contract, now => $now); 
        if (add_profile_mappings(c => $c,
                contract => $contract,
                package => $package,
                #bm_actual => $bm_actual,
                stime => $now,
                profiles => 'underrun_profiles',
                now => $now) > 0) {
            $update->{underrun_profiles} = $now;
        }
    }
    if ((scalar keys %$update) > 0) {
        $balance->update($update);
        $balance->discard_changes();
    }
    
    return $balance;
    
}

sub add_profile_mappings {
    my %params = @_;
    my ($c,$contract,$bm_actual,$package,$stime,$profiles,$now) = @params{qw/c contract bm_actual package stime profiles now/};
    my @profiles;
    if ($contract->status ne 'terminated' && (scalar (@profiles = $package->$profiles->all)) > 0) {
        $bm_actual //= get_actual_billing_mapping(c => $c,
            contract => $contract,
            now => $now);
        my $product_id = $bm_actual->billing_mappings->first->product->id;
        #my $old_prepaid = $bm_actual->billing_mappings->first->billing_profile->prepaid;            
        my @mappings_to_create = ();
        foreach my $mapping (@profiles) {
            push(@mappings_to_create,{ #assume not terminated, 
                billing_profile_id => $mapping->profile_id,
                network_id => $mapping->network_id,
                product_id => $product_id,
                start_date => $stime,
                end_date => undef,
            });
        }
        foreach my $mapping (@mappings_to_create) {
            $contract->billing_mappings->create($mapping); 
        }
        $bm_actual = get_actual_billing_mapping(c => $c,
            contract => $contract,
            now => $now);
        NGCP::Panel::Utils::Subscriber::switch_prepaid(c => $c,
            #old_prepaid => $old_prepaid,
            #new_prepaid => $bm_actual->billing_mappings->first->billing_profile->prepaid,
            prepaid => $bm_actual->billing_mappings->first->billing_profile->prepaid,
            contract => $contract,
        );
        return scalar @profiles;
    }
    return 0;
}

sub lock_contracts {
    my %params = @_;
    my($c,$schema,$rs,$contract_id_field,$contract_ids,$contract_id) = @params{qw/c schema rs contract_id_field contract_ids contract_id/};

    $schema //= $c->model('DB');
    
    my %contract_id_map = ();
    my $rs_result = undef;
    if (defined $rs and defined $contract_id_field) {
        #$rs = $rs->search_rs({},{
        #        columns => [ $contract_id_field ],
        #        distinct => 1
        #    }
        #);
        $rs_result = [ $rs->all ];
        foreach my $item (@$rs_result) {
            $contract_id_map{$item->$contract_id_field} = 1;
        }
    }
    if (defined $contract_ids) {
        foreach my $id (@$contract_ids) {
            $contract_id_map{$id} = 1;
        }
    }
    if (defined $contract_id) {
        $contract_id_map{$contract_id} = 1;
    }
    my @contract_ids_to_lock = keys %contract_id_map;
    my ($t1,$t2) = (time,undef);
    if (defined $contract_id && !defined $rs_result && !defined $contract_ids) {
        $c->log->debug('contract ID to be locked: ' . $contract_id) if $c;
        my $contract = $schema->resultset('contracts')->find({
                id => $contract_id
                },{for => 'update'});
        $t2 = time;
        $c->log->debug('contract ID ' . $contract_id . ' locked (' . ($t2 - $t1) . ' secs)') if $c;
        return $contract;
    } elsif ((scalar @contract_ids_to_lock) > 0) {
        @contract_ids_to_lock = sort { $a <=> $b } @contract_ids_to_lock; #"Access your tables and rows in a fixed order."
        my $contract_ids_label = join(', ',@contract_ids_to_lock);
        $c->log->debug('contract IDs to be locked: ' . $contract_ids_label) if $c;
        my @contracts = $schema->resultset('contracts')->search({
                id => { -in => [ @contract_ids_to_lock ] }
                },{for => 'update'})->all;
        $t2 = time;
        $c->log->debug('contract IDs ' . $contract_ids_label . ' locked (' . ($t2 - $t1) . ' secs)') if $c;        
        if (defined $contract_ids || defined $contract_id) {
            return [ @contracts ];
        } else {
            return $rs_result;
        }
    }
    $c->log->debug('no contract IDs to be locked!') if $c;
    return [];
}

sub check_balance_interval {
    my (%params) = @_;
    my ($c,$resource,$err_code) = @params{qw/c resource err_code/};
    
    my $schema = $c->model('DB');
    if (!defined $err_code || ref $err_code ne 'CODE') {
        $err_code = sub { return 0; };
    }
    
    unless(defined $resource->{balance_interval_unit} && defined $resource->{balance_interval_value}){
        return 0 unless &{$err_code}("Balance interval definition required.",'balance_interval');
    }
    unless($resource->{balance_interval_value} > 0) {
        return 0 unless &{$err_code}("Balance interval has to be greater than 0 interval units.",'balance_interval');
    }
    return 1;
}

sub check_carry_over_mode {
    my (%params) = @_;
    my ($c,$resource,$err_code) = @params{qw/c resource err_code/};
    
    my $schema = $c->model('DB');
    if (!defined $err_code || ref $err_code ne 'CODE') {
        $err_code = sub { return 0; };
    }
    
    if (defined $resource->{carry_over_mode} && $resource->{carry_over_mode} eq _CARRY_OVER_TIMELY_MODE) {
        unless(defined $resource->{timely_duration_unit} && defined $resource->{timely_duration_value}){
            return 0 unless &{$err_code}("'timely' interval definition required.",'timely_duration');
        }
        unless($resource->{balance_interval_value} > 0) {
            return 0 unless &{$err_code}("'timely' interval has to be greater than 0 interval units.",'timely_duration');
        }        
    }
    return 1;
}

sub check_underrun_lock_level {
    my (%params) = @_;
    my ($c,$resource,$err_code) = @params{qw/c resource err_code/};
    
    my $schema = $c->model('DB');
    if (!defined $err_code || ref $err_code ne 'CODE') {
        $err_code = sub { return 0; };
    }
    
    if (defined $resource->{underrun_lock_level}) {
        unless(defined $resource->{underrun_lock_threshold}){
            return 0 unless &{$err_code}("If specifying an underun lock level, 'underrun_lock_threshold' is required.",'underrun_lock_threshold');
        }
    }
    return 1;
}

sub check_profiles {
    my (%params) = @_;
    my ($c,$resource,$mappings_to_create,$err_code) = @params{qw/c resource mappings_to_create err_code/};
    
    my $schema = $c->model('DB');
    if (!defined $err_code || ref $err_code ne 'CODE') {
        $err_code = sub { return 0; };
    }
    
    my $mappings_counts = {};
    return 0 unless prepare_package_profile_set(c => $c, resource => $resource, field => 'initial_profiles', mappings_to_create => $mappings_to_create, mappings_counts => $mappings_counts, err_code => $err_code);
    if ($mappings_counts->{count_any_network} < 1) {
        return 0 unless &{$err_code}("An initial billing profile mapping with no billing network is required.",'initial_profiles');
    }    
    $mappings_counts = {};
    return 0 unless prepare_package_profile_set(c => $c, resource => $resource, field => 'underrun_profiles', mappings_to_create => $mappings_to_create, mappings_counts => $mappings_counts, err_code => $err_code);
    if ($mappings_counts->{count} > 0 && ! defined $resource->{underrun_profile_threshold}) {
        return 0 unless &{$err_code}("If specifying underrun profile mappings, 'underrun_profile_threshold' is required.",'underrun_profile_threshold');
    }
    $mappings_counts = {};
    return 0 unless prepare_package_profile_set(c => $c, resource => $resource, field => 'topup_profiles', mappings_to_create => $mappings_to_create, mappings_counts => $mappings_counts, err_code => $err_code);

    return 1;
}

sub prepare_profile_package {
    my (%params) = @_;
    
    my ($c,$resource,$mappings_to_create,$err_code) = @params{qw/c resource mappings_to_create err_code/};    

    my $schema = $c->model('DB');
    if (!defined $err_code || ref $err_code ne 'CODE') {
        $err_code = sub { return 0; };
    }
    
    return 0 unless check_carry_over_mode(c => $c, resource => $resource, err_code => $err_code);
    return 0 unless check_underrun_lock_level(c => $c, resource => $resource, err_code => $err_code);
    
    return 0 unless check_profiles(c => $c, resource => $resource, mappings_to_create => $mappings_to_create, err_code => $err_code);
    
    return 1;
}  

sub prepare_package_profile_set {
    my (%params) = @_;
    
    my ($c,$resource,$field,$mappings_to_create,$mappings_counts,$err_code) = @params{qw/c resource field mappings_to_create mappings_counts err_code/};    

    my $schema = $c->model('DB');
    if (!defined $err_code || ref $err_code ne 'CODE') {
        $err_code = sub { return 0; };
    }
    
    my $reseller_id = $resource->{reseller_id};

    $resource->{$field} //= [];
    
    if (ref $resource->{$field} ne 'ARRAY') {
        return 0 unless &{$err_code}("Invalid field '$field'. Must be an array.",$field);
    }
    
    if (defined $mappings_counts) {
        $mappings_counts->{count} //= 0;
        $mappings_counts->{count_any_network} //= 0;
    }
    
    my ($prepaid,$interval_free_cash,$interval_free_time) = (undef,undef,undef);
    my $mappings = delete $resource->{$field};
    foreach my $mapping (@$mappings) {
        if (ref $mapping ne 'HASH') {
            return 0 unless &{$err_code}("Invalid element in array '$field'. Must be an object.",$field);
        }
        if (defined $mappings_to_create) {
            my $profile = $schema->resultset('billing_profiles')->find($mapping->{profile_id});
            unless($profile) {
                return 0 unless &{$err_code}("Invalid 'profile_id' ($mapping->{profile_id}).",$field);
            }
            if ($profile->status eq 'terminated') {
                return 0 unless &{$err_code}("Invalid 'profile_id' ($mapping->{profile_id}), already terminated.",$field);
            }            
            if (defined $reseller_id && defined $profile->reseller_id && $reseller_id != $profile->reseller_id) { #($profile->reseller_id // -1)) {
                return 0 unless &{$err_code}("The reseller of the profile package doesn't match the reseller of the billing profile (" . $profile->name . ").",$field);
            }
            if (defined $prepaid) {
                if ($profile->prepaid != $prepaid) {
                    return 0 unless &{$err_code}("Mixing prepaid and post-paid billing profiles is not supported (" . $profile->name . ").",$field);
                }
            } else {
                $prepaid = $profile->prepaid;
            }
            
            if (defined $interval_free_cash) {
                if ($profile->interval_free_cash != $interval_free_cash) {
                    return 0 unless &{$err_code}("Profiles are supposed to have the same interval_free_cash value (" . $profile->name . ").",$field);
                }
            } else {
                $interval_free_cash = $profile->interval_free_cash;
            }
            if (defined $interval_free_time) {
                if ($profile->interval_free_time != $interval_free_time) {
                    return 0 unless &{$err_code}("Profiles are supposed to have the same interval_free_time value (" . $profile->name . ").",$field);
                }
            } else {
                $interval_free_time = $profile->interval_free_time;
            }            
           
            my $network;
            if (defined $mapping->{network_id}) {
                $network = $schema->resultset('billing_networks')->find($mapping->{network_id});
                unless($network) {
                    return 0 unless &{$err_code}("Invalid 'network_id'.",$field);
                }
                if (defined $reseller_id && defined $network->reseller_id && $reseller_id != $network->reseller_id) { #($network->reseller_id // -1)) {
                    return 0 unless &{$err_code}("The reseller of the profile package doesn't match the reseller of the billing network (" . $network->name . ").",$field);
                }
            }
            push(@$mappings_to_create,{
                profile_id => $profile->id,
                network_id => (defined $network ? $network->id : undef),
                discriminator => field_to_discriminator($field),
            });
        }
        if (defined $mappings_counts) {
            $mappings_counts->{count} += 1;
            $mappings_counts->{count_any_network} += 1 unless $mapping->{network_id};
        }
    }   
    return 1;
}

sub field_to_discriminator {
    my ($field) = @_;
    return _DISCRIMINATOR_MAP->{$field};
}

sub get_contract_count_stmt {
    return "select count(distinct c.id) from `billing`.`contracts` c where c.`profile_package_id` = `me`.`id` and c.status != 'terminated'";
}

sub get_voucher_count_stmt {
    return "select count(distinct v.id) from `billing`.`vouchers` v where v.`package_id` = `me`.`id`"; # and v.`used_by_subscriber_id` is null";
}

sub _get_profile_set_group_stmt {
    my ($discriminator) = @_;
    my $grp_stmt = "group_concat(if(bn.`name` is null,bp.`name`,concat(bp.`name`,'/',bn.`name`)) separator ', ')";
    my $grp_len = 30;
    return "select if(length(".$grp_stmt.") > ".$grp_len.", concat(left(".$grp_stmt.", ".$grp_len."), '...'), ".$grp_stmt.") from `billing`.`package_profile_sets` pps join `billing`.`billing_profiles` bp on bp.`id` = pps.`profile_id` left join `billing`.`billing_networks` bn on bn.`id` = pps.`network_id` where pps.`package_id` = `me`.`id` and pps.`discriminator` = '" . $discriminator . "'";
}

sub get_datatable_cols {
    
    my ($c) = @_;
    return (
        { name => "contract_cnt", "search" => 0, "title" => $c->loc("Contracts"), },
        { name => "voucher_cnt", "search" => 0, "title" => $c->loc("Vouchers"), },
        { name => 'initial_profiles_grp', accessor => "initial_profiles_grp", search => 0, title => $c->loc('Initial Profiles'),
         literal_sql => _get_profile_set_group_stmt(INITIAL_PROFILE_DISCRIMINATOR) },
        { name => 'underrun_profiles_grp', accessor => "underrun_profiles_grp", search => 0, title => $c->loc('Underrun Profiles'),
         literal_sql => _get_profile_set_group_stmt(UNDERRUN_PROFILE_DISCRIMINATOR) },
        { name => 'topup_profiles_grp', accessor => "topup_profiles_grp", search => 0, title => $c->loc('Top-up Profiles'),
         literal_sql => _get_profile_set_group_stmt(TOPUP_PROFILE_DISCRIMINATOR) },
        
        { name => 'profile_name', accessor => "profiles_srch", search => 1, join => { profiles => 'billing_profile' },
          literal_sql => 'billing_profile.name' },
        { name => 'network_name', accessor => "network_srch", search => 1, join => { profiles => 'billing_network' },
          literal_sql => 'billing_network.name' },        
    );
    
}

sub get_customer_datatable_cols {
    
    my ($c) = @_;
    return (
        { name => "id", search => 1, title => $c->loc("#") },
        { name => "external_id", search => 1, title => $c->loc("External #") },
        #{ name => "billing_mappings_actual.billing_mappings.product.name", search => 1, title => $c->loc("Product") },
        { name => "contact.email", search => 1, title => $c->loc("Contact Email") },
        { name => "status", search => 1, title => $c->loc("Status") },
    );
}
        
1;