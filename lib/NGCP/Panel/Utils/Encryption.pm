package NGCP::Panel::Utils::Encryption;
use Sipwise::Base;

use Crypt::OpenSSL::RSA;
use MIME::Base64;

my $rsa_encrytper;
my $rsa_decrytper;

sub _check_encrypted {
    
    my $c = shift;
    my $encrypted = $c->req->param('encrypted');
    if ($encrypted
        and ('rsa' eq lc($encrypted)
        or '1' eq $encrypted
        or 'true' eq lc($encrypted))) {
        return 1;
    }
    return 0;
    
}

sub encrypt_rsa {
    
    my ($c,$plaintext) = @_;
    if (_check_encrypted($c)) {
        unless ($rsa_encrytper) {
            $rsa_encrytper = Crypt::PK::RSA->new();
            $rsa_encrytper->import_key($public_key_file);
            die('public key file contains a private key') if $rsa_encrytper->is_private();
        }
        my $ciphertext = $rsa_encrytper->encrypt($plaintext);
        $ciphertext = encode_base64($ciphertext, '');
        return $ciphertext;
    }
    return $plaintext;
    
}

sub decrypt_rsa {
    
    my ($c,$ciphertext) = @_;
    if (_check_encrypted($c)) {
        unless ($rsa_decrytper) {
            $rsa_decrytper = Crypt::PK::RSA->new();
            $rsa_decrytper->import_key($private_key_file);
            die('private key file contains a public key') unless $rsa_decrytper->is_private();
        }
        $ciphertext = decode_base64($ciphertext);
        my $plaintext = $rsa_decrytper->decrypt($ciphertext);
        return $plaintext;
    }
    return $ciphertext;

}

1;
