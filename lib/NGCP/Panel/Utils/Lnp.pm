package NGCP::Panel::Utils::Lnp;
use strict;
use warnings;

use Text::CSV_XS;
use NGCP::Panel::Utils::MySQL;
use NGCP::Panel::Utils::DateTime qw();
use Scalar::Util qw(blessed);

sub get_lnpnumber_rs {
    my ($c, $now, $number) = @_;
    my $schema = $c->model('DB');
    my $item_rs = $schema->resultset('lnp_numbers'); #test env: 35sec for a 100 items page with 200k
    if (defined $now) {
        if(!(blessed($now) && $now->isa('DateTime'))) {
            eval {
                $now = NGCP::Panel::Utils::DateTime::from_string($now);
            };
            if ($@) {
                $c->log->debug($@);
                $now = NGCP::Panel::Utils::DateTime::current_local();
                $c->log->debug("lnp history - using current timestamp " . $now);
            }
        }
        my $dtf = $schema->storage->datetime_parser;
        #undef $number if defined $number && length($number) == 0;
        $item_rs = $item_rs->search({},{
            bind => [ ( $dtf->format_datetime($now) ) x 2, $number, $number ],
            'join' => [ 'lnp_numbers_actual' ],
        }); #test env: 50sec (6.5 sec raw query time)
    }
    return $item_rs;
}

sub _insert_batch {
    my ($c, $schema, $numbers, $chunk_size) = @_;
    NGCP::Panel::Utils::MySQL::bulk_insert(
        c => $c,
        schema => $schema,
        do_transaction => 0,
        query => "INSERT INTO billing.lnp_numbers(lnp_provider_id, number, routing_number, start, end)",
        data => $numbers,
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
    my @cols = qw/carrier_name carrier_prefix number routing_number start end authoritative skip_rewrite/;

    my @fields ;
    my @fails = ();
    my $linenum = 0;
    my @numbers = ();
    my %carriers = ();
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
        my $k = $row->{carrier_name};
        my $p = $row->{carrier_prefix};
        my $auth = $row->{authoritative};
        my $rw = $row->{skip_rewrite};
        unless(exists $carriers{$k}) {
            my $carrier = $schema->resultset('lnp_providers')->find_or_create({
                name => $k,
                prefix => $p,
                authoritative => $auth,
                skip_rewrite => $rw,
            });
            $carriers{$k} = $carrier->id;
        }
        $row->{start} ||= undef;
        if($row->{start} && $row->{start} =~ /^\d{4}-\d{2}-\d{2}$/) {
            $row->{start} .= 'T00:00:00';
        }
        $row->{end} ||= undef;
        if($row->{end} && $row->{end} =~ /^\d{4}-\d{2}-\d{2}$/) {
            $row->{end} .= 'T23:59:59';
        }
        push @numbers, [$carriers{$k}, $row->{number}, $row->{routing_number}, $row->{start}, $row->{end}];

        if($linenum % $chunk_size == 0) {
            _insert_batch($c, $schema, \@numbers, $chunk_size);
            @numbers = ();
        }
    }
    if(@numbers) {
        _insert_batch($c, $schema, \@numbers, $chunk_size);
    }
    $end = time;
    close $fh;
    $c->log->debug("Parsing and uploading LNP CSV took " . ($end - $start) . "s");

    my $text = $c->loc('LNP numbers successfully uploaded');
    if(@fails) {
        $text .= $c->loc(", but skipped the following line numbers: ") . (join ", ", @fails);
    }

    return ( \@numbers, \@fails, \$text );
}

sub create_csv {
    my(%params) = @_;
    my($c, $number_rs) = @params{qw/c number_rs/};
    $number_rs //= $c->stash->{number_rs} // $c->model('DB')->resultset('lnp_numbers');
    #my @cols = @{ $c->config->{lnp_csv}->{element_order} };
    my @cols = qw/carrier_name carrier_prefix number routing_number start end authoritative skip_rewrite/;

    my $lnp_rs = $number_rs->search_rs(
        undef,
        {
            '+select' => ['lnp_provider.name','lnp_provider.prefix', 'lnp_provider.authoritative', 'lnp_provider.skip_rewrite'],
            '+as'     => ['carrier_name','carrier_prefix', 'authoritative', 'skip_rewrite'],
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
        $c->res->write_fh->write(join (",", @lnp{@cols}) );
        $c->res->write_fh->write("\n");
    }
    $c->res->write_fh->close;
    $end = time;
    $c->log->debug("Creating LNP CSV for download took " . ($end - $start) . "s");
    return 1;
}

1;

# vim: set tabstop=4 expandtab:
