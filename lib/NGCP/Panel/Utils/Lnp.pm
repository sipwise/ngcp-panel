package NGCP::Panel::Utils::Lnp;
use strict;
use warnings;

use Text::CSV_XS;
use NGCP::Panel::Utils::MySQL;

sub upload_csv {
    my(%params) = @_;
    my ($c,$data,$schema) = @params{qw/c data schema/};
    my ($start, $end);

    # csv bulk upload
    my $csv = Text::CSV_XS->new({ allow_whitespace => 1, binary => 1, keep_meta_info => 1 });
    #my @cols = @{ $c->config->{lnp_csv}->{element_order} };
    my @cols = qw/carrier_name carrier_prefix number start end/;

    my @fields ;
    my @fails = ();
    my $linenum = 0;
    my @numbers = ();
    my %carriers = ();
    open(my $fh, '<:encoding(utf8)', $data);
    $start = time;
    while ( my $line = $csv->getline($fh)) {
        ++$linenum;
        unless (scalar @{ $line } == scalar @cols) {
            push @fails, $linenum;
            next;
        }
        my $row = {};
        @{$row}{@cols} = @{ $line };
        my $k = $row->{carrier_name};
        my $p = $row->{carrier_prefix};
        unless(exists $carriers{$k}) {
            my $carrier = $schema->resultset('lnp_providers')->find_or_create({
                name => $k,
                prefix => $p,
            });
            $carriers{$k} = $carrier->id;
        }
        push @numbers, [$carriers{$k}, $row->{number}, $row->{start}, $row->{end}];
    }
    $end = time;
    close $fh;
    $c->log->debug("Parsing LNP CSV took " . ($end - $start) . "s");

    $start = time;
    NGCP::Panel::Utils::MySQL::bulk_insert(
        c => $c,
        schema => $schema,
        do_transaction => 0,
        query => "INSERT INTO billing.lnp_numbers(lnp_provider_id, number, start, end)",
        data => \@numbers,
        chunk_size => 2000
    );
    $end = time;
    $c->log->debug("Bulk inserting LNP CSV took " . ($end - $start) . "s");
    
    my $text = $c->loc('LNP numbers successfully uploaded');
    if(@fails) {
        $text .= $c->loc(", but skipped the following line numbers: ") . (join ", ", @fails);
    }

    return ( \@numbers, \@fails, \$text );
}

sub create_csv {
    my(%params) = @_;
    my($c) = @params{qw/c/};

    #my @cols = @{ $c->config->{lnp_csv}->{element_order} };
    my @cols = qw/carrier_name carrier_prefix number start end/;

    my $lnp_rs = $c->stash->{number_rs}->search_rs(
        undef,
        {
            '+select' => ['lnp_provider.name','lnp_provider.prefix'],
            '+as'     => ['carrier_name','carrier_prefix'],
            'join'    => 'lnp_provider',
        }
    );

    my ($start, $end);
    $start = time;
    while(my $lnp_row = $lnp_rs->next) {
        my %lnp = $lnp_row->get_inflated_columns;
        delete $lnp{id};
        $lnp{start} =~ s/T\d{2}:\d{2}:\d{2}//;
        $lnp{end} =~ s/T\d{2}:\d{2}:\d{2}//;
        $c->res->write(join (",", @lnp{@cols}) );
        $c->res->write("\n");
    }
    $c->res->close;
    $end = time;
    $c->log->debug("Creating LNP CSV for download took " . ($end - $start) . "s");
    return 1;
}

1;

# vim: set tabstop=4 expandtab:
