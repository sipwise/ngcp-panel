package NGCP::Panel::Utils::EmergencyMapping;
use strict;
use warnings;

use Text::CSV_XS;
use NGCP::Panel::Utils::MySQL;

sub _insert_batch {
    my ($c, $schema, $mappings, $chunk_size) = @_;
    NGCP::Panel::Utils::MySQL::bulk_insert(
        c => $c,
        schema => $schema,
        do_transaction => 0,
        query => "REPLACE INTO provisioning.emergency_mappings(emergency_container_id, code, prefix)",
        data => $mappings,
        chunk_size => $chunk_size
    );
}

sub upload_csv {
    my(%params) = @_;
    my ($c,$data,$schema) = @params{qw/c data schema/};
    my ($start, $end);

    # csv bulk upload
    my $csv = Text::CSV_XS->new({ allow_whitespace => 1, binary => 1, keep_meta_info => 1 });
    #my @cols = @{ $c->config->{lnp_csv}->{element_order} };
    my @cols = qw/name reseller_id code prefix/;

    my @fields ;
    my @fails = ();
    my $linenum = 0;
    my @mappings = ();
    my %containers = ();
    open(my $fh, '<:encoding(utf8)', $data);
    $start = time;
    my $chunk_size = 2000;
    while ( my $line = $csv->getline($fh)) {
        ++$linenum;
        unless (scalar @{ $line } == scalar @cols) {
            push @fails, $linenum;
            next;
        }
        my $row = {};
        @{$row}{@cols} = @{ $line };
        my $k = $row->{name};
        my $r = $row->{reseller_id};
        unless(exists $containers{$k}) {
            my $container = $schema->resultset('emergency_containers')->find_or_create({
                name => $k,
                reseller_id => $r,
            });
            $containers{$k} = $container->id;
        }
        push @mappings, [$containers{$k}, $row->{code}, $row->{prefix}];

        if($linenum % $chunk_size == 0) {
            _insert_batch($c, $schema, \@mappings, $chunk_size);
            @mappings = ();
        }
    }
    if(@mappings) {
        _insert_batch($c, $schema, \@mappings, $chunk_size);
    }
    $end = time;
    close $fh;
    $c->log->debug("Parsing and uploading Emergency Mappings CSV took " . ($end - $start) . "s");

    my $text = $c->loc('Emergency Mappings successfully uploaded');
    if(@fails) {
        $text .= $c->loc(", but skipped the following line numbers: ") . (join ", ", @fails);
    }

    return ( \@mappings, \@fails, \$text );
}

sub create_csv {
    my(%params) = @_;
    my($c) = @params{qw/c/};

    #my @cols = @{ $c->config->{emergency_mapping_csv}->{element_order} };
    my @cols = qw/name reseller_id code prefix/;

    my $mapping_rs = $c->stash->{emergency_mapping_rs}->search_rs(
        undef,
        {
            '+select' => ['emergency_container.name', 'emergency_container.reseller_id'],
            '+as'     => ['name', 'reseller_id'],
            'join'    => 'emergency_container',
        }
    );

    my ($start, $end);
    $start = time;
    while(my $mapping_row = $mapping_rs->next) {
        my %mapping = $mapping_row->get_inflated_columns;
        delete $mapping{id};
        $c->res->write_fh->write(join (",", @mapping{@cols}) );
        $c->res->write_fh->write("\n");
    }
    $c->res->write_fh->close;
    $end = time;
    $c->log->debug("Creating Emergency Mapping CSV for download took " . ($end - $start) . "s");
    return 1;
}

1;

# vim: set tabstop=4 expandtab:
