package NGCP::Panel::Utils::Auth;

use Sipwise::Base;
use Crypt::Eksblowfish::Bcrypt qw/bcrypt_hash en_base64 de_base64/;
use Data::Entropy::Algorithms qw/rand_bits/;
use IO::Compress::Zip qw/zip/;
use IPC::System::Simple qw/capturex/;
use Redis;
use UUID;
use NGCP::Panel::Utils::Redis;

our $SALT_LENGTH = 128;
our $ENCRYPT_SUBSCRIBER_WEBPASSWORDS = 1;

sub check_password {
    my $pass = shift // return;

    return if $pass =~ /[^[:ascii:]]/;

    return 1;
}

sub get_special_admin_login {
    return 'sipwise';
}

sub get_bcrypt_cost {
    return 13;
}

sub generate_salted_hash {
    my $pass = shift;

    my $salt = rand_bits($SALT_LENGTH);
    my $b64salt = en_base64($salt);
    my $b64hash = en_base64(bcrypt_hash({
        key_nul => 1,
        cost => get_bcrypt_cost(),
        salt => $salt,
    }, $pass));
    return $b64salt . '$' . $b64hash;
}

sub get_usr_salted_pass {
    my ($saltedpass, $pass) = @_;
    my ($db_b64salt, $db_b64hash) = split /\$/, $saltedpass;
    my $salt = de_base64($db_b64salt);
    my $usr_b64hash = en_base64(bcrypt_hash({
        key_nul => 1,
        cost => get_bcrypt_cost(),
        salt => $salt,
    }, $pass));
    return $db_b64salt . '$' . $usr_b64hash;
}

sub perform_auth {
    my ($c, $user, $pass, $realm, $bcrypt_realm) = @_;
    my $res;

    return $res unless check_password($pass);

    my $dbadmin;
    $dbadmin = $c->model('DB')->resultset('admins')->find({
        login => $user,
        is_active => 1,
    }) if $user;
    if(defined $dbadmin && defined $dbadmin->saltedpass) {
        $c->log->debug("login via bcrypt");
        my $saltedpass = $dbadmin->saltedpass;
        my $usr_salted_pass = get_usr_salted_pass($saltedpass, $pass);
        # fetch again to load user into session etc (otherwise we could
        # simply compare the two hashes here :(
        $res = $c->authenticate(
            {
                login => $user,
                saltedpass => $usr_salted_pass,
                'dbix_class' => {
                    searchargs => [{
                        -and => [
                            login => $user,
                            is_active => 1,
                        ],
                    }],
                }
            }, $bcrypt_realm
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
            }, $realm);

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

sub is_salted_hash {
    
    my $password = shift;
    if (length($password)
        and (length($password) == 54 or length($password) == 56)
        and $password =~ /\$/) {
        return 1;
    }
    return 0;
    
}

sub perform_subscriber_auth {
    my ($c, $user, $domain, $pass) = @_;
    my $res;

    if ($pass && $pass =~ /[^[:ascii:]]/) {
        return $res;
    }

    my $authrs = $c->model('DB')->resultset('provisioning_voip_subscribers')->search({
        webusername => $user,
        'voip_subscriber.status' => 'active',
        'domain.domain' => $domain,
        'contract.status' => 'active',
    }, {
        join => ['domain', 'contract', 'voip_subscriber'],
    });

    my $sub = $authrs->first;
    if(defined $sub && defined $sub->webpassword) {
        my $sub_pass = $sub->webpassword;
        if (length $sub_pass > 40) {
            my @splitted_pass = split /\$/, $sub_pass;
            if (scalar @splitted_pass == 3) {
                #password is bcrypted with lower cost
                my ($cost, $db_b64salt, $db_b64hash) = @splitted_pass;
                my $salt = de_base64($db_b64salt);
                my $usr_b64hash = en_base64(bcrypt_hash({
                    key_nul => 1,
                    cost => $cost,
                    salt => $salt,
                }, $pass));
                if ($db_b64hash eq $usr_b64hash) {
                    #upgrade password to bigger cost
                    $salt = rand_bits($SALT_LENGTH);
                    my $b64salt = en_base64($salt);
                    my $b64hash = en_base64(bcrypt_hash({
                        key_nul => 1,
                        cost => get_bcrypt_cost(),
                        salt => $salt,
                    }, $pass));
                    $sub->update({webpassword => $b64salt . '$' . $b64hash});
                    $res = $c->authenticate(
                        {
                            webusername => $user,
                            webpassword => $b64salt . '$' . $b64hash,
                            'dbix_class' => {
                                resultset => $authrs
                            }
                        },
                        'subscriber');
                }
            }
            elsif (scalar @splitted_pass == 2) {
                #password is bcrypted with proper cost
                my ($db_b64salt, $db_b64hash) = @splitted_pass;
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
                        webusername => $user,
                        webpassword => $db_b64salt . '$' . $usr_b64hash,
                        'dbix_class' => {
                            resultset => $authrs
                        }
                    },
                    'subscriber');
                }
        }
        else {
            $res = $c->authenticate(
                {
                    webusername => $user,
                    webpassword => $pass,
                    'dbix_class' => {
                        resultset => $authrs
                    }
                },
                'subscriber');
        }
    }
    return $res;
}

sub generate_client_cert {
    my ($c, $admin, $error_cb) = @_;

    my $updated;
    my ($serial, $pem, $p12);
    $serial = $c->model('DB')->resultset('admins')->get_column('ssl_client_m_serial')->max();
    if ($serial) {
        $serial++;
    } else {
        $serial = time;
    }
    while (!$updated) {
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
    my $output = cmd($c, {no_debug_output =>1 }, $systemctl_cmd, 'list-unit-files', 'openvpn.service');
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
        $error = $c->loc('Openvpn service is not available on the system.');
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

sub initiate_password_reset {
    my ($c, $admin) = @_;
    # don't clear password, a user might just have guessed it and
    # could then block the legit user out
    my ($uuid_bin, $uuid_string);
    UUID::generate($uuid_bin);
    UUID::unparse($uuid_bin, $uuid_string);
    my $redis = Redis->new(
        server => $c->config->{redis}->{central_url},
        reconnect => 10, every => 500000, # 500ms
        cnx_timeout => 3,
    );
    unless ($redis) {
        return {success => 0, error => "Failed to connect to central redis url " . $c->config->{redis}->{central_url}};
    }
    $redis->select($c->config->{'Plugin::Session'}->{redis_db});
    my $username = $admin->login;
    if ($redis->exists("password_reset:admin::$username")) {
        return {success => 0, error => 'A password reset attempt has been made already recently, please check your email.'};
    }
    else {
        $redis->hset("password_reset:admin::$username", 'token', $uuid_string);
        $redis->expire("password_reset:admin::$username", 300);
        $redis->hset("password_reset:admin::$uuid_string", 'user', $username);
        $redis->hset("password_reset:admin::$uuid_string", 'ip', $c->req->address);
        $redis->expire("password_reset:admin::$uuid_string", 300);

        my $url = $c->req->header('Referer') && $c->req->header('Referer') =~ /\/v2\// ?
                  $c->req->base . 'v2/#/recoverpassword' :
                  $c->uri_for_action('/login/recover_password')->as_string;
        $url= NGCP::Panel::Utils::Email::rewrite_url(
            $c->config->{contact}->{external_base_url},$url);
        $url .= '?token=' . $uuid_string;

        NGCP::Panel::Utils::Email::admin_password_reset($c, $admin, $url);
    }
    return {success => 1};
}

sub generate_auth_token {
    my ($self, $c, $type, $role, $user_id, $expires) = @_;

    my ($uuid_bin, $uuid_string);
    my $redis = NGCP::Panel::Utils::Redis::get_redis_connection($c, {database => $c->config->{'Plugin::Session'}->{redis_db}});

    unless ($redis) {
        $c->log->error("Could not generate auth token for user $user_id, no Redis connection available");
        return;
    }

    $expires //= 10; # auto expire the token in 10 seconds if the value is not provided

    my $expire_time = time+10;

    UUID::generate($uuid_bin);
    UUID::unparse($uuid_bin, $uuid_string);
    #remove '-' from the token
    $uuid_string =~ s/\-//g;
    $redis->hset("auth_token:$uuid_string", 'type', $type);
    $redis->hset("auth_token:$uuid_string", 'role', $role);
    $redis->hset("auth_token:$uuid_string", 'user_id', $user_id);
    $redis->hset("auth_token:$uuid_string", 'exp', $expire_time);
    $redis->expire("auth_token:$uuid_string", $expires);

    $c->log->debug(sprintf "Generated auth_token=%s type=%s role=%s user_id=%s expires=%d expire_time=%d",
                    $uuid_string, $type, $role, $user_id, $expires, $expire_time);

    return $uuid_string;
}

1;
