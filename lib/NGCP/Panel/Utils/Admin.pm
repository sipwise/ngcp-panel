package NGCP::Panel::Utils::Admin;

use Sipwise::Base;
use Crypt::Eksblowfish::Bcrypt qw/bcrypt_hash en_base64 de_base64/;
use Data::Entropy::Algorithms qw/rand_bits/;

sub get_bcrypt_cost {
    return 13;
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

sub perform_auth {
    my ($c, $user, $pass) = @_;
    my $res;

    my $dbadmin = $c->model('DB')->resultset('admins')->find({
        login => $user,
        is_active => 1,
    });
    if(defined $dbadmin && defined $dbadmin->saltedpass) {
        $c->log->debug("login via bcrypt");
        my ($db_b64salt, $db_b64hash) = split /\$/, $dbadmin->saltedpass;
        my $salt = de_base64($db_b64salt);
        my $usr_b64hash = en_base64(bcrypt_hash({
            key_nul => 1,
            cost => get_bcrypt_cost(),
            salt => $salt,
        }, $pass));
        # fetch again to load user into session etc (otherwise we could
        # simply compare the two hashes here :(
        $res = $c->authenticate(
            {
                login => $user,
                saltedpass => $db_b64salt . '$' . $usr_b64hash,
                'dbix_class' => {
                    searchargs => [{
                        -and => [
                            login => $user,
                            is_active => 1,
                        ],
                    }],
                }
            }, 'admin_bcrypt'
        );
    } elsif(defined $dbadmin) { # we already know if the username is wrong, no need to check again

        # check md5 and migrate over to bcrypt on success
        $c->log->debug("login via md5");
        $res = $c->authenticate(
            {
                login => $user,
                md5pass => $pass,
                'dbix_class' => {
                    searchargs => [{
                        -and => [
                            login => $user,
                            is_active => 1,
                        ],
                    }],
                }
            }, 'admin');

        if($res) {
            # login ok, time to move user to bcrypt hashing
            $c->log->debug("migrating to bcrypt");
            my $saltedpass = generate_salted_hash($pass);
            $dbadmin->update({
                md5pass => undef,
                saltedpass => $saltedpass,
            });
        }
    }
    return $res;
}

1;
