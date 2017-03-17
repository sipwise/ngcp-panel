package NGCP::Panel::Utils::Admin;

use Sipwise::Base;
use Crypt::Eksblowfish::Bcrypt qw/bcrypt_hash en_base64 de_base64/;
use Data::Entropy::Algorithms qw/rand_bits/;
use IO::Compress::Zip qw/zip/;

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

sub generate_client_cert {
    my ($c, $admin, $error_cb) = @_;

    my $updated;
    my ($serial, $pem, $p12);
    while (!$updated) {
        $serial = time;
        try {
            $pem = $c->model('CA')->make_client($c, $serial);
            $p12 = $c->model('CA')->make_pkcs12($c, $serial, $pem, 'sipwise');
        } catch ($e) {
            $error_cb->($e);
            return;
        }
        try {
            $admin->update({ 
                ssl_client_m_serial => $serial,
                ssl_client_certificate => undef, # not used anymore, clear it just in case
            });
            $updated = 1;
        } catch(DBIx::Class::Exception $e where { "$_" =~ qr'Duplicate entry' }) {
            $serial++;
        }
    }

    my $input = {
        "NGCP-API-client-certificate-$serial.pem" => $pem,
        "NGCP-API-client-certificate-$serial.p12" => $p12,
    };
    my $zip_opts = {
        AutoClose => 0,
        Append => 0,
        Name => "README.txt",
        CanonicalName => 1,
        Stream => 1,
    };
    my $zipped_file;
    my $zip = IO::Compress::Zip->new(\$zipped_file, %{ $zip_opts });
    $zip->write("Use the PEM file for programmatical clients like java, perl, php or curl, and the P12 file for browsers like Firefox or Chrome. The password for the P12 import is 'sipwise'. Handle this file with care, as it cannot be downloaded for a second time! Only a new certificate can be generated if the certificate is lost.\n");
    foreach my $k(keys %{ $input } ) {
        $zip_opts->{Name} = $k;
        $zip_opts->{Append} = 1;
        $zip->newStream(%{ $zip_opts });
        $zip->write($input->{$k});
    }
    $zip->close();

    return { serial => $serial, file => $zipped_file };
}

1;
