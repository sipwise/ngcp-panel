package NGCP::Panel::Utils::DeviceFirmware;

use warnings;
use strict;

use English;
use POSIX;

my $chunk_size = 10*1024*1024; # 10MB

sub insert_firmware_data {
    my (%args)   = @_;
    my $c        = $args{c};
    my $fw_id    = $args{fw_id};
    # either data_ref or data_fh are expected
    my $data_ref = $args{data_ref};
    my $data_fh  = $args{data_fh};

    # do not set it larger than 10M

    $c->model('DB')->resultset('autoprov_firmwares')->find({id => $fw_id},{for => 'update'});

    my $rs = $c->model('DB')->resultset('autoprov_firmwares_data')->search({
        fw_id => $fw_id
    });
    if ($rs->count > 0) {
        $rs->delete;
    }

    my $fh;
    if ($data_fh) {
        $fh = $data_fh;
        seek($fh, 0, 0);
    } else {
        open($fh, "<:raw", $data_ref)
            or die "Cannot open firmware_data filehandler: ".$ERRNO;
    }

    my $buffer;
    my $offset = 0;
    binmode $fh;
    while (read($fh, $buffer, $chunk_size, 0)) {
        $c->model('DB')->resultset('autoprov_firmwares_data')->create(
            { fw_id => $fw_id, data => $buffer }
        );
        $offset += $chunk_size;
        seek($fh, $offset, 0);
    }

    close $fh;

    return;
}

sub get_firmware_data {
    my (%args)   = @_;
    my $c        = $args{c};
    my $fw_id    = $args{fw_id};

    my $rs = $c->model('DB')->resultset('autoprov_firmwares_data')->search({
        fw_id => $fw_id
    },
    {
        order_by => { -asc => 'id' }
    });

    my $data = '';
    if ($rs->count) {
        foreach my $fw_data ($rs->all) {
            $data = $data . $fw_data->data;
        }
    }

    return $data;
}

sub get_firmware_data_into_body {
    my (%args)   = @_;
    my $c        = $args{c};
    my $fw_id    = $args{fw_id};

    my ($range_from, $range_to, $range_len);
    if  ($c->request->headers->header('Range')) {
        my $range = $c->request->headers->header('Range');
        if ($range =~ /^bytes=(\d+)\-(\d+)$/) {
            $range_from = int($1);
            $range_to = int($2);
            $range_len = $range_to - $range_from + 1;
            if ($range_to < $range_from) {
                $range_from = $range_to = undef;
            }
        }
    }

    # TODO: for now, if the requested range fits into the first chunk, request that range
    # directly from db, otherwise we fetch all and extract the requested part
    # later, due to the chunking in the db;
    # this should be optimized to only request the range needed directly from db, but
    # it must be ensured that we also handle cross-chunk ranges
    my ($col, $limit);
    if (defined $range_from && defined $range_to &&
      $range_from < $chunk_size && ($range_from + $range_len) < $chunk_size) {
        my $mysql_range_from = $range_from + 1;
        $col = \"SUBSTRING(data, $mysql_range_from, $range_len)";
        $limit = 1;
    } else {
        $col = 'data';
        $limit = 0;
    }

    my $rs = $c->model('DB')->resultset('autoprov_firmwares_data')->search({
        fw_id => $fw_id
    },
    {
        select => [$col, \"OCTET_LENGTH(data)"],
        as     => [qw/body data_length/],
        order_by => { -asc => 'id' }
    });

    my $data = '';
    my $full_len = 0;
    my $use_chunk = 1;
    if ($rs->count) {
        foreach my $fw_data ($rs->all) {
            if ($use_chunk) {
                $data = $data . $fw_data->get_column('body');
                if ($limit) {
                    $use_chunk = 0;
                }
            }
            $full_len += $fw_data->get_column('data_length');
        }
    }

    if (defined $range_from && defined $range_to) {
        unless ($limit) {
            $data = substr($data, $range_from, $range_len);
        }
        $c->response->status(206);
        $c->response->header("Content-Range" => "bytes $range_from-$range_to/$full_len");
    }
    $c->response->body($data);
    return 0;
}



1;

# vim: set tabstop=4 expandtab:
