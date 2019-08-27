package NGCP::Panel::Role::API::CustomerFraudEvents;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';
use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::BillingMappings qw();
use NGCP::Panel::Utils::DateTime qw();
use DateTime::Format::Strptime qw();

sub _item_rs {
    my ($self, $c, $id) = @_;

    my %cond = ();
    if ($c->user->roles eq "admin" || $c->user->roles eq "ccareadmin") {
        if (my $reseller_id = $c->request->param('reseller_id')) {
            $cond{'contact.reseller_id'} = $reseller_id;
        }
    } elsif ($c->user->roles eq "reseller" || $c->user->roles eq "ccare") {
        $cond{'contact.reseller_id'} = $c->user->reseller_id;
    }
    if (my $contract_id = $c->request->param('contract_id')) {
        $cond{'me.contract_id'} = $contract_id;
    }
    if (my $notify_status = $c->request->param('notify_status')) {
        $cond{'notify_status'} = $notify_status;
    }
    if ($id) {
        $cond{'me.id'} = $id;
    }
    my $attr = {
        join => { 'contract' => 'contact' },
    };

    my $dtf = $c->model('DB')->storage->datetime_parser;
    my $now;
    my $datetime_fmt = DateTime::Format::Strptime->new(
        pattern   => '%Y-%m-%d',
    );
    unless ($now = $datetime_fmt->parse_datetime($c->request->param('date'))) {
        $now = NGCP::Panel::Utils::DateTime::current_local();
    }
    my $first_of_month = $now->clone;
    $first_of_month->set_day(1);
    my $day_rs = $c->model('DB')->resultset('cdr_period_costs')->search_rs({
        'period' => 'day',
        'period_date' => $dtf->format_date($now),
        'direction' => 'out',
        'fraud_limit_exceeded' => 1,
        'contract.status' => 'active',
        %cond,
    },$attr);
    $now->subtract(days => 1);
    my $previous_day_rs = $c->model('DB')->resultset('cdr_period_costs')->search_rs({
        'period' => 'day',
        'period_date' => $dtf->format_date($now),
        'direction' => 'out',
        'fraud_limit_exceeded' => 1,
        'contract.status' => 'active',
        %cond,
    },$attr);
    my $month_rs = $c->model('DB')->resultset('cdr_period_costs')->search_rs({
        'period' => 'month',
        'period_date' => $dtf->format_date($first_of_month),
        'direction' => 'out',
        'fraud_limit_exceeded' => 1,
        'contract.status' => 'active',
        %cond,
    },$attr);

    my $interval = $c->request->param('interval');
    my $rs;
    if (defined $interval and $interval eq 'day') {
        $rs = $day_rs->union_all($previous_day_rs);
    } elsif (defined $interval and $interval eq 'month') {
        $rs = $month_rs;
    } elsif (not defined $interval) {
        $rs = $day_rs->union_all([$previous_day_rs, $month_rs]);
    } else {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid interval '$interval'");
        return;
    }

    return $rs;
}

sub get_form {
    my ($self, $c) = @_;
    if ($c->user->roles eq "admin" || $c->user->roles eq "ccareadmin") {
        return NGCP::Panel::Form::get("NGCP::Panel::Form::CustomerFraudEvents::Admin", $c);
    } elsif ($c->user->roles eq "reseller" || $c->user->roles eq "ccare") {
        return NGCP::Panel::Form::get("NGCP::Panel::Form::CustomerFraudEvents::Reseller", $c);
    }
}

sub resource_from_item {
    my ($self, $c, $item) = @_; #$form

    my %cpc = $item->get_inflated_columns;
    my %resource;
    my $billing_mapping = NGCP::Panel::Utils::BillingMappings::get_actual_billing_mapping(c => $c,
        now => NGCP::Panel::Utils::DateTime::epoch_local($item->last_cdr_start_time),
        contract => $item->contract,
    );
    my $billing_profile = $billing_mapping->billing_profile;
    my $contract_fraud_preference = $item->contract->contract_fraud_preference;
    $resource{'contract_id'} = $item->contract->id;
    $resource{'reseller_id'} = $item->contract->contact->reseller_id;
    $resource{'interval'} = $cpc{'period'};
    $resource{'type'} = $cpc{'fraud_limit_type'};
    $resource{'type'} = 'account_limit' if $resource{'type'} eq 'contract';
    $resource{'type'} = 'profile_limit' if $resource{'type'} eq 'billing_profile';

    if ($billing_profile->fraud_use_reseller_rates) {
        $resource{'interval_cost'} = $cpc{'customer_cost'};
    } else {
        $resource{'interval_cost'} = $cpc{'reseller_cost'};
    }
    if ('month' eq $cpc{'period'}) {
        if ('contract' eq $cpc{'fraud_limit_type'}) {
            if ($contract_fraud_preference) {
                $resource{'interval_limit'} = $contract_fraud_preference->fraud_interval_limit;
                $resource{'interval_lock'} = $contract_fraud_preference->fraud_interval_lock;
                $resource{'interval_notify'} = $contract_fraud_preference->fraud_interval_notify;
            } else {
                $self->debug($c, "no contract fraud preference any more for contract ID $cpc{contract_id}");
                $resource{'interval_limit'} = undef;
                $resource{'interval_lock'} = undef;
                $resource{'interval_notify'} = undef;
            }
        } elsif ('billing_profile' eq $cpc{'fraud_limit_type'}) {
            $resource{'interval_limit'} = $billing_profile->fraud_interval_limit;
            $resource{'interval_lock'} = $billing_profile->fraud_interval_lock;
            $resource{'interval_notify'} = $billing_profile->fraud_interval_notify;
        } else {
            $self->debug($c, "unsupported fraud limit type '$cpc{fraud_limit_type}'");
            $resource{'interval_limit'} = undef;
            $resource{'interval_lock'} = undef;
            $resource{'interval_notify'} = undef;
        }
    } elsif ('day' eq $cpc{'period'}) {
        if ('contract' eq $cpc{'fraud_limit_type'}) {
            if ($contract_fraud_preference) {
                $resource{'interval_limit'} = $contract_fraud_preference->fraud_daily_limit;
                $resource{'interval_lock'} = $contract_fraud_preference->fraud_daily_lock;
                $resource{'interval_notify'} = $contract_fraud_preference->fraud_daily_notify;
            } else {

            }
        } elsif ('billing_profile' eq $cpc{'fraud_limit_type'}) {
            $resource{'interval_limit'} = $billing_profile->fraud_daily_limit;
            $resource{'interval_lock'} = $billing_profile->fraud_daily_lock;
            $resource{'interval_notify'} = $billing_profile->fraud_daily_notify;
        } else {
            $self->debug($c, "unsupported fraud limit type '$cpc{fraud_limit_type}'");
            $resource{'interval_limit'} = undef;
            $resource{'interval_lock'} = undef;
            $resource{'interval_notify'} = undef;
        }
    } else {
        $self->debug($c, "unsupported fraud interval '$cpc{'period'}'");
        $resource{'interval_limit'} = undef;
        $resource{'interval_lock'} = undef;
        $resource{'interval_notify'} = undef;
    }
    $resource{'use_reseller_rates'} = $billing_profile->fraud_use_reseller_rates;
    $resource{'notify_status'} = $cpc{'notify_status'};
    my $datetime_fmt = DateTime::Format::Strptime->new(
        pattern => '%F %T',
    );
    $resource{'notified_at'} = undef;
    $resource{'notified_at'} = $datetime_fmt->format_datetime($cpc{notified_at}) if defined $cpc{notified_at};

    return \%resource;

}

sub item_by_id {
    my ($self, $c, $id) = @_;
    return $self->item_rs($c,$id)->first;
}

sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    $form //= $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
    );

    try {
        # only update r/w fields
        $item->update({
            map { $_ => $resource->{$_} } qw(notify_status notified_at)
        })->discard_changes;
    } catch($e) {
        $c->log->error("failed to update customer fraud event: $e");
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to update customer fraud event.");
        return;
    };

    return $item;
}

1;
