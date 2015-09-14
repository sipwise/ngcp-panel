package NGCP::Panel::Utils::Billing;
use strict;
use warnings;

use Text::CSV_XS;
use IO::String;
use NGCP::Schema;
use NGCP::Panel::Utils::Preferences qw();

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
    while ( my $line = <$fh> ){
        ++$linenum;
        next unless length $line;
        unless($csv->parse($line)) {
            push @fails, $linenum;
            next;
        }
        @fields = $csv->fields();
        unless (scalar @fields == scalar @cols) {
            push @fails, $linenum;
            next;
        }
        my $row = {};
        @{$row}{@cols} = @fields;
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
        push @fees, $row;
    }

    $profile->billing_fees_raw->populate(\@fees);
    $schema->storage->dbh_do(sub{
        my ($storage, $dbh) = @_;
        $dbh->do("call billing.fill_billing_fees(?)", undef, $profile->id );
    });

    my $text = $c->loc('Billing Fee successfully uploaded');
    if(@fails) {
        $text .= $c->loc(", but skipped the following line numbers: ") . (join ", ", @fails);
    }

    return ( \@fees, \@fails, \$text );
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
    my ($c,$profile_id,$old_prepaid,$new_prepaid,$contract_rs) = @params{qw/c profile_id old_prepaid new_prepaid contract_rs/};

    my $schema //= $c->model('DB');
    # if prepaid flag changed, update all subscribers for customers
    # who currently have the billing profile active
    my $rs = $schema->resultset('billing_mappings')->search({
        billing_profile_id => $profile_id,
    });
    
    if($old_prepaid && !$new_prepaid ||
       !$old_prepaid && $new_prepaid) {
       
        #this will taking too long, prohibit it: 
        #die("changing the prepaid flag is not allowed");
        
        foreach my $mapping ($rs->all) {
            my $contract = $mapping->contract;
            next unless($contract->contact->reseller_id); # skip non-customers
            my $chosen_contract = $contract_rs->find({id => $contract->id});
            next unless( defined $chosen_contract && $chosen_contract->get_column('billing_mapping_id') == $mapping->id ); # is not current mapping
            foreach my $sub($contract->voip_subscribers->all) {
                my $prov_sub = $sub->provisioning_voip_subscriber;
                next unless($sub->provisioning_voip_subscriber);
                NGCP::Panel::Utils::Preferences::set_provisoning_voip_subscriber_first_int_attr_value(c => $c,
                    prov_subscriber => $prov_sub,
                    value => ($new_prepaid ? 1 : 0),
                    attribute => 'prepaid'
                );  
            }
        }
    }
    
}

sub get_contract_count_stmt {
    return "select count(distinct c.id) from `billing`.`billing_mappings` bm join `billing`.`contracts` c on c.id = bm.contract_id where bm.`billing_profile_id` = `me`.`id` and c.status != 'terminated' and (bm.end_date is null or bm.end_date >= now())";
}
sub get_package_count_stmt {
    return "select count(distinct pp.id) from `billing`.`package_profile_sets` pps join `billing`.`profile_packages` pp on pp.id = pps.package_id where pps.`profile_id` = `me`.`id`"; # and pp.status != 'terminated'";
}

sub get_datatable_cols {

    my ($c) = @_;
    return (
        { name => "contract_cnt", "search" => 0, "title" => $c->loc("Used (contracts)"), },
        { name => "package_cnt", "search" => 0, "title" => $c->loc("Used (packages)"), },

    );

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
