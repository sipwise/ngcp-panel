package NGCP::Panel::Utils::Subscriber;
use strict;
use warnings;

use Sipwise::Base;

use NGCP::Panel::Utils::Generic qw(:all);

use DBIx::Class::Exception;
use String::MkPasswd;
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Preferences;
use NGCP::Panel::Utils::Email;
use NGCP::Panel::Utils::Events;
use NGCP::Panel::Utils::DateTime qw();
use NGCP::Panel::Utils::License;
use NGCP::Panel::Utils::Generic;
use NGCP::Panel::Utils::RedisLocationResultSet;
use UUID qw/generate unparse/;
use JSON qw/decode_json encode_json/;
use HTTP::Status qw(:constants);
use IPC::System::Simple qw/capturex/;
use File::Slurp qw/read_file/;
use Redis;

my %LOCK = (
    0, 'none',
    1, 'foreign',
    2, 'outgoing',
    3, 'incoming and outgoing',
    4, 'global',
    5, 'ported',
);

sub get_subscriber_location_rs {
    my ($c, $filter) = @_;
    if ($c->config->{redis}->{usrloc}) {
        my $redis;
        try {
            $redis = Redis->new(
                server => $c->config->{redis}->{central_url},
                reconnect => 10, every => 500000, # 500ms
                cnx_timeout => 3,
            );
            unless ($redis) {
                $c->log->error("Failed to connect to central redis url " . $c->config->{redis}->{central_url});
                return;
            }
            $redis->select($c->config->{redis}->{usrloc_db});
            my $rs = NGCP::Panel::Utils::RedisLocationResultSet->new(_redis => $redis, _c => $c);
            $rs = $rs->search($filter);
            return $rs;
        } catch($e) {
            $c->log->error("Failed to fetch location information from redis: $e");
            return;
        }
    } else {
        my $reg_rs = $c->model('DB')->resultset('location')->search({
            username => $filter->{username},
        });
        if($c->config->{features}->{multidomain}) {
            $reg_rs = $reg_rs->search({
                domain => $filter->{domain},
            });
        }
        return $reg_rs;
    }
}

sub period_as_string {
    my $set = shift;

    my @wdays = (qw/
        invalid Sunday Monday Tuesday Wednesday Thursday Friday Saturday
    /);
    my @months = (qw/
        invalid January February March April May June July August September October November December
    /);

    my $string = "";
    foreach my $type(qw/year month mday wday hour minute/) {
        my $s = $set->{$type};
        if(defined $s) {
            SWITCH: for ($type) {
                /^month$/ && do {
                    my ($from, $to) = split /\-/, $s;
                    $s = $months[$from];
                    $s .= '-'.$months[$to] if defined($to);
                    last SWITCH;
                };
                /^wday$/ && do {
                    my ($from, $to) = split /\-/, $s;
                    $s = $wdays[$from];
                    $s .= '-'.$wdays[$to] if defined($to);
                    last SWITCH;
                };
                # default
            } # SWITCH
        }
        $string .= "$type { $s } " if defined($s);
    }
    return $string;
}

sub destination_as_string {
    my ($c, $destination, $prov_subscriber, $direction) = @_;
    my $dest = $destination->{destination};

    if($dest =~ /\@voicebox\.local$/) {
        return "VoiceMail";
    } elsif($dest =~ /\@fax2mail\.local$/) {
        return "Fax2Mail";
    } elsif($dest =~ /\@conference\.local$/) {
        return "Conference";
    } elsif($dest =~ /^sip:callingcard\@app\.local$/) {
        return "CallingCard";
    } elsif($dest =~ /^sip:callthrough\@app\.local$/) {
        return "CallThrough";
    } elsif($dest =~ /^sip:localuser\@.+\.local$/) {
        return "Local Subscriber";
    } elsif($dest =~ /^sip:auto-attendant\@app\.local$/) {
        return "Auto Attendant";
    } elsif($dest =~ /^sip:office-hours\@app\.local$/) {
        return "Office Hours Announcement";
    } elsif($dest =~ /^sip:custom-hours\@app\.local$/) {
        return "Custom Announcement";
    } elsif($dest =~ /\@managersecretary\.local$/) {
        my $sn_rs = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                c => $c, attribute => 'secretary_numbers',
                prov_subscriber => $prov_subscriber);
        my @sn_list = ();
        if ($sn_rs) {
            foreach my $l ($sn_rs->all) {
                next if $l->value =~ /^#/;
                push @sn_list, $l->value;
            }
        }
        return "MS to " . (@sn_list ? join(',', @sn_list) : 'unknown');
    } else {
        my $d = $dest;
        $d =~ s/^sips?://;
        my $b_subscriber = $prov_subscriber
            ? $prov_subscriber->voip_subscriber
            : undef;
        $direction //= 'caller_out';
        if($b_subscriber && ($c->user->roles eq "subscriberadmin" || $c->user->roles eq "subscriber")) {
            my ($user, $domain) = split(/\@/, $d);
            $domain //= $b_subscriber->domain->domain;
            $user = NGCP::Panel::Utils::Subscriber::apply_rewrite(
                c => $c, subscriber => $b_subscriber, number => $user, direction => $direction
            );
            if($domain eq $b_subscriber->domain->domain) {
                $d = $user;
            } else {
                $d = $user . '@' . $domain;
            }
        }
        return $d;
    }
}

sub lock_provisoning_voip_subscriber {
    my %params = @_;

    if ($params{c} and $params{prov_subscriber}) {
        if ($params{level}) {
            $params{c}->log->debug('set subscriber ' . $params{prov_subscriber}->username . ' lock level: ' . $params{level});
        } else {
            $params{c}->log->debug('remove subscriber ' . $params{prov_subscriber}->username . ' lock level');
        }
    }

    NGCP::Panel::Utils::Preferences::set_provisoning_voip_subscriber_first_int_attr_value(%params,
        value => $params{level},
        attribute => 'lock'
        );
}

sub get_provisoning_voip_subscriber_lock_level {
    my %params = @_;

    return NGCP::Panel::Utils::Preferences::get_provisoning_voip_subscriber_first_int_attr_value(%params,
        attribute => 'lock'
        );
}

sub switch_prepaid {
    my %params = @_;

}

sub switch_prepaid_contract {
    my %params = @_;

}

sub get_lock_string {
    my $level = shift;
    return $LOCK{$level};
}

sub create_subscriber {
    my %params = @_;
    my $c = $params{c};

    my $contract = $params{contract};
    my $params = $params{params};
    my $administrative = $params{admin_default};
    my $preferences = $params{preferences};
    my $event_context = $params{event_context} // {};

    my $schema = $params{schema} // $c->model('DB');
    my $reseller = $contract->contact->reseller;
    my $billing_domain = $schema->resultset('domains')
            ->find($params->{domain}{id} // $params->{domain_id});
    my $prov_domain = $schema->resultset('voip_domains')
            ->find({domain => $billing_domain->domain});

    if (my $status = NGCP::Panel::Utils::License::is_license_error()) {
        $c->log->warn("invalid license status: $status");
        # die("invalid license status: $status");
    }
    if ($c->user->roles eq "reseller") {
        if ($contract->contact->reseller_id ne $c->user->reseller_id) {
            die("invalid contract id '".$contract->id."'");
        }
    } elsif ($c->user->roles eq "subscriberadmin" || $c->user->roles eq "subscriber") {#while we don't allow to create subscribers to subscriber role, of course
        if ($contract->id ne $c->user->account_id) {
            die("invalid contract id '".$contract->id."'");
        }
    }

    my($error,$profile_set,$profile) = check_profile_set_and_profile($c, $params);
    if ($error) {
        $params{error}->{extended} = $error if ref $params{error} eq 'HASH';
        die($error->{error});
    }

    $params->{timezone} = $params->{timezone}->{name} if 'HASH' eq ref $params->{timezone};
    if ($params->{timezone} && !NGCP::Panel::Utils::DateTime::is_valid_timezone_name($params->{timezone})) {
        die("invalid timezone name '$params->{timezone}' detected");
    }

    # if there is a contract default sound set, use it.
    my $default_sound_set = $contract->voip_sound_sets->search({ contract_default => 1 })->first;
    if($default_sound_set) {
        $preferences->{contract_sound_set} = $default_sound_set->id;
    }

    my $passlen = $c->config->{security}->{password_min_length} || 8;
    if($c->config->{security}->{password_sip_autogenerate} && !$params->{password}) {
        $params->{password} = String::MkPasswd::mkpasswd(
            -length => $passlen,
            -minnum => 1, -minlower => 1, -minupper => 1, -minspecial => 1,
            -distribute => 1, -fatal => 1,
        );
        #otherwise it breaks xml device configs
        $params->{password} =~s/[<>&]/,/g;
    }
    if($c->config->{security}->{password_web_autogenerate} && !$params->{webpassword}) {
        $params->{webpassword} = String::MkPasswd::mkpasswd(
            -length => $passlen,
            -minnum => 1, -minlower => 1, -minupper => 1, -minspecial => 1,
            -distribute => 1, -fatal => 1,
        );
    }

    $schema->txn_do(sub {
        my ($uuid_bin, $uuid_string);
        UUID::generate($uuid_bin);
        UUID::unparse($uuid_bin, $uuid_string);

        my $contact;

        if($params->{email} || $params->{timezone}) {
            $contact = $c->model('DB')->resultset('contacts')->create({
                reseller_id => $contract->contact->reseller_id,
            });
            if($params->{email}) {
                $contact->update({
                    email => $params->{email},
                });
            }
            if($params->{timezone}) {
                $contact->update({
                    timezone => $params->{timezone},
                });
            }
        }
        delete $params->{email};
        delete $params->{timezone};

        # TODO: check if we find a reseller and contract and domains

        my $billing_subscriber = $contract->voip_subscribers->create({
            uuid => $uuid_string,
            username => $params->{username},
            domain_id => $billing_domain->id,
            status => $params->{status},
            external_id => ((defined $params->{external_id} && length $params->{external_id}) ? $params->{external_id} : undef), # make null if empty
            primary_number_id => undef, # will be filled in next step
            contact_id => $contact ? $contact->id : undef,
        });
        unless(exists $params->{password}) {
            my ($pass_bin, $pass_str);
            UUID::generate($pass_bin);
            UUID::unparse($pass_bin, $pass_str);
            $params->{password} = $pass_str;
        }
        my $prov_subscriber = $schema->resultset('provisioning_voip_subscribers')->create({
            uuid => $uuid_string,
            username => $params->{username},
            password => $params->{password},
            webusername => $params->{webusername} || $params->{username},
            webpassword => $params->{webpassword},
            admin => $params->{administrative} // $administrative,
            account_id => $contract->id,
            domain_id => $prov_domain->id,
            is_pbx_pilot => $params->{is_pbx_pilot} // 0,
            is_pbx_group => $params->{is_pbx_group} // 0,
            pbx_extension => $params->{pbx_extension},
            pbx_hunt_policy => $params->{pbx_hunt_policy},
            pbx_hunt_timeout => $params->{pbx_hunt_timeout},
            profile_set_id => $profile_set ? $profile_set->id : undef,
            profile_id => $profile ? $profile->id : undef,
            create_timestamp => NGCP::Panel::Utils::DateTime::current_local,
        });

        my $aliases_before = NGCP::Panel::Utils::Events::get_aliases_snapshot(
            c => $c,
            schema => $schema,
            subscriber => $billing_subscriber,
        );
        $event_context->{aliases_before} = $aliases_before;

        if(defined $params->{e164range} && ref $params->{e164range} eq "ARRAY") {
            my @alias_numbers = ();
            foreach my $range(@{ $params->{e164range} }) {
                if(defined $range->{e164range}{cc} && $range->{e164range}{cc} ne '') {
                    my $len = $range->{e164range}{snlength};
                    if ($len) {
                        foreach my $ext(0 .. int("9" x $len)) {
                            $range->{e164range}{sn} = sprintf("%s%0".$len."d", $range->{e164range}{snbase}, $ext);
                            push @alias_numbers, { e164 => {
                                cc => $range->{e164range}{cc},
                                ac => $range->{e164range}{ac},
                                sn => $range->{e164range}{sn},
                            }};
                        }
                    } else {
                        push @alias_numbers, { e164 => {
                            cc => $range->{e164range}{cc},
                            ac => $range->{e164range}{ac},
                            sn => $range->{e164range}{snbase},
                        }};
                    }
                }
            }
            if(@alias_numbers) {

                # if no primary number was given, use the first from the range
                unless(defined $params->{e164}{cc} && $params->{e164}{cc} ne '') {
                    my $first_alias = shift @alias_numbers;
                    $params->{e164} = $first_alias->{e164};
                }
                update_subscriber_numbers(
                    c => $c,
                    schema => $schema,
                    subscriber_id => $billing_subscriber->id,
                    reseller_id => $reseller->id,
                    alias_numbers => \@alias_numbers,
                );
            }
        }

        my ($cli);
        if(defined $params->{e164}{cc} && $params->{e164}{cc} ne '') {
            $cli = $params->{e164}{cc} .
                ($params->{e164}{ac} || '') .
                $params->{e164}{sn};

            update_subscriber_numbers(
                c => $c,
                schema => $schema,
                subscriber_id => $billing_subscriber->id,
                reseller_id => $reseller->id,
                primary_number => $params->{e164},
            );
        }

        $schema->resultset('voicemail_users')->create({
            customer_id => $uuid_string,
            mailbox => $cli // $uuid_string,
            password => sprintf("%04d", int(rand 10000)),
            email => '',
            tz => 'vienna',
        });
        $preferences->{account_id} = $contract->id;
        $preferences->{ac} = $params->{e164}{ac}
            if(defined $params->{e164}{ac} && length($params->{e164}{ac}) > 0);
        $preferences->{cc} = $params->{e164}{cc}
            if(defined $params->{e164}{cc} && length($params->{e164}{cc}) > 0);

        update_preferences(c => $c,
            prov_subscriber => $prov_subscriber,
            preferences => $preferences
        );

        if($contract->subscriber_email_template_id) {
            my ($uuid_bin, $uuid_string);
            UUID::generate($uuid_bin);
            UUID::unparse($uuid_bin, $uuid_string);
            $billing_subscriber->password_resets->create({
                uuid => $uuid_string,
                # for new subs, let the link be valid for a year
                timestamp => NGCP::Panel::Utils::DateTime::current_local->epoch + 31536000,
            });
            my $url = $c->uri_for_action('/subscriber/recover_webpassword')->as_string . '?uuid=' . $uuid_string;
            NGCP::Panel::Utils::Email::new_subscriber($c, $billing_subscriber, $url);
        }

        #if($prov_subscriber->profile_id) {
            my $events_to_create = $event_context->{events_to_create};
            if (defined $events_to_create) {
                push(@$events_to_create,{
                    subscriber_id => $billing_subscriber->id,
                    type => 'profile', old => undef, new => $prov_subscriber->profile_id,
                    %$aliases_before,
                });
            } else {
                NGCP::Panel::Utils::Events::insert_profile_events(
                    c => $c, schema => $schema, subscriber_id => $billing_subscriber->id,
                    old => undef, new => $prov_subscriber->profile_id,
                    %$aliases_before,
                );
            }
        #}
        if($prov_subscriber->is_pbx_group) {
            my $events_to_create = $event_context->{events_to_create};
            if (defined $events_to_create) {
                push(@$events_to_create,{
                    subscriber_id => $billing_subscriber->id,
                    type => 'start_huntgroup', old => undef, new => $prov_subscriber->profile_id,
                    %$aliases_before,
                });
            } else {
                NGCP::Panel::Utils::Events::insert(
                    c => $c, schema => $schema, subscriber_id => $billing_subscriber->id,
                    type => 'start_huntgroup', old => undef, new => $prov_subscriber->profile_id,
                    %$aliases_before,
                );
            }
        }

        return $billing_subscriber;
    });
}

sub check_profile_set_and_profile {
    my ($c, $resource, $subscriber) = @_;
    
    my ($profile_set, $profile, $profile_set_rs);
    my $schema = $c->model('DB');

    my $prov_subscriber;
    if ($subscriber) { #edit
        $prov_subscriber = $subscriber->provisioning_voip_subscriber;
        #as we don't allow to change customer (l. 624), so we shouldn't allow profile_set that belongs to other reseller
        #this restriction also is related to admin, so we don't allow to make data uncoordinated
        $profile_set_rs = $schema->resultset('voip_subscriber_profile_sets')->search({
            'me.reseller_id' => $subscriber->contract->contact->reseller_id,
        });
    } else {
        $profile_set_rs = $schema->resultset('voip_subscriber_profile_sets');
    }
    if($c->user->roles eq "admin") {
        #we allow to admins (both superadmin and reseller admin roles)
        #to pick any profile_set, even not linked to pilot. 
        #it may lead to situation when subscriberadmin will not see profile options, as profile ajax call is based on pilot profile_set setting
        #this was old behavior and I left untouched this administrator privilege
    } elsif($c->user->roles eq "reseller") {
        $profile_set_rs = $profile_set_rs->search({
            'me.reseller_id' => $c->user->reseller_id,
        });
    }  elsif($c->user->roles eq "subscriberadmin") {
        if ($c->stash->{pilot} && $c->stash->{pilot}->provisioning_voip_subscriber->profile_set_id) {
            #$c->user->voip_subscriber->provisioning_voip_subscriber->profile_set_id
            #this is new condition, as now we allow subscriberadmin to edit subscribers using API
            #(and previousely we allowed to add)
            #and subscriberadmin should operate in boundaries of his own profile_set
            $profile_set_rs = $profile_set_rs->search({
                'me.id' => $c->stash->{pilot}->provisioning_voip_subscriber->profile_set_id
            });
        } else {
            #subscriberadmin is not supposed to add a pilot,
            #pilot will be created first by force, if not exists
            #but this situation still is possible if pilot doesn't have profile_set setting
            #then we will check at least reseller
            $profile_set_rs = $profile_set_rs->search({
                'me.reseller_id' => $c->user->contract->contact->reseller_id
            });
        }
    }
    use Data::Dumper;
    $c->log->debug(Dumper([
        "pilot:".($c->stash->{pilot} ? $c->stash->{pilot}->id:"undefined"),
        "pilot profile_set:".($c->stash->{pilot} && $c->stash->{pilot}->provisioning_voip_subscriber->voip_subscriber_profile_set ? $c->stash->{pilot}->provisioning_voip_subscriber->voip_subscriber_profile_set->id:"undefined"),
        "!exists profile_set.id:".((!exists $resource->{profile_set}{id}) ? "true":"false"),
        "c->user->roles eq subscriberadmin:".(($c->user->roles eq "subscriberadmin") ? "true":"false"),
    
    ]));
    if (defined $resource->{profile_set}{id} && $resource->{profile_set}{id}) {
        $profile_set = $profile_set_rs->find($resource->{profile_set}{id});
        unless($profile_set) {
            return {
                error         => "invalid subscriber profile set id '" . $resource->{profile_set}{id} . "'",
                description   => "Invalid profile_set_id parameter",
                response_code => HTTP_UNPROCESSABLE_ENTITY,
            };
        }
    } elsif (!exists $resource->{profile_set}{id}) {
        if ($c->user->roles eq "subscriberadmin") { #we are in subscriberadmin web UI
        #this is for subscriberadmin web ui to edit subscriber. 
        #Edit subscriber form for subscriberadmin doesn't contain profile_set control
        #API form doesn't suppose profile_set field.
        # => subscriberadmin can't manage profile_set via web ui and API
        #here we will provide profile_set so below we can check profile id
        #please note, that we don't allow to subscriberadmin unset profile_set_id and profile_set at all, . Later we will take default profile for profile_set
            if ($prov_subscriber && $resource->{profile}{id}) { #edit, preserve current profile_set
    $c->log->debug(Dumper([
        "GOT_HERE",
    
    ]));
                #not pbx account or pilot doesn't have any profile set
                $profile_set = $prov_subscriber->voip_subscriber_profile_set;
            } elsif ($c->stash->{pilot} && $c->stash->{pilot}->provisioning_voip_subscriber->voip_subscriber_profile_set) {
                $profile_set = $c->stash->{pilot}->provisioning_voip_subscriber->voip_subscriber_profile_set;
            }
        }
    }
    if ($profile_set) {
    #inverted condition to don't repeate taking default for empty input and input mismatch in web admin ui
        if ($resource->{profile}{id}) {
            $profile = $profile_set->voip_subscriber_profiles->find({
                id => $resource->{profile}{id},
            });
        }
        if (!$profile 
            && (
                    #we force default profile instead of empty for all roles those can't unset profile_set
                    (!$resource->{profile}{id}) 
                    #to admin roles we forgive incorrect profile_id (no error)
                    #this is due web ui, when not dynamic profile field can't reflect profile_set change
                    #and user need to edit twice to 1) change profile_set + incorrect profile_id) and 2) select not-default profile
                ||  ($c->user->roles eq "admin" || $c->user->roles eq "reseller")
            )
        ) {
            $profile = $profile_set->voip_subscriber_profiles->find({
                set_default => 1,
            });
        }
    } elsif ($resource->{profile}{id}) {#so - user requested profile, but we didn't find proper profile_set
        return {
            error         => "empty subscriber profile_set id for profile id '" . $resource->{profile}{id} . "'",
            description   => "Empty profile_set_id parameter",
            response_code => HTTP_UNPROCESSABLE_ENTITY,
        };
    }
    use Data::Dumper;
    $c->log->debug(Dumper([
        "profile_set input: ".($resource->{profile_set}{id}?$resource->{profile_set}{id}:"ubdefined"),
        "profile_set found: ".($profile_set?$profile_set->id:"ubdefined"),
        "profile input: ".($resource->{profile}{id}?$resource->{profile}{id}:"ubdefined"),
        "profile found: ".($profile?$profile->id:"ubdefined"),
    ]));
    if (!$profile && (
        $profile_set 
        || ( $c->user->roles eq "subscriberadmin"
            && $resource->{profile}{id} )
        )
    ) {
        #it does not matter how we get here - it is incorrect.
        #subscriberadmin can get there if he will try  to set profile not from pilot or existing profile_set
        if ($resource->{profile}{id}) {
            return {
                error         => "invalid subscriber profile id '" . $resource->{profile}{id} . "'",
                description   => "Invalid profile_id parameter",
                response_code => HTTP_UNPROCESSABLE_ENTITY,
            };
        } else {
            #TODO: maybe we should allow it? Can it be so that subscribers are linked to the profile_set without default profile?
            #in that case we will fail with this error on every subscriber update attempt
            return {
                error         => "can not determine allowed profile for subscribers profile_set",
                description   => "Can not determine allowed profile for subscribers profile_set",
                response_code => HTTP_UNPROCESSABLE_ENTITY,
            };
        }
    }

    # if the profile changed, clear any preferences which are not in the new profile
    #in create use case we don't have prov_subscriber
    if($prov_subscriber 
        && $prov_subscriber->voip_subscriber_profile 
        && ( !$profile || $prov_subscriber->voip_subscriber_profile->id != $profile->id )
    ) {
        my %old_profile_attributes = map { $_ => 1 }
            $prov_subscriber->voip_subscriber_profile
            ->profile_attributes->get_column('attribute_id')->all;
        if($profile) {
            foreach my $attr_id($profile->profile_attributes->get_column('attribute_id')->all) {
                delete $old_profile_attributes{$attr_id};
            }
        }
        if(keys %old_profile_attributes) {
            my $cfs = $schema->resultset('voip_preferences')->search({
                id => { -in => [ keys %old_profile_attributes ] },
                attribute => { -in => [qw/cfu cfb cft cfna cfs cfr/] },
            });
            $prov_subscriber->voip_usr_preferences->search({
                attribute_id => { -in => [ keys %old_profile_attributes ] },
            })->delete;
            $prov_subscriber->voip_cf_mappings->search({
                type => { -in => [ map { $_->attribute } $cfs->all ] },
            })->delete;
        }
    }
    return 0, $profile_set, $profile;
}

sub update_preferences {
    my (%params) = @_;
    my $c = $params{c};
    my $prov_subscriber = $params{prov_subscriber};
    my $preferences = $params{preferences};

    foreach my $k(keys %{ $preferences } ) {
        my $pref = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
            c => $c, attribute => $k, prov_subscriber => $prov_subscriber);
        if($pref->first && $pref->first->attribute->max_occur == 1) {
            unless(defined $preferences->{$k}) {
                $pref->first->delete;
            } else {
                $pref->first->update({
                    'value' => $preferences->{$k},
                });
            }
        } else {
            $pref->create({
                'value' => $preferences->{$k},
            }) if(defined $preferences->{$k});
        }
    }
    return;
}

sub get_pbx_subscribers_rs{
    my %params = @_;

    my $c             = $params{c};
    my $schema        = $params{schema} // $c->model('DB');
    my $ids           = $params{ids} // [];
    my $sync_with_ids = $params{sync_with_ids} // 0;

    my $customer_id = $params{customer_id} // 0;
    my $is_group    = $params{is_group};

    my $rs = $schema->resultset('voip_subscribers')->search_rs(
        {
            'status' => { '!=' => 'terminated' },
            (@$ids || $sync_with_ids) ? ( 'me.id' => { -in => $ids } ) : (),
            $customer_id ? ( 'contract_id' => $customer_id ) : (),
            $is_group ? ( 'provisioning_voip_subscriber.is_pbx_group' => $is_group ) : (),
        },{
            join => 'provisioning_voip_subscriber',
        }
    );
    return $rs;
}

sub get_pbx_subscribers_ordered_by_ids{
    my %params = @_;

    my $ids           = $params{ids} // [];
    my $sync_with_ids = $params{sync_with_ids} // 0;

    my (@items,@absent_items_ids);

    if ( !$sync_with_ids || ( ( 'ARRAY' eq ref $ids ) && @$ids ) ){
        my $c           = $params{c};
        my $schema      = $params{schema} // $c->model('DB');
        my $customer_id = $params{customer_id} // 0;
        my $is_group    = $params{is_group};

        my $pbx_subscribers_rs = get_pbx_subscribers_rs(@_);
        @items = $pbx_subscribers_rs->all();
        my %items_ids_exists =  map{ $_->id => 0 } @items;

        if(@$ids){
            my $order_hash = { %items_ids_exists };
            @$order_hash{@$ids} = (1..$#$ids+1);
            @items = sort { $order_hash->{$a->id} <=> $order_hash->{$b->id} } @items;
        }
        if($#items < $#$ids){
            @absent_items_ids = grep { !exists $items_ids_exists{$_} } @{$params{ids}};
        }
    }
    return wantarray ? (\@items, (( 0 < @absent_items_ids) ? \@absent_items_ids : undef )) : \@items;
}

#the method named "item" as it can return both groups or groups members
sub get_subscriber_pbx_items{
    my %params = @_;

    my $ids = get_subscriber_pbx_items_ids(@_) // [];
    my $items = [];

    if(@$ids){
        my $c          = $params{c};
        my $schema     = $params{schema} // $c->model('DB');
        my $subscriber = $params{subscriber};
        my $prov_subscriber = $subscriber->provisioning_voip_subscriber;
        my $items_are_groups = !($prov_subscriber->is_pbx_group);

        $items = get_pbx_subscribers_ordered_by_ids(
            c           => $c,
            schema      => $schema,
            customer_id => $subscriber->contract->id ,
            is_group    => $items_are_groups,
            ids         => $ids,
        );
    }
    return wantarray ? ($items, $ids) : $items;
}

sub get_subscriber_pbx_items_ids{
    my %params = @_;

    my $c          = $params{c};
    my $schema     = $params{schema} // $c->model('DB');
    my $subscriber = $params{subscriber};

    my $prov_subscriber = $subscriber->provisioning_voip_subscriber;
    my $items_are_groups = !($prov_subscriber->is_pbx_group);
    my $select_attributes = {
        'order_by' => 'me.id',
        'select'   => 'voip_subscriber.id',
        'as'       => 'voip_subscriber_id',
        'join'     => { ( $items_are_groups ? 'group' : 'subscriber' ) => 'voip_subscriber'},
    };
    my $ids;
    if($items_are_groups){
        $ids = [ $prov_subscriber->voip_pbx_groups->search_rs(undef,$select_attributes)->get_column('voip_subscriber_id')->all];
    }else{
        $ids = [ $prov_subscriber->voip_pbx_group_members->search_rs(undef,$select_attributes)->get_column('voip_subscriber_id')->all];
    }
    return $ids;
}

sub manage_pbx_groups{
    my %params = @_;

    my $c               = $params{c};
    my $schema          = $params{schema} // $c->model('DB');
    my $group_ids       = $params{group_ids} // [];
    my $groups          = $params{groups} // [];
    my $groupmember_ids = $params{groupmember_ids} // [];
    my $groupmembers    = $params{groupmembers} // [];
    my $subscriber      = $params{subscriber};
    my $customer        = $params{customer} // $subscriber->contract;

    my $prov_subscriber = $subscriber->provisioning_voip_subscriber;

    my $ids_existent = get_subscriber_pbx_items_ids( c => $c, subscriber => $subscriber );

    if( !$prov_subscriber->is_pbx_group ){
        if(!@$group_ids && @$groups){
            $group_ids = [ map {$_->id} @$groups ];
        }
        #Returns 0 if the structures differ, else returns 1.
        if(!compare($ids_existent, $group_ids)){
            $c->log->debug('Old and new groups differ, apply changes');

            $c->log->debug('Existent groups:'.join(',',@$ids_existent));
            $c->log->debug('Requested groups:'.join(',',@$group_ids));

            my(@added_ids, @deleted_ids, %existent_hash, %requested_hash);
            @requested_hash{@$group_ids} = @$group_ids;
            @existent_hash{@$ids_existent} = @$ids_existent;
            @added_ids = grep { !exists $existent_hash{$_} } keys %requested_hash;
            @deleted_ids = grep { !exists $requested_hash{$_} } keys %existent_hash;

            my $subscriber_uri  = get_pbx_group_member_name( subscriber => $subscriber );


            if(scalar @deleted_ids){
                #delete all old groups, to support correct order
                $c->log->debug('Delete groups:'.join(',',@deleted_ids));
                my @deleted_ids_provisioning = $schema->resultset('provisioning_voip_subscribers')->search_rs(
                    {
                        'voip_subscriber.id' => { -in => [ @deleted_ids ] },
                    },{
                        join => 'voip_subscriber',
                    }
                )->get_column('id')->all();
                my $member_preferences_rs = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                    c => $c,
                    attribute => 'cloud_pbx_hunt_group',
                )->search_rs({
                    subscriber_id => { -in => [ @deleted_ids_provisioning ] },
                    value         => $subscriber_uri,
                });

                $member_preferences_rs->delete;
                $prov_subscriber->voip_pbx_groups->search_rs( { group_id => { -in => [ @deleted_ids_provisioning ] } } )->delete;
            }
            if(scalar @added_ids){
                $c->log->debug('Added groups:'.join(',',@added_ids));
                my $groups_added       = @$group_ids ? get_pbx_subscribers_ordered_by_ids(
                    c           => $c,
                    schema      => $schema,
                    ids         => \@added_ids,
                    customer_id => $customer->id,
                    is_group    => 1,
                ) : [] ;

                #create new groups_added
                foreach my $group(@{ $groups_added }) {
                    my $group_prov_subscriber = $group->provisioning_voip_subscriber;
                    next unless( $group_prov_subscriber && $group_prov_subscriber->is_pbx_group );
                    $prov_subscriber->voip_pbx_groups->create({
                        group_id => $group_prov_subscriber->id,
                    });
                    my $preferences_rs = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                        c               => $c,
                        attribute       => 'cloud_pbx_hunt_group',
                        prov_subscriber => $group_prov_subscriber,
                    );
                    $preferences_rs->create({ value => $subscriber_uri });
                }
            }else{
                $c->log->debug('No groups were added.');
            }
        }else{
            $c->log->debug('Old and new groups are the same');
        }
    }else{
        if(!@$groupmember_ids && @$groupmembers){
            $groupmember_ids = [ map {$_->id} @$groupmembers ];
        }
        #Returns 0 if the structures differ, else returns 1.
        if(!compare($ids_existent, $groupmember_ids)){
            $c->log->debug('Old and new group members differ, apply changes');
            my $groupmembers = @$groupmember_ids ? get_pbx_subscribers_ordered_by_ids(
                c           => $c,
                schema      => $schema,
                ids         => $groupmember_ids,
                customer_id => $customer->id,
                is_group    => 0,
            ) : [] ;

            #delete old members to support correct order
            $prov_subscriber->voip_pbx_group_members->delete;
            my $group_preferences_rs = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                c => $c,
                attribute => 'cloud_pbx_hunt_group',
                prov_subscriber => $prov_subscriber,
            );
            $group_preferences_rs->delete;

            foreach my $member(@{ $groupmembers }) {
                my $member_prov_subscriber = $member->provisioning_voip_subscriber;
                next unless( $member_prov_subscriber && !$member_prov_subscriber->is_pbx_group );
                my $member_uri = get_pbx_group_member_name( subscriber => $member );
                $prov_subscriber->voip_pbx_group_members->create({
                    subscriber_id => $member_prov_subscriber->id,
                });
                $group_preferences_rs->create({ value => $member_uri });
            }
        }else{
            $c->log->debug('Old and new group members are the same');
        }
   }
}

sub get_pbx_group_member_name{
    my %params = @_;
    my $c               = $params{c};
    my $subscriber      = $params{subscriber};
    return "sip:".$subscriber->username."\@".$subscriber->domain->domain;
}

sub update_subscriber_numbers {
    my %params = @_;

    my $c              = $params{c};
    my $schema         = $params{schema};
    my $subscriber_id  = $params{subscriber_id};
    my $reseller_id    = $params{reseller_id};
    my $primary_number = $params{primary_number};
    my $alias_numbers  = $params{alias_numbers}; # alias numbers

    my $billing_subs = $schema->resultset('voip_subscribers')->find({
            id => $subscriber_id,
        });
    my $prov_subs = $billing_subs->provisioning_voip_subscriber;
    my @nums = ();

    my $primary_number_old = defined $billing_subs->primary_number ? { $billing_subs->primary_number->get_inflated_columns } : undef;

    my $acli_pref;
    $acli_pref = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
        c => $c, attribute => 'allowed_clis', prov_subscriber => $prov_subs)
        if($prov_subs && $c->config->{numbermanagement}->{auto_allow_cli});

    if(exists $params{primary_number} && !defined $primary_number) {
        $billing_subs->update({
            primary_number_id => undef,
        });

        if(defined $acli_pref) {
            $acli_pref->delete;
        }
        my $cli_pref = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
            c => $c, attribute => 'cli', prov_subscriber => $prov_subs);
        if(defined $cli_pref) {
            if($cli_pref->first
                && defined $primary_number_old
                && ( $cli_pref->first->value eq number_as_string($primary_number_old) )
                && $c->config->{numbermanagement}->{auto_sync_cli}){

                $cli_pref->delete;
            }
        }
        for my $cfset($prov_subs->voip_cf_destination_sets->all) {
            for my $cf($cfset->voip_cf_destinations->all) {
                if($cf->destination =~ /\@fax2mail\.local$/) {
                    $cf->delete;
                } elsif($cf->destination =~ /\@conference\.local$/) {
                    $cf->delete;
                }
            }
            unless($cfset->voip_cf_destinations->count) {
                $cfset->voip_cf_mappings->delete;
                $cfset->delete;
            }
        }
        update_voicemail_number(schema => $schema, subscriber => $billing_subs);

    } elsif(defined $primary_number) {

        my $old_cc;
        my $old_ac;
        my $old_sn;
        if (defined $billing_subs->primary_number) {
            $old_cc = $billing_subs->primary_number->cc;
            $old_ac = ($billing_subs->primary_number->ac // '');
            $old_sn = $billing_subs->primary_number->sn;
        }

        my $number;
        if (defined $primary_number->{cc}
            && $primary_number->{cc} ne '') {

            my $old_number = $schema->resultset('voip_numbers')->search({
                    cc            => $primary_number->{cc},
                    ac            => $primary_number->{ac} // '',
                    sn            => $primary_number->{sn},
                    subscriber_id => [undef, $subscriber_id],
                },{
                    for => 'update',
                })->first;

            if(defined $old_number) {
                $old_number->update({
                    status        => 'active',
                    reseller_id   => $reseller_id,
                    subscriber_id => $subscriber_id,
                });
                $number = $old_number;
            } else {
                $number = $schema->resultset('voip_numbers')->create({
                    cc            => $primary_number->{cc},
                    ac            => $primary_number->{ac} // '',
                    sn            => $primary_number->{sn},
                    status        => 'active',
                    reseller_id   => $reseller_id,
                    subscriber_id => $subscriber_id,
                });
            }
            my $cli_pref = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                c => $c, attribute => 'cli', prov_subscriber => $prov_subs);
            if($cli_pref->first) {
                if(defined $primary_number_old
                    && ( number_as_string($primary_number_old) eq $cli_pref->first->value )
                    && $c->config->{numbermanagement}->{auto_sync_cli} ){

                    $cli_pref->first->update({ value => $primary_number->{cc} . ($primary_number->{ac} // '') . $primary_number->{sn} });
                }
            } else {
                if( ! defined $primary_number_old && $c->config->{numbermanagement}->{auto_sync_cli} ){
                    $cli_pref->create({
                        subscriber_id => $prov_subs->id,
                        value => $primary_number->{cc} . ($primary_number->{ac} // '') . $primary_number->{sn}
                    });
                }
            }
        }

        if(defined $number) {
            my $cli = $number->cc . ($number->ac // '') . $number->sn;
            my $old_cli = undef;

            if(defined $billing_subs->primary_number
                && $billing_subs->primary_number_id != $number->id) {
                $old_cli = $billing_subs->primary_number->cc .
                    ($billing_subs->primary_number->ac // '') .
                    $billing_subs->primary_number->sn;
                $billing_subs->primary_number->delete;
            }
            $billing_subs->update({
                    primary_number_id => $number->id,
                });
            if(defined $prov_subs) {
                my $dbalias = $prov_subs->voip_dbaliases->find({
                    username => $cli,
                });
                if($dbalias) {
                    if(!$dbalias->is_primary) {
                        $dbalias->update({ is_primary => 1 });
                    }
                } else {
                    $dbalias = $prov_subs->voip_dbaliases->create({
                        username => $cli,
                        domain_id => $prov_subs->domain->id,
                        is_primary => 1,
                    });
                }
                if(defined $acli_pref) {
                    $acli_pref->search({ value => $old_cli })->delete if($old_cli);
                    if(!$acli_pref->find({ value => $cli })) {
                        $acli_pref->create({ value => $cli });
                    }
                }
                update_voicemail_number(schema => $schema, subscriber => $billing_subs);

                for my $cfset($prov_subs->voip_cf_destination_sets->all) {
                    for my $cf($cfset->voip_cf_destinations->all) {
                        if($cf->destination =~ /\@fax2mail\.local$/) {
                            $cf->update({ destination => 'sip:'.$cli.'@fax2mail.local' });
                        } elsif($cf->destination =~ /\@conference\.local$/) {
                            $cf->update({ destination => 'sip:conf='.$cli.'@conference.local' });
                        }
                    }
                }
            }
        } else {
            if (defined $billing_subs->primary_number) {
                $billing_subs->primary_number->delete;
                update_voicemail_number(schema => $schema, subscriber => $billing_subs);
            }
        }

        if ( (defined $old_cc && defined $old_sn)
                && $billing_subs->contract->product->class eq "pbxaccount"
                && $prov_subs->is_pbx_pilot ) {
            my $customer_subscribers_rs = $billing_subs->contract->voip_subscribers;
            my $my_cc = $primary_number->{cc};
            my $my_ac = $primary_number->{ac};
            my $my_sn = $primary_number->{sn};
            my $new_base_cli = $my_cc . ($my_ac // '') . $my_sn;
            my $usr_preferences_base_cli_rs = $schema->resultset('voip_preferences')->find({
                    attribute => 'cloud_pbx_base_cli',
                })->voip_usr_preferences;
            $usr_preferences_base_cli_rs->search_rs({subscriber_id=>$prov_subs->id})->update_all({value => $new_base_cli});
            for my $sub ($customer_subscribers_rs->all) {
                next unless($sub->provisioning_voip_subscriber); # terminated etc
                next if $sub->id == $billing_subs->id; # myself
                next unless $sub->primary_number;
                next unless $sub->primary_number->cc == $old_cc;
                next unless $sub->primary_number->ac == $old_ac;
                next unless $sub->primary_number->sn =~ /^$old_sn/;
                $usr_preferences_base_cli_rs->search_rs({subscriber_id=>$sub->provisioning_voip_subscriber->id})->update_all({value => $new_base_cli});
                $schema->resultset('voip_dbaliases')->search_rs({
                    username => $old_cc . ($old_ac // '') . $sub->primary_number->sn,
                })->delete;
                update_subscriber_numbers(
                    c => $c,
                    schema => $schema,
                    subscriber_id => $sub->id,
                    reseller_id => $reseller_id,
                    primary_number => {
                        cc => $my_cc,
                        ac => $my_ac,
                        sn => $sub->primary_number->sn =~ s/^$old_sn/$my_sn/r,
                    }
                );
            }
        }

    }

    if(defined $alias_numbers && ref($alias_numbers) eq 'ARRAY') {
        my $number;
        for my $alias(@$alias_numbers) {

            my $old_cli;
            my $old_number = $schema->resultset('voip_numbers')->search({
                    cc            => $alias->{e164}->{cc},
                    ac            => $alias->{e164}->{ac} // '',
                    sn            => $alias->{e164}->{sn},
                    subscriber_id => [undef, $subscriber_id],
                },{
                    for => 'update',
                })->first;

            if(defined $old_number) {
                $old_number->update({
                    status        => 'active',
                    reseller_id   => $reseller_id,
                    subscriber_id => $subscriber_id,
                });
                $number = $old_number;
                $old_cli = $old_number->cc . ($old_number->ac // '') . $old_number->sn;
            } else {
                $number = $schema->resultset('voip_numbers')->create({
                    cc            => $alias->{e164}->{cc},
                    ac            => $alias->{e164}->{ac} // '',
                    sn            => $alias->{e164}->{sn},
                    status        => 'active',
                    reseller_id   => $reseller_id,
                    subscriber_id => $subscriber_id,
                });
            }
            push @nums, $number->id;
            my $cli = $number->cc . ($number->ac // '') . $number->sn;
            my $dbalias = $prov_subs->voip_dbaliases->find({
                username => $cli,
            });
            if($dbalias) {
                if($dbalias->is_primary) {
                    $dbalias->update({ is_primary => 0 });
                }
            } else {
                $dbalias = $prov_subs->voip_dbaliases->create({
                    username => $cli,
                    domain_id => $prov_subs->domain->id,
                    is_primary => 0,
                });
            }
            if(defined $acli_pref) {
                $acli_pref->search({ value => $old_cli })->delete if($old_cli);
                if(!$acli_pref->find({ value => $cli })) {
                    $acli_pref->create({ value => $cli });
                }
            }
        }
    } else {
        push @nums, $billing_subs->voip_numbers->get_column('id')->all;
    }

    push @nums, $billing_subs->primary_number_id
        if($billing_subs->primary_number_id);
    $billing_subs->voip_numbers->search({
        id => { 'not in' => \@nums },
    })->update({
        subscriber_id => undef,
        reseller_id => undef,
    });
    if($prov_subs) {
        my @dbnums = map { $_->cc . ($_->ac // '') . $_->sn } $billing_subs->voip_numbers->all;
        $prov_subs->voip_dbaliases->search({
            username => { 'not in' => \@dbnums },
        })->delete;
        if(defined $acli_pref) {
            $acli_pref->search({ value => { 'not in' => \@dbnums }})->delete;
        }
    }

    return;
}

sub update_subadmin_sub_aliases {
    my %params = @_;

    my $c              = $params{c};
    my $schema         = $params{schema};
    my $subscriber     = $params{subscriber};
    my $sadmin         = $params{sadmin};
    my $contract_id    = $params{contract_id};
    my $alias_selected = $params{alias_selected};

    my $num_rs = $schema->resultset('voip_numbers')->search_rs({
        'subscriber.contract_id' => $contract_id,
    },{
        prefetch => 'subscriber',
    });

    my $acli_pref_sub;
    $acli_pref_sub = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
        c => $c, attribute => 'allowed_clis', prov_subscriber => $subscriber->provisioning_voip_subscriber)
        if($subscriber->provisioning_voip_subscriber && $c->config->{numbermanagement}->{auto_allow_cli});
    my $acli_pref_pilot;
    $acli_pref_pilot = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
        c => $c, attribute => 'allowed_clis', prov_subscriber => $sadmin->provisioning_voip_subscriber)
        if($sadmin->provisioning_voip_subscriber && $c->config->{numbermanagement}->{auto_allow_cli});

    for my $num ($num_rs->all) {
        next if ($num->voip_subscribers->first); # is a primary number

        my $cli = $num->cc . ($num->ac // '') . $num->sn;

        my $tmpsubscriber;
        if (grep { $num->id eq $_ } @$alias_selected) {
            # assign number from someone to this subscriber

            # since the number could be assigned to any sub within the pbx,
            # we need to figure out the owner first and clear the allowed_clis pref from there
            my $sub = $schema->resultset('voip_dbaliases')->find({
                username => $cli,
                domain_id => $subscriber->provisioning_voip_subscriber->domain_id,
            });
            $sub = $sub->subscriber if($sub);
            my $acli_pref_tmpsub;
            $acli_pref_tmpsub = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                c => $c, attribute => 'allowed_clis', prov_subscriber => $sub)
                if($sub && $c->config->{numbermanagement}->{auto_allow_cli});
            if(defined $acli_pref_tmpsub) {
                $acli_pref_tmpsub->search({ value => $cli })->delete;
            }

            # then set allowed_clis for the new owner
            if(defined $acli_pref_sub) {
                if(!$acli_pref_sub->find({ value => $cli })) {
                    $acli_pref_sub->create({ value => $cli });
                }
            }

            $tmpsubscriber = $subscriber;
        } elsif ($num->subscriber_id == $subscriber->id) {
            # move number back to pilot

            # clear allowed_clis pref from owner and add it to pilot
            if(defined $acli_pref_sub) {
                $acli_pref_sub->search({ value => $cli })->delete;
            }
            if(defined $acli_pref_pilot) {
                if(!$acli_pref_pilot->find({ value => $cli })) {
                    $acli_pref_pilot->create({ value => $cli });
                }
            }
            $tmpsubscriber = $sadmin
        } else {
            next;
        }
        $num->update({
            subscriber_id => $tmpsubscriber->id,
        });
        my $dbnum = $schema->resultset('voip_dbaliases')->find({
            username => $cli,
            domain_id => $subscriber->provisioning_voip_subscriber->domain_id,
        });
        if($dbnum) {
            $dbnum->update({
                subscriber_id => $tmpsubscriber->provisioning_voip_subscriber->id,
            });
        } else {
            $schema->resultset('voip_dbaliases')->create({
                username => $num->cc . ($num->ac // '') . $num->sn,
                domain_id => $subscriber->provisioning_voip_subscriber->domain_id,
                subscriber_id => $tmpsubscriber->provisioning_voip_subscriber->id,
                is_primary => 0,
            });
        }
    }

}

sub terminate {
    my %params = @_;

    my $c = $params{c};
    my $subscriber = $params{subscriber};

    my $schema = $c->model('DB');
    $schema->txn_do(sub {

        my $prov_subscriber = $subscriber->provisioning_voip_subscriber;

        my @events_to_create = ();
        my $aliases_before = NGCP::Panel::Utils::Events::get_aliases_snapshot(
            c => $c,
            schema => $schema,
            subscriber => $subscriber,
        );
        my $aliases_after = { new_aliases => [] };
        $aliases_after->{new_pilot_aliases} = [] if $prov_subscriber && $prov_subscriber->is_pbx_pilot;

        if($prov_subscriber) {
            foreach my $set ($prov_subscriber->voip_cf_destination_sets->all) {
                my $autoattendant = check_dset_autoattendant_status($set);
                if ($autoattendant) {
                    foreach my $map ($set->voip_cf_mappings->all) {
                        push(@events_to_create,{
                            subscriber_id => $subscriber->id, type => 'end_ivr',
                            %$aliases_before,%$aliases_after,
                        });
                    }
                }
            }
            if($prov_subscriber->is_pbx_group) {
                $schema->resultset('voip_pbx_groups')->search({
                    group_id => $subscriber->provisioning_voip_subscriber->id,
                })->delete;
                push(@events_to_create,{
                        type => 'end_huntgroup',
                        subscriber_id => $subscriber->id,
                        old => $prov_subscriber->profile_id, new => undef,
                        %$aliases_before,%$aliases_after,
                    });
            }
            #if($prov_subscriber->profile_id) {
                push(@events_to_create,{
                    subscriber_id => $subscriber->id, type => 'profile',
                    old => $prov_subscriber->profile_id, new => undef,
                    %$aliases_before,%$aliases_after,
                });
            #}
        }
        if($prov_subscriber && !$prov_subscriber->is_pbx_pilot) {
            my $pilot_rs = $schema->resultset('voip_subscribers')->search({
                contract_id => $subscriber->contract_id,
                status => { '!=' => 'terminated' },
                'provisioning_voip_subscriber.is_pbx_pilot' => 1,
            },{
                join => 'provisioning_voip_subscriber',
            });
            if($pilot_rs->first) {
                update_subadmin_sub_aliases(
                    c => $c,
                    schema => $schema,
                    subscriber => $subscriber,
                    contract_id => $subscriber->contract_id,
                    alias_selected => [], #none, thus moving them back to our subadmin
                    sadmin => $pilot_rs->first,
                );
                my $subscriber_primary_nr = $subscriber->primary_number;
                if ($subscriber_primary_nr) {
                    $subscriber_primary_nr->update({
                        subscriber_id => undef,
                        reseller_id => undef,
                    });
                }
            } else {
                $subscriber->voip_numbers->update_all({
                    subscriber_id => undef,
                    reseller_id => undef,
                });
            }
        } else {
            $subscriber->voip_numbers->update_all({
                subscriber_id => undef,
                reseller_id => undef,
            });
        }
        if($prov_subscriber) {
            manage_pbx_groups(
                c            => $c,
                schema       => $schema,
                groups       => [],
                subscriber   => $subscriber,
            );
            my $auth_prefs = {};
            NGCP::Panel::Utils::Preferences::get_peer_auth_params($c, $prov_subscriber, $auth_prefs);
            NGCP::Panel::Utils::Preferences::update_sems_peer_auth($c, $prov_subscriber, $auth_prefs, {});
            NGCP::Panel::Utils::Kamailio::delete_location($c, $prov_subscriber);
            foreach my $pref(qw/allowed_ips_grp man_allowed_ips_grp/) {
                my $aig_rs = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                    c => $c, prov_subscriber => $prov_subscriber, attribute => $pref,
                );
                if($aig_rs && $aig_rs->first) {
                    $c->model('DB')->resultset('voip_allowed_ip_groups')
                    ->search_rs({ group_id => $aig_rs->first->value })
                    ->delete;
                }
            }
            NGCP::Panel::Utils::Events::insert_deferred(
                c => $c, schema => $schema,
                events_to_create => \@events_to_create,
            );
            #ready for number change events here

            $prov_subscriber->delete;
        }
        $subscriber->update({ status => 'terminated' });
    });
}

sub field_to_destination {
    my %params = @_;

    my $number = $params{number};
    my $domain = $params{domain};
    my $d = $params{destination};
    my $uri = $params{uri};
    my $cf_type = $params{cf_type};
    my $c = $params{c};  # if not passed, rwr is not applied (web panel, it is done there separately)
    my $sub = $params{subscriber};

    my $vm_prefix = "vmu";
    if(defined $cf_type && $cf_type eq "cfb") {
        $vm_prefix = "vmb";
    }

    if($d eq "voicebox") {
        $d = "sip:".$vm_prefix.$number."\@voicebox.local";
    } elsif($d eq "fax2mail") {
        $d = "sip:$number\@fax2mail.local";
    } elsif($d eq "conference") {
        $d = "sip:conf=$number\@conference.local";
    } elsif($d eq "callingcard") {
        $d = "sip:callingcard\@app.local";
    } elsif($d eq "callthrough") {
        $d = "sip:callthrough\@app.local";
    } elsif($d eq "localuser") {
        $d = "sip:localuser\@app.local";
    } elsif($d eq "autoattendant") {
        $d = "sip:auto-attendant\@app.local";
    } elsif($d eq "officehours") {
        $d = "sip:office-hours\@app.local";
    } elsif($d eq "customhours") {
        $d = "sip:custom-hours\@app.local";
    } elsif($d eq "managersecretary") {
        $d = "sip:$number\@managersecretary.local";
    } else {
        my $v = $uri;
        $v =~ s/^sips?://;
        my ($vuser, $vdomain) = split(/\@/, $v);
        $vdomain = $domain unless($vdomain);

        if($c && ($c->user->roles eq "subscriberadmin" || $c->user->roles eq "subscriber")) {
            $vuser = NGCP::Panel::Utils::Subscriber::apply_rewrite(
                c => $c, subscriber => $sub, number => $vuser, direction => 'callee_in',
            );
        }

        $d = 'sip:' . $vuser . '@' . $vdomain;
    }
    return $d;
}

sub destination_to_field {
    my ($d) = @_;

    $d //= "";
    my $duri = undef;
    if($d =~ /\@voicebox\.local$/) {
        $d = 'voicebox';
    } elsif($d =~ /\@fax2mail\.local$/) {
        $d = 'fax2mail';
    } elsif($d =~ /\@conference\.local$/) {
        $d = 'conference';
    } elsif($d =~ /^sip:callingcard\@app\.local$/) {
        $d = 'callingcard';
    } elsif($d =~ /^sip:callthrough\@app\.local$/) {
        $d = 'callthrough';
    } elsif($d =~ /^sip:localuser\@.+\.local$/) {
        $d = 'localuser';
    } elsif($d =~ /^sip:auto-attendant\@app\.local$/) {
        $d = 'autoattendant';
    } elsif($d =~ /^sip:office-hours\@app\.local$/) {
        $d = 'officehours';
    } elsif($d =~ /^sip:custom-hours\@app\.local$/) {
        $d = 'customhours';
    } elsif($d =~ /\@managersecretary\.local$/) {
        $d = 'managersecretary';
    } else {
        $duri = $d;
        $d = 'uri';
    }
    return ($d, $duri);
}

sub uri_deflate {
    my ($c, $v, $sub) = @_;
    my $direction = 'caller_out';
    $v =~ s/^sips?://;
    my $t;
    my ($user, $domain) = split(/\@/, $v);
    if($c && ($c->user->roles eq "subscriberadmin" || $c->user->roles eq "subscriber")) {
        $user = NGCP::Panel::Utils::Subscriber::apply_rewrite(
            c => $c, subscriber => $sub, number => $user, direction => $direction,
        );
    }
    if($domain eq $sub->domain->domain) {
        $v = $user;
    } else {
        $v = $user . '@' . $domain;
    }
    return $v;
}


sub callforward_create_or_update_quickset_destinations {
    my %params = @_;

    my $mapping = $params{mapping};
    my $type = $params{type};
    my $destinations = $params{destinations};
    my $schema = $params{schema};

    return;
}

sub prepare_alias_select {
    my (%p) = @_;
    my $c = $p{c};
    my $subscriber = $p{subscriber};
    my $params = $p{params};
    my $unselect = $p{unselect} // 0;

    my @alias_options = ();
    my @alias_nums = ();
    my $num_rs = $c->model('DB')->resultset('voip_numbers')->search_rs({
        'subscriber.contract_id' => $subscriber->contract_id,
    },{
        prefetch => 'subscriber',
    });
    for my $num($num_rs->all) {
        next if ($subscriber->primary_number_id && $num->id == $subscriber->primary_number_id); # is our primary number
        next unless ($num->subscriber_id == $subscriber->id);
        push @alias_nums, { e164 => { cc => $num->cc, ac => $num->ac, sn => $num->sn } };
        unless($unselect) {
            push @alias_options, $num->id;
        }
    }
    $params->{alias_number} = \@alias_nums;
    $params->{alias_select} = encode_json(\@alias_options);
}

sub prepare_group_select {
    my (%p) = @_;
    my $c = $p{c};
    my $subscriber = $p{subscriber};
    my $params = $p{params};
    my $unselect = $p{unselect} // 0;

    my @group_options = ();
    my $group_rs = $c->model('DB')->resultset('voip_pbx_groups')->search({
        'subscriber_id' => $subscriber->provisioning_voip_subscriber->id,
    },{
        'order_by' => 'me.id',
    });
    unless($unselect) {
        @group_options = map { $_->group->voip_subscriber->id } $group_rs->all;
    }
    $params->{group_select} = encode_json(\@group_options);
}

sub apply_rewrite {
    my (%params) = @_;

    my $c = $params{c};
    my $subscriber = $params{subscriber};
    my $avp_caller_subscriber = $params{avp_caller_subscriber} // $subscriber;
    my $avp_callee_subscriber = $params{avp_callee_subscriber} // $subscriber;
    my $callee = $params{number};
    my $dir = $params{direction};
    my $rws_id = $params{rws_id}; # override rewrite rule set
    my $sub_type = 'provisioning';
    my $rwr_rs = undef;

    return $callee unless $dir =~ /^(caller_in|callee_in|caller_out|callee_out|callee_lnp|caller_lnp)$/;

    my ($field, $direction) = split /_/, $dir;
    $dir = "rewrite_".$dir."_dpid";

    if ($rws_id) {
        $rwr_rs = $c->model('DB')->resultset('voip_rewrite_rule_sets')->search({
                    id => $rws_id,
                  }, {
                    '+select' => (sprintf "%s_%s_dpid", $field, $direction),
                    '+as' => qw(rwr_id),
                  });
        unless ($rwr_rs->count) {
            return $callee;
        }
    } elsif (!$subscriber || !ref($subscriber)) {
        $c->log->warn('could not apply rewrite: no subscriber found.');
        return $callee;
    } elsif ($subscriber->can('provisioning_voip_subscriber')) {
        $rwr_rs = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
            c => $c, attribute => $dir,
            prov_subscriber => $subscriber->provisioning_voip_subscriber,
        );
        unless($rwr_rs->count) {
            $rwr_rs = NGCP::Panel::Utils::Preferences::get_dom_preference_rs(
                c => $c, attribute => $dir,
                prov_domain => $subscriber->provisioning_voip_subscriber->domain,
            );
        }
        unless($rwr_rs->count) {
            return $callee;
        }
    } elsif ($subscriber->can('domain')) {
        $sub_type = 'billing';
        if ($subscriber->domain && $subscriber->domain->provisioning_voip_domain) {
            $rwr_rs = NGCP::Panel::Utils::Preferences::get_dom_preference_rs(
                c => $c, attribute => $dir,
                prov_domain => $subscriber->domain->provisioning_voip_domain,
            );
            unless($rwr_rs->count) {
                return $callee;
            }
        } else {
            return $callee;
        }
    } else {
        $c->log->warn('could not apply rewrite: unknown subscriber type.');
        return $callee;
    }

    my $rule_rs = $c->model('DB')->resultset('voip_rewrite_rules')->search({
        'ruleset.'.$field.'_'.$direction.'_dpid' =>
            $rws_id ? $rwr_rs->first->get_column('rwr_id')
                    : $rwr_rs->first->value,
        direction => $direction,
        field => $field,
    }, {
        join => 'ruleset',
        order_by => { -asc => 'priority' },
    });

    unless($rule_rs->count) {
        $c->log->warn('could not apply rewrite: no rewrite rule set found.');
        return $callee;
    }

    my $cache = {};
    foreach my $r($rule_rs->all) {
        my @entries = ();
        my $match = $r->match_pattern;
        my $replace = $r->replace_pattern;

        #print ">>>>>>>>>>> match=$match, replace=$replace\n";
        for my $field($match, $replace) {
            #print ">>>>>>>>>>> normalizing $field\n";
            my @avps = ();
            @avps = ($field =~ /\$\(?avp\(s:([^\)]+)\)/g);
            @avps = keys %{{ map { $_ => 1 } @avps }};
            for my $avp(@avps) {
                if(!exists $cache->{$avp}) {
                    if($avp eq "caller_cloud_pbx_account_cli_list") {
                        $cache->{$avp} = [];
                        foreach my $sub($avp_caller_subscriber->contract->voip_subscribers->all) {
                            foreach my $num($sub->voip_numbers->search({ status => 'active' })->all) {
                                my $v = $num->cc . ($num->ac // '') . $num->sn;
                                unless(grep { $v eq $_ } @{ $cache->{$avp} }) {
                                    push @{ $cache->{$avp} }, $v;
                                }
                            }
                        }
                    } elsif($avp eq "callee_cloud_pbx_account_cli_list") {
                        $cache->{$avp} = [];
                        foreach my $sub($avp_callee_subscriber->contract->voip_subscribers->all) {
                            foreach my $num($sub->voip_numbers->search({ status => 'active' })->all) {
                                my $v = $num->cc . ($num->ac // '') . $num->sn;
                                unless(grep { $v eq $_ } @{ $cache->{$avp} }) {
                                    push @{ $cache->{$avp} }, $v;
                                }
                            }
                        }
                    } else {
                        my $avp_attr = $avp;
                        $avp_attr =~ s/^calle(?:r|e)_//;
                        my $pref_rs = undef;
                        if ($sub_type eq 'provisioning') {
                            my $subs = $subscriber;
                            if ($avp =~ /^caller_/) {
                                $subs = $avp_caller_subscriber;
                            } elsif ($avp =~ /^callee_/) {
                                $subs = $avp_callee_subscriber;
                            }
                            $pref_rs = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                                c => $c, attribute => $avp_attr,
                                prov_subscriber => $subs->provisioning_voip_subscriber,
                            );
                            unless($pref_rs && $pref_rs->count) {
                                $pref_rs = NGCP::Panel::Utils::Preferences::get_dom_preference_rs(
                                    c => $c, attribute => $avp_attr,
                                    prov_domain => $subs->provisioning_voip_subscriber->domain,
                                );
                            }
                        } elsif ($sub_type eq 'billing') {
                            $pref_rs = NGCP::Panel::Utils::Preferences::get_dom_preference_rs(
                                c => $c, attribute => $avp_attr,
                                prov_domain => $subscriber->domain->provisioning_voip_domain,
                            );
                        }
                        next unless($pref_rs);
                        if($field =~ /\$\(avp/) { # $(avp(s:xxx)[*])
                            $cache->{$avp} = [ $pref_rs->get_column('value')->all ];
                        } else {
                            $cache->{$avp} = $pref_rs->first ? $pref_rs->first->value : '';
                        }
                    }
                }
                my $val = $cache->{$avp};
                if(ref $val eq "ARRAY") {
                    my $orig = $field; $field = [];
                    $orig = shift @{ $orig } if(ref $orig eq "ARRAY");
                    foreach my $v(@{ $val }) {
                        my $tmporig = $orig;
                        $tmporig =~ s/\$avp\(s:$avp\)/$v/g;
                        $tmporig =~ s/\$\(avp\(s:$avp\)\[\+\]\)/$v/g;
                        push @{ $field }, $tmporig;
                    }
                } else {
                    my $orig = $field;
                    $orig = shift @{ $orig } if(ref $orig eq "ARRAY");
                    $orig =~ s/\$avp\(s:$avp\)/$val/g;
                    $field = [] unless(ref $field eq "ARRAY");
                    push @{ $field }, $orig;
                }
                #print ">>>>>>>>>>> normalized $field\n";
            }
        }

        $match = [ $match ] if(ref $match ne "ARRAY");

        $replace = shift @{ $replace } if(ref $replace eq "ARRAY");
        # \1 => ${1}
        $replace =~ s/\\(\d{1})/\${$1}/g;
        # ${0} => ${&} # meaning the whole matched regex (compatible to sed/POSIX)
        $replace =~ s/\$\{0\}/\${&}/g;

        $replace =~ s/\"/\\"/g;
        $replace = qq{"$replace"};

        my $found;
        $c->log->debug(">>>>>>>>>>> apply matches");
        #print ">>>>>>>>>>> apply matches\n";
        foreach my $m(@{ $match }) {
            $c->log->debug(">>>>>>>>>>>     m=$m, r=$replace;");
            #print ">>>>>>>>>>>     m=$m, r=$replace\n";
            if($callee =~ s/$m/$replace/eeg) {
                # we only process one match
                $c->log->debug(">>>>>>>>>>> match found, callee=$callee;");
                #print ">>>>>>>>>>> match found, callee=$callee\n";
                $found = 1;
                last;
            }
        }
        last if $found;
        $c->log->debug(">>>>>>>>>>> done, match=$match, replace=$replace, callee is $callee;");
        #print ">>>>>>>>>>> done, match=$match, replace=$replace, callee is $callee\n";
    }

    return $callee;
}

sub check_cf_ivr {
    my (%params) = @_;

    my $c = $params{c};
    my $schema = $params{schema} // $c->model('DB');;
    my $subscriber = $params{subscriber};
    my $new_aa = $params{new_aa}; # boolean, false on delete
    my $old_aa = $params{old_aa}; # boolean, false on create
    if ($old_aa && !$new_aa) {
        NGCP::Panel::Utils::Events::insert(
            c => $c, schema => $schema,
            subscriber_id => $subscriber->id,
            type => 'end_ivr',
        );
    } elsif (!$old_aa && $new_aa) {
        NGCP::Panel::Utils::Events::insert(
            c => $c, schema => $schema,
            subscriber_id => $subscriber->id,
            type => 'start_ivr',
        );
    }
    return;
}

sub check_dset_autoattendant_status {
    my ($dset) = @_;

    my $status = 0;
    if ($dset) {
        for my $dest ($dset->voip_cf_destinations->all) {
            if ( (destination_to_field($dest->destination))[0] eq 'autoattendant' ) {
                $status = 1;
            }
        }
    }
    return $status;
}

# echo-order: voicemail_echo_number, cli, primary_number, uuid
# cf-order: primary_number, uuid
sub update_voicemail_number {
    my (%params) = @_;

    my $schema = $params{schema};
    my $subscriber = $params{subscriber};

    my $prov_subs = $subscriber->provisioning_voip_subscriber;
    return unless $prov_subs;
    my $voicemail_user = $prov_subs->voicemail_user;

    my $echonumber_pref_rs = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
        schema => $schema,
        prov_subscriber => $prov_subs,
        attribute => 'voicemail_echo_number',
    );
    my $cli_pref_rs = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
        schema => $schema,
        prov_subscriber => $prov_subs,
        attribute => 'cli',
    );

    my ($cf_cli, $echo_cli);
    if (defined $subscriber->primary_number) {
        my $n = $subscriber->primary_number;
        $cf_cli = $echo_cli = $n->cc . ($n->ac // '') . $n->sn;
    } else {
        $cf_cli = $echo_cli = $subscriber->uuid;
    }

    if (defined $echonumber_pref_rs->first) {
        $echo_cli = $echonumber_pref_rs->first->value;
    } elsif (defined $cli_pref_rs->first) {
        $echo_cli = $cli_pref_rs->first->value;
    }

    if (defined $voicemail_user) {
        $voicemail_user->update({ mailbox => $echo_cli });
    }

    for my $cfset ($prov_subs->voip_cf_destination_sets->all) {
        for my $cf ($cfset->voip_cf_destinations->all) {
            if($cf->destination =~ /^sip:(vm[ub]).+\@voicebox\.local$/) {
                $cf->update({ destination => 'sip:'.$1.$cf_cli.'@voicebox.local' });
            }
        }
    }

    return;
}

sub vmnotify{
    my (%params) = @_;

    my $c = $params{c};
    my $voicemail = $params{voicemail};
    #1.although method is called after delete - DBIC still can access data in deleted row
    #2.amount of the new messages should be selected after played update or delete, of course

    my $data = { $voicemail->get_inflated_columns };
    $data->{cli} = $voicemail->mailboxuser->provisioning_voip_subscriber->username;
    $data->{context} = 'default';

    $data->{messages_amount} = $c->model('DB')->resultset('voicemail_spool')->find({
        'mailboxuser' => $data->{mailboxuser},
        'msgnum'      => { '>=' => 0 },
        'dir'         => { 'like' => '%/INBOX' },
    },{
        'select'      => [{'count' => '*', -as => 'messages_number'}]
    })->get_column('messages_number');

    my @cmd = ('vmnotify',@$data{qw/context cli messages_amount/});
    my $output = capturex([0..3],@cmd);
    $c->log->debug("cmd=".join(" ", @cmd)."; output=$output;");
    return;
}

sub mark_voicemail_read{
    my (%params) = @_;

    my $c = $params{c};
    my $voicemail = $params{voicemail};
    my $dir = $voicemail->dir;
    $dir =~s/INBOX$/Old/;
    $voicemail->update({ dir => $dir });
    return;
}

sub get_subscriber_voicemail_directory{
    my (%params) = @_;

    my $c = $params{c};
    my $subscriber = $params{subscriber};
    my $dir = $params{dir};
    return "/var/spool/asterisk/voicemail/default/".$subscriber->uuid."/$dir";
}

sub get_subscriber_voicemail_type{
    my (%params) = @_;

    my $c = $params{c};
    my $dir = $params{dir};
    $dir =~s/.*?\/([^\/]+)$/$1/gis;
    return $dir;
}

sub convert_voicemailgreeting{
    my (%params) = @_;

    my $c = $params{c};
    my $upload = $params{upload};
    my $converted_data_ref = $params{converted_data_ref};
    if(!$upload->size){
        die('Uploaded greeting file is empty.');
    }
    $c->log->debug("type=".$upload->type."; size=".$upload->size."; filename=".$upload->filename.";");

    my $filepath = $upload->tempname;
    my $filepath_converted = $filepath;
    $filepath_converted =~s/\.([^\.]+)$/\.converted.$1/;

    #my $ft = File::Type->new();
    #my $greetingfile = delete $form->values->{'greetingfile'};
    #my $mime_type = $ft->mime_type($greetingfile);
    #if(('edit' eq $action) &&('audio/x-wav' ne $mime_type && 'application/octet-stream' ne $mime_type)){
    #    die('Wrong mime-type '.$mime_type.' for the voicemail greeting. Must be a audio file in the "wav" format');
    #    return;
    #}
    my @cmd = ( $filepath, '-e', 'gsm', '-b', '16', '-r', '8000', '-c', '1', $filepath_converted);
    my $output = '';
    $c->log->debug("cmd=".join(" ", 'sox', @cmd));
    eval {
        $output = capturex('sox', @cmd);
    };
    $c->log->debug("cmd=".join(" ", 'sox', @cmd)."; output=$output; \$\@=".($@?$@:'').';');
    if($output || $@){
        die('Wrong file format for the voicemail greeting. Must be a audio file in the "wav" format with "gsm" encoding.');
    }
    my $data = read_file($filepath_converted, {binmode => ':raw'},);
    if(!length($data)){
        die('Empty greeting file after conversion to GSM encoding.');
    }
    ${$params{converted_data_ref}} = \$data;
}

sub number_as_string{
    my ($number_row, %params) = @_;
    return 'HASH' eq ref $number_row
        ? $number_row->{cc} . ($number_row->{ac} // '') . $number_row->{sn}
        : $number_row->cc . ($number_row->ac // '') . $number_row->sn;
}

sub lookup {
    my (%params) = @_;

    my ($c, $lookup) = @{params}{qw(c lookup)};

    my $rs = $c->model('DB')->resultset('voip_subscribers')->search({
        'voip_dbaliases.username' => { 'like' => $lookup.'%' },
        status => { '!=' => 'terminated' },
    }, {
        join => { 'provisioning_voip_subscriber' => 'voip_dbaliases' },
        order_by => { -desc => qw/voip_dbaliases.username/ },
    });
    if (not $rs->first and $lookup =~ /(\S+?)\@(\S+)/) {
        $rs = $c->model('DB')->resultset('voip_subscribers')->search({
            username => $1,
            'domain.domain' => $2,
            status => { '!=' => 'terminated' },
        }, {
            join => 'domain',
        });
    }
    return $rs->first || undef;
}

sub create_cf_destination{
    my %params = @_;
    my($c,$subscriber,$cf_type,$set,$fields) = @params{qw/c subscriber cf_type set fields/};
    my $number = $subscriber->primary_number;
    my $numberstr = "";
    if(defined $number) {
        $numberstr .= $number->cc;
        $numberstr .= $number->ac if defined($number->ac);
        $numberstr .= $number->sn;
    } else {
        $numberstr = $subscriber->uuid;
    }
    foreach my $dest(@$fields) {
        my $d = $dest->field('destination')->value;
        my $t = 300;
        if ($d eq "uri") {
            $t = $dest->field('uri')->field('timeout')->value;
            # TODO: check for valid timeout here
        }
        $d = NGCP::Panel::Utils::Subscriber::field_to_destination(
                number => $numberstr,
                domain => $subscriber->domain->domain,
                destination => $d,
                uri => $dest->field('uri')->field('destination')->value,
                cf_type => $cf_type,
            );

        $set->voip_cf_destinations->create({
            destination => $d,
            timeout => $t,
            priority => ( $dest->field('priority') && $dest->field('priority')->value ) ? $dest->field('priority')->value : 1,
            announcement_id => (('customhours' eq $dest->field('destination')->value) and $dest->field('announcement_id')->value) || undef,
        });
    }
}

sub get_subscriber_pbx_status{
    my($c, $subscriber) = @_;
    if($c->config->{features}->{cloudpbx}) {
        my $pbx_pref = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
            c => $c,
            attribute => 'cloud_pbx',
            prov_subscriber => $subscriber->provisioning_voip_subscriber
        );
        if($pbx_pref->first) {
            return 1;
        }
    }
    return 0;
}

sub get_voicemail_filename {
    my ($c, $voicemail_item, $format) = @_;
    $format //= 'wav';
    return 'voicemail-'.$voicemail_item->msgnum.'.'.$format;
}

sub get_voicemail_content_type {
    my($c, $format) = @_;

    SWITCH: for ($format) {
        /^wav$/ && return "audio/x-wav";
        /^mp3$/ && return "audio/mpeg";
        /^ogg$/ && return "audio/ogg";
        return;
    }
    return;
}

sub delete_callrecording {
    my %params = @_;
    my($recording) = @params{qw/recording/};

    foreach my $stream($recording->recording_streams->all) {
        -e $stream->full_filename and unlink($stream->full_filename);
    }
    $recording->recording_streams->delete;
    $recording->recording_metakeys->delete;
    $recording->delete;
}

1;

=head1 NAME

NGCP::Panel::Utils::Subscriber

=head1 DESCRIPTION

A temporary helper to manipulate subscriber data

=head1 METHODS

=head2 update_subscriber_numbers

This reimplements the behavior of ossbss. When adding numbers to a subscriber,
we first check, if the number is already available in voip_numbers but
has no subscriber_id set. In that case we can just reuse that number.
If the number does not exist at all, we just create it.
For reference see _get_number_for_update() in ossbss.

=head2 check_cf_ivr

old_aa and new_aa are boolean params that determine if a cf mapping had an autoattendant
set before and after update. it will then create the according start_ivr or
end_ivr entry.

    the logic:
    change/delete dset:
        check each mapping
    change/create/delete mapping:
        check old/new dset (may be false)

=head2 check_dset_autoattendant_status

Returns a boolean value, if the dset has an autoattendant destination. Can be used
for check_cf_ivr().

=head1 AUTHOR

Andreas Granig,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
# vim: set tabstop=4 expandtab:
