package NGCP::Panel::Utils::Admin;

use Sipwise::Base;
use Crypt::Eksblowfish::Bcrypt qw/bcrypt_hash en_base64/;
use Data::Entropy::Algorithms qw/rand_bits/;

sub get_bcrypt_cost {
    return 12;
}

sub generate_salted_hash {
    my $pass = shift;

	my $salt = rand_bits(128);
	my $b64salt = en_base64($salt);
	my $b64hash = en_base64(bcrypt_hash({
	    key_nul => 1,
	    cost => get_bcrypt_cost(),
	    salt => $salt,
	}, $pass));
	return $b64salt . '$' . $b64hash;
}


1;
