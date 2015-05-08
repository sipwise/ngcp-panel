package NGCP::Panel::Utils::Billing;
use strict;
use warnings;

use Text::CSV_XS;

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
    open my $fh, '<', $data;
    while ( my $line = <$fh> ){
        ++$linenum;
        chomp $line;
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

#sub _get_profile_set_group_stmt {
#    my ($discriminator) = @_;
#        my $rs = $c->model('DB')->resultset('billing_profiles')->search({
#            'me.status' => { '!=' => 'terminated' },
#            }, {
#            join => { 'billing_mappings' => 'contract_active' },
#            '+select' => { count => 'contract_active.status', -as => 'v_count_used' },
#            'group_by' => [ qw(me.id) ]
#        });
#    #ayrrrr
#    "select count(pp.id) from from `billing`.`package_profile_sets` pps join `billing`.`profile_packages` pp on pp.id = pps.package_id where pps.`profile_id` = `me`.`id` and pp.status != 'terminated' group by pp.id"
#    my $grp_stmt = "group_concat(if(bn.`name` is null,bp.`name`,concat(bp.`name`,'/',bn.`name`)) separator ', ')";
#    my $grp_len = 30;
#    return "select if(length(".$grp_stmt.") > ".$grp_len.", concat(left(".$grp_stmt.", ".$grp_len."), '...'), ".$grp_stmt.") from `billing`.`package_profile_sets` pps join `billing`.`billing_profiles` bp on bp.`id` = pps.`profile_id` left join `billing`.`billing_networks` bn on bn.`id` = pps.`network_id` where pps.`package_id` = `me`.`id` and pps.`discriminator` = '" . $discriminator . "'";
#}
#
#sub get_datatable_cols {
#    
#    my ($c) = @_;
#    return (
#        { name => "v_count_used", "search" => 0, "title" => $c->loc("Used (act. contracts)") },
#        { name => "packages_cnt", name => "packages_cnt", "search" => 0, "title" => $c->loc("Active packages"),
#          literal_sql => "select count(pp.id) from from `billing`.`package_profile_sets` pps join `billing`.`profile_packages` pp on pp.id = pps.package_id where pps.`profile_id` = `me`.`id` and pp.status != 'terminated' group by pp.id" },
#        
#    );
#    
#}

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
