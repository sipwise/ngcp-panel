package NGCP::Panel::Utils::Admin;

use Sipwise::Base;
use Crypt::Eksblowfish::Bcrypt qw/bcrypt_hash en_base64 de_base64/;
use Data::Entropy::Algorithms qw/rand_bits/;
use IO::Compress::Zip qw/zip/;
use IPC::System::Simple qw/capturex/;


sub get_special_admin_login {
    return 'sipwise';
}

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

sub check_openvpn_status {
    my ($c, $params) = @_;
    $params //= {};
    #possible params:
    # - no_check_availability - check availability is expensive. If we did it already, we can skip it
    # - check_status - check particular command, active or enabled
    my $ret = {
        allowed   => 0, #based on role
        available => 0, #unavailable
        enabled   => 0, #disabled
        active    => 0, #inactive
    };
    my $config = $c->config->{openvpn} // {};
    my $systemctl_cmd = $config->{command};
    #default service is openvpn@ovpn, where ovpn profile is a openvpn config located at /etc/openvpn/ovpn.conf
    my $openvpn_service = $config->{service};
    if (!$config->{allowed}) {
        return $ret;
    }
    if ($params->{no_check_availability} || check_openvpn_availability($c)) {
        $ret->{available} = 1;
        if ( !$params->{check_status} || $params->{check_status} eq 'enabled') {
            my $output = cmd($c, undef, $systemctl_cmd, 'is-enabled', $openvpn_service);
            if ($output eq 'enabled') {#what we will see on localized OS? should "enabled" be localized?
                $ret->{enabled} = 1;
            } elsif ($output ne 'disabled') {
                #all other is-enabled responses, except "enabled" and "disabled" mean that service is not available at all
                $ret->{available} = 0;
            }
        }
        if ($ret->{available}) {
            if ( !$params->{check_status} || $params->{check_status} eq 'active') {
                my $output = cmd($c, undef, $systemctl_cmd, 'is-active', $openvpn_service);
                if ($output eq 'active') {
                    $ret->{active} = 1;
                }
            }
        }
    }
    #testing
    #$ret->{active} = 1;
    return $ret;
}

sub check_openvpn_availability {
    my ($c) = @_;
    my $res = 0;
    my $config = $c->config->{openvpn} // {};
    my $systemctl_cmd = $config->{command};
    #default service is openvpn@ovpn, where ovpn profile is a openvpn config located at /etc/openvpn/ovpn.conf
    my $openvpn_service = $config->{service};
    my $output = cmd($c, {no_debug_output =>1 }, $systemctl_cmd, 'list-unit-files');
    #$c->log->debug( $output );
    if ($output =~/^openvpn.service/m) {
        $res = 1;
    }
    return $res;
}

sub toggle_openvpn {
    my ($c, $set_active) = @_;
    my ($message, $error);
    my $config = $c->config->{openvpn} // {};
    my $systemctl_cmd = $config->{command};
    #default service is openvpn@ovpn, where ovpn profile is a openvpn config located at /etc/openvpn/ovpn.conf
    my $openvpn_service = $config->{service};
    my $status_in = check_openvpn_status($c);
    my $status_out;
    if (!$status_in->{allowed}) {
        $error = $c->loc('Openvpn service is not enabled or host role is not allowed.');
    } elsif (!$status_in->{available}) {
        $error = $c->loc('Openvpn service is not avaialbe on the system.');
    } else {
        if ($set_active) {
            if ( $status_in->{active} ) {
                $message = $c->loc('Openvpn connection is already opened.');
            } else {
                my $status_enabled = { enabled => $status_in->{enabled} };
                if (!$status_enabled->{enabled}) {
                    $error = cmd($c, undef, $systemctl_cmd, 'enable', $openvpn_service);
                    if (!$error) {
                        my $status_enabled = check_openvpn_status($c, {
                                no_check_availability => 1, 
                                check_status          => 'enabled',
                            },
                        );
                    }
                }
                if ($status_enabled->{enabled}) {
                    $error = cmd($c, undef, $systemctl_cmd, 'start', $openvpn_service);
                    if (!$error) {
                        $status_out = check_openvpn_status($c, {
                                no_check_availability => 1, 
                            },
                        );
                        if ($status_out->{active}) {
                            $message = $c->loc('Openvpn connection open.');
                        } else {
                            $error = $c->loc('Can not open openvpn connection.');
                        }
                    }
                } else {
                    $error = $c->loc('Can not enable openvpn.');
                }
            }
        } else { #requested to close connection
            if ( !$status_in->{active} ) {
                $message = $c->loc('Openvpn connection is already closed.');
            } else {
                $error = cmd($c, undef, $systemctl_cmd, 'stop', $openvpn_service);
            }
            if (!$error) {
                $status_out = check_openvpn_status($c, {
                        no_check_availability => 1, 
                    },
                );
                if (!$status_out->{active}) {
                    $message = $c->loc('Openvpn connection closed.');
                } else {
                    $error = $c->loc('Can not close openvpn connection.');
                }
            }
        }
    }
    return $message, $error;
}

sub cmd {
    my($c, $params, $cmd, @cmd_args) = @_;
    $params //= {};
    my $cmd_full = $cmd.' '.join(' ', @cmd_args);
    $c->log->debug( $cmd_full );
    my $output = '';
    try {
        $output = capturex([0..1,3], $cmd, @cmd_args);
        $output =~s/^\s+|\s+$//g;
        $c->log->debug( "output=$output;" ) unless $params->{no_debug_output};
    } catch ($e) {
        $c->log->debug( "error=$e;" );
        return $e;
    }
    return $output;
}

1;
