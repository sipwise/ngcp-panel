package NGCP::Panel::Utils::Auth;

use Sipwise::Base;
use Crypt::Eksblowfish::Bcrypt qw/bcrypt_hash en_base64 de_base64/;
use Data::Entropy::Algorithms qw/rand_bits/;
use IO::Compress::Zip qw/zip/;
use IPC::System::Simple qw/capturex/;
use UUID;

use NGCP::Panel::Utils::Ldap qw(
    auth_ldap_simple
    get_user_dn

    $ldapconnecterror
    $ldapnouserdn
    $ldapauthfailed
    $ldapsearchfailed
    $ldapnousersfound
    $ldapmultipleusersfound
    $ldapuserfound
    $ldapauthsuccessful
);

our $local_auth_method = 'local';
our $ldap_auth_method = 'ldap';

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
    my $bcrypt_cost = shift // get_bcrypt_cost();

    my $salt = rand_bits($SALT_LENGTH);
    my $b64salt = en_base64($salt);
    my $b64hash = en_base64(bcrypt_hash({
        key_nul => 1,
        cost => $bcrypt_cost,
        salt => $salt,
    }, $pass));
    return $b64salt . '$' . $b64hash;
}

sub get_usr_salted_pass {
    my ($saltedpass, $pass, $opt_cost) = @_;
    my ($db_b64salt, $db_b64hash) = split /\$/, $saltedpass;
    my $salt = de_base64($db_b64salt);
    my $usr_b64hash = en_base64(bcrypt_hash({
        key_nul => 1,
        cost => $opt_cost // get_bcrypt_cost(),
        salt => $salt,
    }, $pass));
    return $db_b64salt . '$' . $usr_b64hash;
}

sub perform_auth {
    my ($c, $user, $pass, $realm, $bcrypt_realm) = @_;

    my $res;
    my $log_failed_login_attempt = 1;

    return $res if !check_password($pass);
    return -2 if user_is_banned($c, $user, 'admin');

    my $dbadmin;
    $dbadmin = $c->model('DB')->resultset('admins')->find({
        login => $user,
        is_active => 1,
    }) if $user;
    return $res unless $dbadmin;

    if ($dbadmin->auth_mode eq $local_auth_method) {
        if (defined $dbadmin->saltedpass) {
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
        } else {
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
    } elsif ($dbadmin->auth_mode eq $ldap_auth_method) {
        $c->log->debug("login via ldap");
        my ($code,$message) = auth_ldap_simple($c,get_user_dn($c,$user),$pass);
        if ($code == $ldapauthfailed) {
            $res = 0;
        } elsif ($code != $ldapauthsuccessful) {
            $res = 0;
            $log_failed_login_attempt = 0; # do not log failed attempt if there was an ldap error
        } else {
            $res = 1;
            $c->set_authenticated($dbadmin); # logs the user in and calls persist_user
        }
    }

    $res ? do {
        clear_failed_login_attempts($c, $user, 'admin');
        reset_ban_increment_stage($c, $user, 'admin');
    }
    : ($log_failed_login_attempt && log_failed_login_attempt($c, $user, 'admin'));

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

    my $userdom = $domain ? $user . '@' . $domain : $user;
    return -2 if user_is_banned($c, $userdom, 'subscriber');

    my $authrs = $c->model('DB')->resultset('provisioning_voip_subscribers')->search({
        webusername => $user,
        'voip_subscriber.status' => 'active',
        ($c->config->{features}->{multidomain} ? ('domain.domain' => $domain) : ()),
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

    $res ? do {
        clear_failed_login_attempts($c, $userdom, 'subscriber');
        reset_ban_increment_stage($c, $userdom, 'subscriber');
    }
    : log_failed_login_attempt($c, $userdom, 'subscriber');

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
    if ($output =~ /^openvpn.service/m) {
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
    my $redis = $c->redis_get_connection({database => $c->config->{'Plugin::Session'}->{redis_db}});
    unless ($redis) {
        return {success => 0, error => "Failed to connect to central redis url " . $c->config->{redis}->{central_url}};
    }
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
    my $redis = $c->redis_get_connection({database => $c->config->{'Plugin::Session'}->{redis_db}});

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

sub get_user_domain {
    my ($c, $user) = @_;

    my ($p_user, $p_domain, $t) = split(/\@/, $user, 3);
    if (defined $t) {
        # in case username is an email address
        $p_user = $p_user . '@' . $p_domain;
        $p_domain = $t;
    }
    unless(defined $p_domain) {
        $p_domain = $c->req->uri->host;
    }

    return ($p_user, $p_domain);
}

sub user_is_banned {
    my ($c, $user, $realm) = @_;

    my $ip = $c->request->address;
    my $redis = $c->redis_get_connection({database => $c->config->{'Plugin::Session'}->{redis_db}});

    my ($p_user, $p_domain) = get_user_domain($c, $user);

    my $key = "login:ban:$p_user:$p_domain:$realm:$ip";

    return $redis->exists($key) ? 1 : 0;
}

sub log_failed_login_attempt {
    my ($c, $user, $realm) = @_;

    return unless $c->config->{security}{login}{ban_enable};
    my $expire = $c->config->{security}{login}{ban_max_time} // 3600;
    my $max_attempts = $c->config->{security}{login}{max_attempts} // return;
    my $ip = $c->request->address;

    my $redis = $c->redis_get_connection({database => $c->config->{'Plugin::Session'}->{redis_db}});

    my ($p_user, $p_domain) = get_user_domain($c, $user);

    my $key = "login:fail:$p_user:$p_domain:$realm:$ip";
    my $attempted = ($redis->hget($key, 'attempts') // 0) + 1;
    $attempted >= $max_attempts
        ? ban_user($c, $user, $realm)
        : do {
             $redis->multi();
             $redis->hset($key, 'attempts', $attempted);
             $redis->hset($key, 'last_attempt', time());
             $redis->expire($key, $expire // 3600); # always expire invalid login attempts
             $redis->exec();
        };

    return;
}

sub clear_failed_login_attempts {
    my ($c, $user, $realm) = @_;

    my ($p_user, $p_domain) = get_user_domain($c, $user);

    my $ip = $c->request->address;
    my $key = "login:fail:$p_user:$p_domain:$realm:$ip";

    my $redis = $c->redis_get_connection({database => $c->config->{'Plugin::Session'}->{redis_db}});

    $redis->del($key);

    return;
}

sub reset_ban_increment_stage {
    my ($c, $user, $realm) = @_;

    my ($p_user, $p_domain) = get_user_domain($c, $user);

    my $usr_rs;
    if ($realm eq 'admin') {
        $usr_rs = $c->model('DB')->resultset('admins')->search({
            login => $p_user,
        })->first;
    } elsif ($realm eq 'subscriber') {
        $usr_rs = $c->model('DB')->resultset('provisioning_voip_subscribers')->search({
            webusername => $p_user,
            'domain.domain' => $p_domain,
        }, {
            join => 'domain',
        })->first;
    }
    if ($usr_rs) {
        my $ip = $c->request->address;
        $c->log->debug("Reset ban increment for user=$p_user domain=$p_domain realm=$realm ip=$ip");
        $usr_rs->update({ban_increment_stage => 0});
    }

    return;
}

sub ban_user {
    my ($c, $user, $realm, $domain) = @_;

    return unless $c->config->{security}{login}{ban_enable};
    my $min_time = $c->config->{security}{login}{ban_min_time} // 300;
    my $max_time = $c->config->{security}{login}{ban_max_time} // 3600;
    my $increment = $c->config->{security}{login}{ban_increment} // 300;

    my ($p_user, $p_domain) = get_user_domain($c, $user);

    my $ip = $c->request->address;
    my $key = "login:ban:$p_user:$p_domain:$realm:$ip";

    my $increment_stage = -1;
    my $expire = 3600;

    my $usr_rs;
    if ($realm eq 'admin') {
        $usr_rs = $c->model('DB')->resultset('admins')->search({
            login => $p_user,
        })->first;
        if ($usr_rs) {
            $increment_stage = $usr_rs->ban_increment_stage;
        }
    } elsif ($realm eq 'subscriber') {
        $usr_rs = $c->model('DB')->resultset('provisioning_voip_subscribers')->search({
            webusername => $p_user,
            'domain.domain' => $p_domain,
        },{
            join => 'domain',
        })->first;
        if ($usr_rs) {
            $increment_stage = $usr_rs->ban_increment_stage;
        }
    }

    if ($increment_stage >= 0) {
        $expire = $min_time + $increment*$increment_stage;
        $expire = $max_time if $expire > $max_time;
        $increment_stage++;
    }

    $c->log->info("Ban user=$p_user domain=$p_domain realm=$realm ip=$ip stage=$increment_stage for $expire seconds");

    my $redis = $c->redis_get_connection({database => $c->config->{'Plugin::Session'}->{redis_db}});

    $redis->hset($key, 'banned_at', time());
    $redis->expire($key, $expire) if $expire;

    if ($increment_stage > 0 && $usr_rs) {
        $usr_rs->update({ban_increment_stage => $increment_stage});
    }

    clear_failed_login_attempts($c, $user, $realm);

    return;
}

sub check_max_age {
    my $c = shift;
    my ($auth_user, $ngcp_realm) = @_;

    my $pass_last_modify;
    my $pass_last_modify_time;

    if ($auth_user && $ngcp_realm) {
        if ($ngcp_realm eq 'admin') {
            $pass_last_modify = $auth_user->saltedpass_modify_timestamp;
        } else {
            $pass_last_modify = $auth_user->webpassword_modify_timestamp;
        }
    } else {
        return 1 unless $c->user;

        if ($c->user->roles eq 'subscriber' || $c->user->roles eq 'subscriberadmin') {
            $pass_last_modify = $c->user->webpassword_modify_timestamp;
        } else {
            $pass_last_modify = $c->user->saltedpass_modify_timestamp;
        }
    }

    my $strp = DateTime::Format::Strptime->new(
        pattern => '%Y-%m-%dT%H:%M:%S',
        time_zone => 'local',
    );

    if (my $dt = $strp->parse_datetime($pass_last_modify // '')) {
        $pass_last_modify_time = $dt->epoch;
    }

    if ($pass_last_modify_time) {
        my $max_age = $c->config->{security}{password}{web_max_age_days} // 0;
        if (defined $max_age && $max_age > 0) {
            if ($pass_last_modify_time < (time()-$max_age*24*60*60)) {
                return;
            }
        }
    }

    return 1;
}

1;
