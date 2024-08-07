package NGCP::Panel::Utils::Form;

use Sipwise::Base;
use Data::Password::zxcvbn qw(password_strength);
use NGCP::Panel::Utils::Auth;

sub validate_password {
    my %params = @_;
    my $c = $params{c};
    my $field = $params{field};
    my $pass_change = $params{password_change};
    my $pw = $c->config->{security}{password};
    my $utf8 = $params{utf8} // 1;
    my $pass = $field->value;

    my $minlen = $pw->{min_length} // 12;
    my $maxlen = $pw->{max_length} // 40;

    my $is_sip_password = 0;
    my $is_web_password = 0;
    my $is_admin_password = 0;

    if ($params{admin}) {
        $is_admin_password = 1;
    } elsif ($field->name eq 'password') {
        $is_sip_password = 1;
    } elsif ($field->name eq 'webpassword') {
        $is_web_password = 1;
    } elsif ($field->name eq 'new_password') {
        $is_web_password = 1;
    }

    if ($is_sip_password) {
        return unless $pw->{sip_validate};
    } elsif ($is_web_password || $is_admin_password) {
        return unless $pw->{web_validate};
    } else {
        return;
    }

    if(length($pass) < $minlen) {
        $field->add_error($c->loc('Must be at minimum [_1] characters long', $minlen));
    }
    if(length($pass) > $maxlen) {
        $field->add_error($c->loc('Must be at maximum [_1] characters long', $maxlen));
    }
    if ($pass =~ /\s/) {
        $field->add_error($c->loc("Must not contain spaces"));
    }

    if(my $c_check = $pw->{musthave_lowercase}) {
        my $count = 0;
        map { $_ =~ /^[a-z]$/ and $count++ } split(//, $pass);
        if ($count < $c_check) {
            $field->add_error($c->loc("Must contain at least $c_check lower-case characters"));
        }
    }
    if(my $c_check = $pw->{musthave_uppercase}) {
        my $count = 0;
        map { $_ =~ /^[A-Z]$/ and $count++ } split(//, $pass);
        if ($count < $c_check) {
            $field->add_error($c->loc("Must contain at least $c_check upper-case characters"));
        }
    }
    if(my $c_check = $pw->{musthave_digit}) {
        my $count = 0;
        map { $_ =~ /^[0-9]$/ and $count++ } split(//, $pass);
        if ($count < $c_check) {
            $field->add_error($c->loc("Must contain at least $c_check digits"));
        }
    }
    if(my $c_check = $pw->{musthave_specialchar}) {
        my $count = 0;
        map { $_ =~ /^[^0-9a-zA-Z]$/ and $count++ } split(//, $pass);
        if ($count < $c_check) {
            $field->add_error($c->loc("Must contain at least $c_check special characters"));
        }
    }
    if (!$utf8 && $pass && !NGCP::Panel::Utils::Auth::check_password($pass)) {
        $field->add_error($c->loc('Contains invalid characters'));
    }
    my $res = password_strength($pass);
    if ($res->{score} < 3) {
        $field->add_error($c->loc('Password is too weak'));
    }

    my $lp_rs;
    my $check_last_passwords = 0;
    if ($is_sip_password) {
        my $user;
        my $prov_sub = $c->stash->{subscriber}
                        ? $c->stash->{subscriber}->provisioning_voip_subscriber
                        : undef;
        if ($pass_change && !$prov_sub) {
            $prov_sub = $c->user->provisioning_voip_subscriber;
        }
        if ($field->form->field('username')) {
            $user = $field->form->field('username')->value;
        } elsif ($prov_sub) {
            $user = $prov_sub->username;
        }
        if (defined $user && $pass =~ /$user/i) {
            $field->add_error($c->loc('Must not contain username'));
        }
        if ($pass && $prov_sub && $pass ne $prov_sub->password) {
            $lp_rs = $prov_sub->last_passwords;
            $check_last_passwords = 1;
        }
    } elsif($field->name eq "webpassword" && $pw->{web_validate}) {
        my $user;
        my $prov_sub = $c->stash->{subscriber}
                ? $c->stash->{subscriber}->provisioning_voip_subscriber
                : undef;
        if ($pass_change && !$prov_sub) {
            $prov_sub = $c->user->provisioning_voip_subscriber;
        }
        if ($field->form->field('webusername')) {
            $user = $field->form->field('webusername')->value;
        } elsif($prov_sub) {
            $user = $prov_sub->webusername;
        }
        if(defined $user && $pass =~ /$user/i) {
            $field->add_error($c->loc('Must not contain username'));
        }
        if ($pass && $prov_sub) {
            $lp_rs = $prov_sub->last_webpasswords;
            $check_last_passwords = 1;
        }
    } elsif ($is_admin_password) {
        my $user;
        my $admin = $c->stash->{administrator} // undef;
        if ($pass_change && !$admin) {
            $admin = $c->user;
        }
        if ($field->form->field('login')) {
            $user = $field->form->field('login')->value;
        } elsif($admin) {
            $user = $admin->login;
        }
        if (defined $user && $pass =~ /$user/i) {
            $field->add_error($c->loc('Must not contain login'));
        }
        if ($pass && $admin) {
            $lp_rs = $admin->last_passwords;
            $check_last_passwords = 1;
        }
    }
    if ($check_last_passwords) {
        my $bcrypt_cost = 6;
        foreach my $row ($lp_rs->all) {
            my $last_password = $row->value;
            my $enc_pass = $NGCP::Panel::Utils::Auth::ENCRYPT_SUBSCRIBER_WEBPASSWORDS
                                ? NGCP::Panel::Utils::Auth::get_usr_salted_pass($last_password, $pass, $bcrypt_cost)
                                : $pass;
            if ($last_password eq $enc_pass) {
                $field->add_error($c->loc('Password was previously used'));
                last;
            }
        }
    }
}

sub validate_entities {
    my (%params) = @_;
    
    #usage:
    #1. last unless validate_entities(c => $c, contracts => 4711, customers => 4712);
    #2. return unless validate_entities(c => $c, resource => $json, contract_id => 'contracts');
    #3. my $entities = {}; last unless validate_entities(c => $c, resource => $json,
    #    parent_id => $c->user->reseller_id,
    #    profile_id => { resultset => 'billing_profiles',
    #                    optional => 1,
    #                    parent_field => 'reseller_id',
    #                    deleted_field => 'status',
    #                    deleted_value => 'terminated'},
    #    entities => $entities);
    #4. last unless validate_entities(..., error => sub { $self->error($c, HTTP_UNPROCESSABLE_ENTITY, shift); });
    #5. validation in form handlers...
    
    my @args = qw/c resource parent_id error entities/;
    my ($c,$res,$parent_id,$err_code,$entities) = delete @params{@args};    

    my $schema = $c->model('DB');
    if ('CODE' ne ref $err_code) {
        $err_code = sub { return; };
    }
    
    my $validate_field = sub {
        my $name = shift;
        my $field = $params{$name}; # { id, resultset, optional, deleted_field, deleted_value, parent_field }
        my $is_res = 'HASH' eq ref $res;
        if ('HASH' ne ref $field) {
            $field = { ($is_res ? 'resultset' : 'id'), $field };
        }
        if ($is_res) {
            $field->{id} = $res->{$name} if !exists $field->{id};
            $field->{label} //= "'" . $name . "'";
        } else {
            $field->{resultset} //= $name;
            $field->{label} //= $name . ' ID';
        }
        $field->{optional} //= 0;
        $field->{hfh_field} //= $name;
        if (!$field->{optional} && !defined $field->{id}) {
            return 0 unless &{$err_code}("Invalid $field->{label}, not defined.",$field->{hfh_field});
        }
        my $entity = undef;
        eval {
            $entity = (defined $field->{id} ? $schema->resultset($field->{resultset})->find({id => $field->{id}},($field->{lock} ? {for => 'update'} : undef)) : undef);
        };
        if ($@) {
            return 0 unless &{$err_code}($@,$field->{hfh_field});
        }
        if (defined $field->{id} && !defined $entity) {
            return 0 unless &{$err_code}("Invalid $field->{label} ($field->{id}).",$field->{hfh_field});
        }
        if (defined $field->{deleted_field} && defined $field->{deleted_value} && defined $entity) {
            my $deleted_accessor = $field->{deleted_field};
            if (defined $entity->$deleted_accessor() && $field->{deleted_value} eq $entity->$deleted_accessor()) {
                return 0 unless &{$err_code}("Invalid $field->{label} ($field->{id}), $field->{deleted_value}.",$field->{hfh_field});
            }
        }
        if (defined $parent_id && defined $field->{parent_field} && defined $entity) {
            my $parent_accessor = $field->{parent_field};
            if (defined $entity->$parent_accessor() && $parent_id != $entity->$parent_accessor()) {
                return 0 unless &{$err_code}("The $field->{parent} of $field->{label} (" . $entity->$parent_accessor() . ") doesn't match.",$field->{hfh_field});
            }
        }
        if ('HASH' eq ref $entities) {
            $entities->{$name} = $entity;
        }
        return 1;
    };

    foreach my $name (keys %params) {
        return 0 unless &$validate_field($name);
    }  
    
    return 1;
}

sub validate_number_uri {
    my %params = @_;
    my $c = $params{c};
    my $field = $params{field};
    my $val = $field->value;

    unless ($val =~ /^\s*(sip:)*[[:lower:][:upper:][:digit:]+=,;_.~'()!*-]+\@[\w\d\-_\.]+\s*$/ ||
            $val =~ /^\s*\+*[0-9a-z]+\s*$/i) {
        $field->add_error($c->loc('Must be either a number or user@domain format.'));
    }
}

1;

# vim: set tabstop=4 expandtab:
