package NGCP::Panel::Utils::Billing;
use strict;
use warnings;

use Text::CSV_XS;
use IO::String;
use NGCP::Schema;
use NGCP::Panel::Utils::Preferences qw();
use NGCP::Panel::Utils::DateTime;
use DateTime::Format::Strptime qw();

use NGCP::Panel::Utils::IntervalTree::Simple;

use constant _CHECK_PEAKTIME_WEEKDAY_OVERLAPS => 1;
use constant _CHECK_PEAKTIME_SPECIALS_OVERLAPS => 1;

sub check_profile_update_item {
    my ($c,$new_resource,$old_item,$err_code) = @_;

    return 1 unless $old_item;

    if (!defined $err_code || ref $err_code ne 'CODE') {
        $err_code = sub { return 0; };
    }

    if ($old_item->status eq 'terminated') {
        return 0 unless &{$err_code}("Billing profile is already terminated and cannot be changed.",'status');
    }

    #if ($new_resource->{prepaid} && not $new_resource->{prepaid_library}) {
    #    return 0 unless &{$err_code}("The prepaid rating library is mandatory for a prepaid profile.",'prepaid_library');
    #}

    my $contract_exists = $old_item->get_column('contract_exists');
    my $contract_cnt = $old_item->get_column('contract_cnt');
    #my $package_cnt = $old_item->get_column('package_cnt');

    if ($contract_exists
        && defined $new_resource->{interval_charge} && $old_item->interval_charge != $new_resource->{interval_charge}) {
        return 0 unless &{$err_code}("Interval charge cannot be changed (profile linked to $contract_cnt contracts).",'interval_charge');
    }
    if ($contract_exists
        && defined $new_resource->{interval_free_time} && $old_item->interval_free_time != $new_resource->{interval_free_time}) {
        return 0 unless &{$err_code}("Interval free time cannot be changed (profile linked to $contract_cnt contracts).",'interval_free_time');
    }
    if ($contract_exists
        && defined $new_resource->{interval_free_cash} && $old_item->interval_free_cash != $new_resource->{interval_free_cash}) {
        return 0 unless &{$err_code}("Interval free cash cannot be changed (profile linked to $contract_cnt contracts).",'interval_free_cash');
    }

    return 1;

}

sub prepare_peaktime_weekdays {
    my(%params) = @_;
    my ($c,$resource,$err_code,$peaktimes_to_create) = @params{qw/c resource err_code peaktimes_to_create/};

    if (!defined $err_code || ref $err_code ne 'CODE') {
        $err_code = sub { return 0; };
    }

    my $peaktime_weekdays = delete $resource->{peaktime_weekdays};
    $peaktime_weekdays //= [];
    if ('ARRAY' ne ref $peaktime_weekdays) {
        return 0 unless &{$err_code}("peaktime_weekdays is not an array");
    }

    my @WEEKDAYS = @{NGCP::Panel::Utils::DateTime::get_weekday_names($c)};

    my %intersecter_map = ();
    foreach my $peaktime_weekday (@$peaktime_weekdays) {
        if ($peaktime_weekday->{weekday} < 0 || $peaktime_weekday->{weekday} > 6) {
            return 0 unless &{$err_code}("Peaktime weekday must be between 0 (Monday) and 6 (Sunday)");
        }
        my $weekday = $peaktime_weekday->{weekday};

        my $parsetime  = DateTime::Format::Strptime->new(pattern => '%T');
        my $parsetime2 = DateTime::Format::Strptime->new(pattern => '%R');
        my $stime = $peaktime_weekday->{start};
        my $etime = $peaktime_weekday->{stop};
        $stime = '00:00:00' unless($stime && length($stime));
        $etime = '23:59:59' unless($etime && length($etime));
        my $start = $parsetime->parse_datetime($stime)
                || $parsetime2->parse_datetime($stime);
        my $end = $parsetime->parse_datetime($etime)
              || $parsetime2->parse_datetime($etime);

        unless ($start) {
            return 0 unless &{$err_code}("Unknown weekday peaktime start time '$stime'.");
        }
        unless ($end) {
            return 0 unless &{$err_code}("Unknown weekday peaktime stop time '$etime'.");
        }
        $stime = $parsetime->format_datetime($start);
        $etime = $parsetime->format_datetime($end);
        if ($end < $start) { #<= actually
            return 0 unless &{$err_code}("Peaktime ($weekday - $WEEKDAYS[$weekday]) end time $etime must be later than start time $stime.");
        }

        my $intersecter;
        if (_CHECK_PEAKTIME_WEEKDAY_OVERLAPS) {
            if (exists $intersecter_map{$weekday}) {
                $intersecter = $intersecter_map{$weekday};
            } else {
                $intersecter = NGCP::Panel::Utils::IntervalTree::Simple->new();
                $intersecter_map{$weekday} = $intersecter;
            }
        }

        if (defined $intersecter) {
            my $from = $start->hour * 3600 + $start->minute * 60 + $start->second;
            my $to = $end->hour * 3600 + $end->minute * 60 + $end->second + 1;
            my $label = '(' . $weekday . ' - ' . $WEEKDAYS[$weekday] . ' ' . $stime . ' - ' . $etime .')';
            my $overlaps_with = $intersecter->find($from,$to);
            if ((scalar @$overlaps_with) > 0) {
                return 0 unless &{$err_code}("Peaktime $label overlaps with peaktimes " . join(", ",@$overlaps_with));
            } else {
                $intersecter->insert($from,$to,$label);
            }
        }

        if ('ARRAY' eq ref $peaktimes_to_create) {
            push(@$peaktimes_to_create,{ weekday => $weekday,
                    start => $stime,
                    end => $etime,
                });
        }

    }

    return 1;
}

sub prepare_peaktime_specials {
    my(%params) = @_;
    my ($c,$resource,$err_code,$peaktimes_to_create) = @params{qw/c resource err_code peaktimes_to_create/};

    if (!defined $err_code || ref $err_code ne 'CODE') {
        $err_code = sub { return 0; };
    }

    my $peaktime_specials = delete $resource->{peaktime_special};
    $peaktime_specials //= [];
    if ('ARRAY' ne ref $peaktime_specials) {
        return 0 unless &{$err_code}("peaktime_special is not an array");
    }

    my $intersecter = (_CHECK_PEAKTIME_SPECIALS_OVERLAPS ? NGCP::Panel::Utils::IntervalTree::Simple->new() : undef);
    foreach my $peaktime_special (@$peaktime_specials) {
        my $stime = $peaktime_special->{start};
        my $etime = $peaktime_special->{stop};
        #format checked by form
        my $start = (defined $stime ? NGCP::Panel::Utils::DateTime::from_string($stime) : undef);
        my $end = (defined $etime ? NGCP::Panel::Utils::DateTime::from_string($etime) : undef);

        #although nullable, rateomat logic does not support open intervals
        unless ($start) {
            return 0 unless &{$err_code}("Empty special peaktime start timestamp.");
        }
        unless ($end) {
            return 0 unless &{$err_code}("Empty special peaktime stop timestamp.");
        }
        if ($end < $start) { #<= actually
            return 0 unless &{$err_code}("Special peaktime end timestamp $etime must be later than start timestamp $stime.");
        }

        if (defined $intersecter) {
            my $from = $start->epoch;
            my $to = $end->epoch + 1;
            my $label = $stime . ' - ' . $etime;
            my $overlaps_with = $intersecter->find($from,$to);
            if ((scalar @$overlaps_with) > 0) {
                return 0 unless &{$err_code}("Special peaktime $label overlaps with peaktimes " . join(", ",@$overlaps_with));
            } else {
                $intersecter->insert($from,$to,$label);
            }
        }

        if ('ARRAY' eq ref $peaktimes_to_create) {
            push(@$peaktimes_to_create,{
                    start => $start,
                    end => $end,
                });
        }

    }

    return 1;
}

sub validate_billing_fee {
    my ($values,$error_code,$value_code) = @_;
    $value_code //= sub {
        my $field = shift;
        return $values->{$field};
    };

    my $match_mode = $values->{match_mode};
    if (defined $match_mode
        and ('regex_longest_pattern' eq $match_mode
        or 'regex_longest_match' eq $match_mode)) {
        foreach my $field (qw(source destination)) {
            my $pattern = &$value_code($field);
            if (defined $pattern and length($pattern) > 0) {
                eval {
                    qr/$pattern/;
                };
                if ($@) {
                    return 0 unless &$error_code($field,'no valid regexp',$@);
                }
            }
        }
    }

    foreach my $field (qw(onpeak_init_interval onpeak_follow_interval offpeak_init_interval offpeak_follow_interval)) {
        if(int(&$value_code($field)) < 1) {
            return 0 unless &$error_code($field,'must be greater than 0');
        }
    }

    return 1;
}

sub process_billing_fees{
    my(%params) = @_;
    my ($c,$data,$profile,$schema) = @params{qw/c data profile schema/};

    # csv bulk upload
    my $csv = Text::CSV_XS->new({ allow_whitespace => 1, binary => 1, keep_meta_info => 1 });
    my @cols = @{ $c->config->{fees_csv}->{element_order} };

    my @fields ;
    my @fails = ();
    my $linenum = 0;
    my @fees = ();
    my %zones = ();
    open(my $fh, '<:encoding(utf8)', $data);
    #to don't stop on first failed parse - don't use "while($csv->getline)"
    while ( my $line = <$fh> ){
        ++$linenum;
        next unless length $line;
        unless($csv->parse($line)) {
            push @fails, $linenum;
            next;
        }
        @fields = $csv->fields();
        my $row = {};
        @{$row}{@cols} = @fields;
        unless($row->{zone}){
            push @fails, $linenum;
            next;
        }

        my $k = $row->{zone}.'__NGCP__'.$row->{zone_detail};
        unless(exists $zones{$k}) {
            my $zone = $profile->billing_zones->find_or_create({
                zone => $row->{zone},
                detail => $row->{zone_detail}
            });
            $zones{$k} = $zone->id;
        }
        $row->{billing_zone_id} = $zones{$k};
        delete $row->{zone};
        delete $row->{zone_detail};
        $row->{match_mode} = 'regex_longest_pattern' unless $row->{match_mode};
        $row->{onpeak_extra_rate} = 0 unless $row->{onpeak_extra_rate};
        $row->{offpeak_extra_rate} = 0 unless $row->{offpeak_extra_rate};
        $row->{onpeak_extra_second} = undef if (defined $row->{onpeak_extra_second} and $row->{onpeak_extra_second} eq '');
        $row->{offpeak_extra_second} = undef if (defined $row->{offpeak_extra_second} and $row->{offpeak_extra_second} eq '');
        $row->{offpeak_use_free_time} = $row->{onpeak_use_free_time} if (not defined $row->{offpeak_use_free_time} or $row->{offpeak_use_free_time} eq '');
        $row->{aoc_pulse_amount_per_message} = 0 unless $row->{aoc_pulse_amount_per_message};
        unless (validate_billing_fee($row,
            sub {
                my ($field,$error,$error_detail) = @_;
                return 0;
            },
            undef,
            )) {
            push @fails, $linenum;
            next;
        }
        push @fees, $row;
    }

    insert_unique_billing_fees(
        c => $c,
        schema => $schema,
        profile => $profile,
        fees => \@fees
    );

    my $text = $c->loc('Billing Fee successfully uploaded');
    if(@fails) {
        $text .= $c->loc(", but skipped the following line numbers: ") . (join ", ", @fails);
    }

    return ( \@fees, \@fails, \$text );
}

sub insert_unique_billing_fees{
    my(%params) = @_;
    my($c,$schema,$profile,$fees,$return_created) = @params{qw/c schema profile fees return_created/};
    $return_created //= 0;

    #while we use lower id we don't need insert records from billing_fees, they are already contain in billing_fees with lower id
    $profile->billing_fees_raw->delete();

    $schema->storage->dbh_do(sub{
        my ($storage, $dbh) = @_;
        (my ($auto_increment)) = $dbh->selectrow_array('select `AUTO_INCREMENT` from INFORMATION_SCHEMA.TABLES where TABLE_SCHEMA = "billing" AND TABLE_NAME   = "billing_fees"');
        $dbh->do('alter table billing.billing_fees_raw auto_increment='.$auto_increment);
    });
    my $created_fees_raw = $profile->billing_fees_raw->populate($fees);

    $schema->storage->dbh_do(sub{
        my ($storage, $dbh) = @_;
        $c->log->debug('call billing.fill_billing_fees('.$profile->id.')');
        $dbh->do("call billing.fill_billing_fees(?)", undef, $profile->id );
    });

    #return section
    if($return_created){
        my @created_fees = $profile->billing_fees->search({ 'id' => { -in => [map { $_->id } @$created_fees_raw] } } )->all;
        return \@created_fees;
    }
    return;
}
sub combine_billing_fees{
    my(%params) = @_;
    my($c,$profile,$schema) = @params{qw/c profile schema/};

    my $csv = Text::CSV_XS->new({ allow_whitespace => 1, binary => 1, keep_meta_info => 1 });
    my @cols = @{ $c->config->{fees_csv}->{element_order} };
    $csv->column_names(@cols);
    my $io = IO::String->new();

    my $fees_rs = $profile->billing_fees->search_rs(
        undef,
        {
            '+select' => ['billing_zone.zone','billing_zone.detail'],
            '+as'     => ['zone','zone_detail'],
            'join'    => 'billing_zone',
        }
    );

    #$csv->print($io, [ @cols ]);
    #print $io "\n";
    while (  my $billing_fee_row = $fees_rs->next ){
        #$csv->print_hr($io, $billing_fee_row->get_inflated_columns);
        my %billing_fee = $billing_fee_row->get_inflated_columns;
        $csv->print($io, [ @billing_fee{@cols} ]);
        print $io "\n";
    }
    return $io->string_ref;
}
sub get_billing_profile_uniq_params{
    my(%params) = @_;
    my($params) = $params{params};
    my $uniq = '_dup_'.time();
    my $uniq_length = length($uniq);
    my %uniq_columns =  ('handle' => 63, 'name' => 31);
    while(my($column,$limit) = each %uniq_columns){
        $params->{$column}= substr( $params->{$column}, 0, $limit - $uniq_length ).$uniq ;
    }
    return $params;
}
sub clone_billing_profile_tackles{
    my(%params) = @_;
    my($c, $profile_old, $profile_new, $schema) = @params{qw/c profile_old profile_new schema/};
    $schema //= $c->model('DB');

    my %struct_info = (
        'billing_zones' => 'billing_zones',
        'billing_peaktime_weekdays' => 'billing_peaktime_weekdays',
        'billing_peaktime_special' => 'billing_peaktime_specials'
    );
    while (my ($table_name,$rel_name) = each %struct_info ){
        my $source = NGCP::Schema->source($table_name);
        my @columns = grep { !/^billing_profile_id$|^id$/i } $source->columns;
        my $resultset = $profile_old->$rel_name->search_rs(undef,{
            'select' => [@columns,{ '' => \[ $profile_new->id], -as => 'billing_profile_id' } ],
            'as'     => [@columns,'billing_profile_id'],
        });
        $resultset->result_class('DBIx::Class::ResultClass::HashRefInflator');
        my @records = $resultset->all;
        $profile_new->$rel_name->populate(\@records) if @records;

        #insert into billing_peaktime_special(billing_profile_id,end,start) select ?,end,start from billing_peaktime_special where billing_profile_id=?, undef, $profile_new->id, $profile_old->id

        #insert into billing_peaktime_weekdays(billing_profile_id,end,start,weekday) select ?,end,start,weekday from billing_peaktime_weekdays where billing_profile_id=?, undef, $profile_new->id, $profile_old->id

        #insert into billing_zones(billing_profile_id,zone,detail) select ?,zone,detail from billing_zones where billing_profile_id=?, undef, $profile_new->id, $profile_old->id


    }

    #insert into billing_fees(billing_profile_id,billing_zone_id,source,destination,direction,type,onpeak_init_rate,onpeak_init_interval,onpeak_follow_rate,onpeak_follow_interval,offpeak_init_rate,offpeak_init_interval,offpeak_follow_rate,offpeak_follow_interval,use_free_time) select ?,bz_new.billing_zone_id,source,destination,direction,type,onpeak_init_rate,onpeak_init_interval,onpeak_follow_rate,onpeak_follow_interval,offpeak_init_rate,offpeak_init_interval,offpeak_follow_rate,offpeak_follow_interval,use_free_time
    #from billing_fees
    #inner join billing_zones bz_old on billing_fees.billing_zone_id=bz_old.billing_zone_id
    #inner join billing_zones bz_new on bz_old.zone=bz_new.zone and bz_old.detail=bz_new.detail and bz_new.billing_profile_id=? where billing_fees.billing_profile_id=?, undef, $profile_new->id, $profile_new->id, $profile_old->id

    my $source = NGCP::Schema->source('billing_fees');
    my @columns = grep { !/^billing_profile_id$|^id$|^billing_zone_id$/i } $source->columns;
    my $fees_rs = $profile_old->billing_fees->search_rs(
        undef,
        {
            'select' => [
                @columns,
                { '' =>\['bz_new.id'],        -as => 'billing_zone_id' },
                { '' => \[ $profile_new->id], -as => 'billing_profile_id' }
            ],
            'as'     => [ @columns,'billing_zone_id','billing_profile_id' ],
            alias => 'me',
            from  => [
                { 'me' => 'billing.billing_fees' },
                [
                    #!Attention:  -join-type DOESN'T WORK here!!! But in optimistic case, when all billing_zones created successfully - inner, which is default, is sufficient.
                    { 'bz_old' => 'billing.billing_zones', '-join-type' => 'inner' },
                    [
                        { 'me.billing_zone_id' => 'bz_old.id' },
                    ],
                ],
                [
                    #!Attention:  -join-type DOESN'T WORK here!!! But in optimistic case, when all billing_zones created successfully - inner, which is default, is sufficient.
                    { 'bz_new' => 'billing.billing_zones', '-join-type' => 'inner' },
                    [
                        {
                            '-and' => [
                                {
                                    'bz_new.zone'   => { -ident => 'bz_old.zone'} ,
                                    'bz_new.detail' => { -ident => 'bz_old.detail'} ,
                                    'bz_new.billing_profile_id' => $profile_new->id
                                },
                            ],
                        },
                    ],
                ],
            ],
        }
    );

    $fees_rs->result_class('DBIx::Class::ResultClass::HashRefInflator');
    my @records = $fees_rs->all;
    $profile_new->billing_fees_raw->populate(\@records);
    $schema->storage->dbh_do(sub{
        my ($storage, $dbh) = @_;
        $dbh->do("call billing.fill_billing_fees(?)", undef, $profile_new->id );
    });
}

sub switch_prepaid {
    my %params = @_;
    my ($c,$profile_id,$old_prepaid,$new_prepaid) = @params{qw/c profile_id old_prepaid new_prepaid/};

}

sub get_contract_exists_stmt {

    return <<EOS;
select
  1
from billing.contracts_billing_profile_network_schedule cbpns
join billing.contracts_billing_profile_network cbpn on cbpns.profile_network_id = cbpn.id
join billing._v_actual_effective_start_time est on est.contract_id = cbpn.contract_id and cbpns.effective_start_time = est.effective_start_time
join billing.contracts as c on est.contract_id = c.id
where
cbpn.billing_profile_id = me.id
and c.status != 'terminated'
limit 1
EOS

}

sub get_contract_count_stmt {

    return <<EOS;
select
  count(c.id)
from billing.contracts_billing_profile_network_schedule cbpns
join billing.contracts_billing_profile_network cbpn on cbpns.profile_network_id = cbpn.id
join billing._v_actual_effective_start_time est on est.contract_id = cbpn.contract_id and cbpns.effective_start_time = est.effective_start_time
join billing.contracts as c on est.contract_id = c.id
where
cbpn.billing_profile_id = me.id
and c.status != 'terminated'
EOS

}

sub get_package_count_stmt {

    return <<EOS;
select
  count(distinct pp.id)
from `billing`.`package_profile_sets` pps
join `billing`.`profile_packages` pp on pp.id = pps.package_id
where pps.`profile_id` = `me`.`id`
EOS
# and pp.status != 'terminated'";

}

sub get_datatable_cols {

    my ($c) = @_;
    return (
        { name => "prepaid", "search" => 0, "title" => $c->loc("Prepaid"),
          custom_renderer => 'function ( data, type, full, opt ) { opt.escapeHtml = false; return \'<input type="checkbox" disabled="disabled"\' + (full.prepaid == 1 ? \' checked="checked"\': \'\') + \'/>\'; }' },
        { name => "contract_cnt", "search" => 0, "title" => $c->loc("Used (contracts)"), },
        { name => "package_cnt", "search" => 0, "title" => $c->loc("Used (packages)"), },

    );

}

sub resource_from_peaktime_weekdays {

    my ($profile) = @_;

    my $datetime_fmt = DateTime::Format::Strptime->new(
        pattern => '%T',
    );
    my $rs = $profile->billing_peaktime_weekdays->search_rs(
        undef,
        { order_by => { '-asc' => [ 'weekday', 'start', 'id' ]},
        });
    my @weekday_peaktimes = ();
    foreach my $weekday_peaktime ($rs->all) {
        my %wp = ( weekday => $weekday_peaktime->weekday );
        $wp{start} = $weekday_peaktime->start; #($weekday_peaktime->start ? $datetime_fmt->format_datetime($weekday_peaktime->start) : undef);
        $wp{stop} = $weekday_peaktime->end; #($weekday_peaktime->end ? $datetime_fmt->format_datetime($weekday_peaktime->end) : undef);
        push(@weekday_peaktimes,\%wp);
    }
    return \@weekday_peaktimes;

}

sub resource_from_peaktime_specials {

    my ($profile) = @_;

    my $datetime_fmt = DateTime::Format::Strptime->new(
        pattern => '%F %T',
    );
    my $rs = $profile->billing_peaktime_specials->search_rs(
        undef,
        { order_by => { '-asc' => [ 'start', 'id' ]},
        });
    my @special_peaktimes = ();
    foreach my $special_peaktime ($rs->all) {
        my %sp = ();
        $sp{start} = ($special_peaktime->start ? $datetime_fmt->format_datetime($special_peaktime->start) : undef);
        $sp{stop} = ($special_peaktime->end ? $datetime_fmt->format_datetime($special_peaktime->end) : undef);
        push(@special_peaktimes,\%sp);
    }
    return \@special_peaktimes;

}

1;

=head1 NAME

NGCP::Panel::Utils::Billing

=head1 DESCRIPTION

A temporary helper to manipulate billing plan related data

=head1 METHODS

=head2 process_billing_fees

Parse billing fees uploaded csv

=head1 AUTHOR

Irina Peshinskaya

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
# vim: set tabstop=4 expandtab:
