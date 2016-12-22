package NGCP::Panel::Utils::DeviceFirmware;

use English;

sub insert_firmware_data {
    my (%args)   = @_;
    my $c        = $args{c};
    my $fw_id    = $args{fw_id};
    # either data_ref or data_fh are expected
    my $data_ref = $args{data_ref};
    my $data_fh  = $args{data_fh};

    # do not set it larger than 10M
    my $chunk_size = 10*1024*1024; # 10MB

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
    if ($rs->first) {
        foreach my $fw_data ($rs->all) {
            $data = $data . $fw_data->data;
        }
    }

    return $data;
}
1;

# vim: set tabstop=4 expandtab:
