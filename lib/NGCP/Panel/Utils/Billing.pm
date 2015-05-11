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
