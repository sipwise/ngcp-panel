package NGCP::Panel::Utils::Voucher;
use Sipwise::Base;
use Crypt::Rijndael;
use MIME::Base64;

sub encrypt_code {
    my ($c, $plain) = @_;

    my $key = $c->config->{vouchers}->{key};
    my $iv = $c->config->{vouchers}->{iv};

    # pkcs#5 padding to 16 bytes blocksize
    my $pad = 16 - (length $plain) % 16;
    $plain .= pack('C', $pad) x $pad;

    my $cipher = Crypt::Rijndael->new(
        $key,
        Crypt::Rijndael::MODE_CBC()
    );
    $cipher->set_iv($iv);
    my $crypted = $cipher->encrypt($plain);
    my $b64 = encode_base64($crypted, '');
    return $b64;
}

sub decrypt_code {
    my ($c, $code) = @_;

    my $key = $c->config->{vouchers}->{key};
    my $iv = $c->config->{vouchers}->{iv};

    my $cipher = Crypt::Rijndael->new(
        $key,
        Crypt::Rijndael::MODE_CBC()
    );
    $cipher->set_iv($iv);
    my $crypted = decode_base64($code);
    my $plain = $cipher->decrypt($crypted) . "";
    # remove padding
    $plain =~ s/[\x01-\x1e]*$//;
    return $plain;
}

1;
