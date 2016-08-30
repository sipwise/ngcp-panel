package NGCP::Panel::Utils::EmergencyMapping;
use strict;
use warnings;

use Text::CSV_XS;
use NGCP::Panel::Utils::MySQL;
use NGCP::Panel::Utils::CSVSeparator;

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
    my ($c,$data,$schema, $reseller_id) = @params{qw/c data schema reseller_id/};
    my ($start, $end);

    my $separator = NGCP::Panel::Utils::CSVSeparator::get_separator(
        path => $data,
        lucky => 1,
    );
    unless(defined $separator) {
        my $text = $c->loc("Failed to detect CSV separator");
        return ([], [], \$text );
    }

    # csv bulk upload
    my $csv = Text::CSV_XS->new({ 
        allow_whitespace => 1,
        binary => 1,
        keep_meta_info => 1,
        sep_char => $separator,
    });

    #my @cols = @{ $c->config->{lnp_csv}->{element_order} };
    my @cols = qw/name code prefix/;

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
        unless(exists $containers{$k}) {
            my $container = $schema->resultset('emergency_containers')->find_or_create({
                name => $k,
                reseller_id => $reseller_id,
            });
            $containers{$k} = $container->id;
        }
        unless(length $row->{prefix}) {
            $row->{prefix} = undef;
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
    my($c, $reseller_id) = @params{qw/c reseller_id/};

    #my @cols = @{ $c->config->{emergency_mapping_csv}->{element_order} };
    my @cols = qw/name code prefix/;

    my $mapping_rs = $c->stash->{emergency_mapping_rs}->search_rs({
            'emergency_container.reseller_id' => $reseller_id,
        },
        {
            '+select' => ['emergency_container.name'],
            '+as'     => ['name'],
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
