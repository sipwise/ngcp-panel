package NGCP::Panel::Utils::Subscriber;
use strict;
use warnings;

use Sipwise::Base;
use DBIx::Class::Exception;
use String::MkPasswd;
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Preferences;
use NGCP::Panel::Utils::Email;
use NGCP::Panel::Utils::Events;
use UUID qw/generate unparse/;
use JSON qw/decode_json encode_json/;
use IPC::System::Simple qw/capturex/;

my %LOCK = (
    0, 'none',
    1, 'foreign',
    2, 'outgoing',
    3, 'incoming and outgoing',
    4, 'global',
);


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
    my ($c, $destination) = @_;
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
    } else {
        my $d = $dest;
        $d =~ s/^sips?://;
        my $sub = $c->stash->{subscriber};
        if($sub && ($c->user->roles eq "subscriberadmin" || $c->user->roles eq "subscriber")) {
            my ($user, $domain) = split(/\@/, $d);
            $domain //= $sub->domain->domain;
            $user = NGCP::Panel::Utils::Subscriber::apply_rewrite(
                c => $c, subscriber => $sub, number => $user, direction => 'caller_out'
            );
            if($domain eq $sub->domain->domain) {
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

    my $c = $params{c};
    my $prov_subscriber= $params{prov_subscriber};
    my $level = $params{level};

    return unless $prov_subscriber;

    my $rs = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
        c => $c, 
        prov_subscriber => $prov_subscriber, 
        attribute => 'lock',
    );
    try {
        if($rs->first) {
            if($level == 0) {
                $rs->first->delete;
            } else {
                $rs->first->update({ value => $level });
            }
        } elsif($level > 0) { # nothing to do for level 0, if no lock is set yet
            $rs->create({ value => $level });
        }
    } catch($e) {
        $c->log->error("failed to set provisioning_voip_subscriber lock: $e");
        $e->rethrow;
    }
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

    my $schema = $params{schema} // $c->model('DB');
    my $reseller = $contract->contact->reseller;
    my $billing_domain = $schema->resultset('domains')
            ->find($params->{domain}{id} // $params->{domain_id});
    my $prov_domain = $schema->resultset('voip_domains')
            ->find({domain => $billing_domain->domain});

    my ($profile_set, $profile);
    if($params->{profile_set}{id}) {
        my $profile_set_rs = $c->model('DB')->resultset('voip_subscriber_profile_sets');
        if($c->user->roles eq "admin") {
        } elsif($c->user->roles eq "reseller") {
            $profile_set_rs = $profile_set_rs->search({
                reseller_id => $c->user->reseller_id,
            });
        }
        $profile_set = $profile_set_rs->find($params->{profile_set}{id});
        unless($profile_set) {
            $c->log->error("invalid subscriber profile set id '".$params->{profile_set}{id}."' detected");
            return;
        }
        if($params->{profile}{id}) {
            $profile = $profile_set->voip_subscriber_profiles->find({
                id => $params->{profile}{id},
            });
        }
        # TODO: use profile from user input if given
        unless($profile) {
            $profile = $profile_set->voip_subscriber_profiles->find({
                set_default => 1,
            });
        }
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
        if($params->{email}) {
            $contact = $c->model('DB')->resultset('contacts')->create({
                reseller_id => $contract->contact->reseller_id,
                email => $params->{email},
            });
            delete $params->{email};
        }


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

        if($prov_subscriber->profile_id) {
            NGCP::Panel::Utils::Events::insert(
                c => $c, schema => $schema, subscriber => $billing_subscriber,
                type => 'start_profile', old => undef, new => $prov_subscriber->profile_id
            );
        }
        if($prov_subscriber->is_pbx_group) {
            NGCP::Panel::Utils::Events::insert(
                c => $c, schema => $schema, subscriber => $billing_subscriber,
                type => 'start_huntgroup', old => undef, new => $prov_subscriber->profile_id
            );
        }

        if(defined $params->{e164range} && ref $params->{e164range} eq "ARRAY") {
            my @alias_numbers = ();
            foreach my $range(@{ $params->{e164range} }) {
                if(defined $range->{e164range}{cc} && $range->{e164range}{cc} ne '') {
                    my $len = $range->{e164range}{snlength};
                    foreach my $ext(0 .. int("9" x $len)) {
                        $range->{e164range}{sn} = sprintf("%s%0".$len."d", $range->{e164range}{snbase}, $ext);
                        push @alias_numbers, { e164 => {
                            cc => $range->{e164range}{cc},   
                            ac => $range->{e164range}{ac},   
                            sn => $range->{e164range}{sn},   
                        }};
                    }
                }
            }
            if(@alias_numbers) {
                update_subscriber_numbers(
                    c => $c,
                    schema => $schema,
                    subscriber_id => $billing_subscriber->id,
                    reseller_id => $reseller->id,
                    alias_numbers => \@alias_numbers,
                );
            }
        }


        return $billing_subscriber;
    });
}
sub update_subscriber_pbx_policy {
    my (%params) = @_;
    my $c = $params{c};
    my $prov_subscriber = $params{prov_subscriber};
    my $values = $params{values};

   #todo: use update_preferences instead?

    foreach(qw/cloud_pbx_hunt_policy cloud_pbx_hunt_timeout/){
        my $preference = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
            c => $c, 
            prov_subscriber => $prov_subscriber,
            attribute => $_
        );
        if($preference) {
            if($preference && $preference->first) {
                $preference->first->update({ value => $values->{$_} });
            } else {
                $preference->create({ value => $values->{$_} });
            }
        }
    }
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

sub update_pbx_group_prefs {
    my %params = @_;

    my $c = $params{c};
    my $schema = $params{schema} // $c->model('DB');
    my $old_group_id = $params{old_group_id};
    my $new_group_id = $params{new_group_id};
    my $username = $params{username};
    my $domain = $params{domain};
    my $group_rs = $params{group_rs} // $c->stash->{pbx_groups};

    return if(defined $old_group_id && defined $new_group_id && $old_group_id == $new_group_id);
    unless ($group_rs) {
        $c->log->warn('update_pbx_group_prefs: need a group_rs');
        return;
    }

    my $old_grp_subscriber;
    my $new_grp_subscriber;

    my $uri = "sip:$username\@$domain";
    if($old_group_id) {
        $old_grp_subscriber= $group_rs
                        ->find($old_group_id)
                        ->provisioning_voip_subscriber;
        if($old_grp_subscriber) {
            my $grp_pref_rs = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                c => $c, attribute => 'cloud_pbx_hunt_group', prov_subscriber => $old_grp_subscriber
            );
            my $pref = $grp_pref_rs->find({ value => $uri });
            $pref->delete if($pref);
        }
    }
    if($new_group_id) {
        $new_grp_subscriber = $group_rs
                        ->find($new_group_id)
                        ->provisioning_voip_subscriber;
        if($new_grp_subscriber) {
            my $grp_pref_rs = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                c => $c, attribute => 'cloud_pbx_hunt_group', prov_subscriber => $new_grp_subscriber
            );
            unless($grp_pref_rs->find({ value => $uri })) {
                $grp_pref_rs->create({ value => $uri });
            }
        }
    }
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
            $cli_pref->delete;
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
                $cli_pref->first->update({ value => $primary_number->{cc} . ($primary_number->{ac} // '') . $primary_number->{sn} });
            } else {
                $cli_pref->create({ 
                    subscriber_id => $prov_subs->id,
                    value => $primary_number->{cc} . ($primary_number->{ac} // '') . $primary_number->{sn} 
                });
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
                && $billing_subs->contract->billing_mappings->first->product->class eq "pbxaccount"
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
            my $acli_pref_tmpsub = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
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
        if($prov_subscriber && $prov_subscriber->profile_id) {
            NGCP::Panel::Utils::Events::insert(
                c => $c, schema => $schema, 
                subscriber => $subscriber, type => 'stop_profile', 
                old => $prov_subscriber->profile_id, new => undef,
            );
        }
        if($prov_subscriber && $prov_subscriber->is_pbx_group) {
            $schema->resultset('voip_pbx_groups')->search({
                group_id => $subscriber->provisioning_voip_subscriber->id,
            })->delete;
            NGCP::Panel::Utils::Events::insert(
                c => $c, schema => $schema, type => 'end_huntgroup',
                subscriber => $subscriber,
                old => $prov_subscriber->profile_id, new => undef,
            );
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
            foreach my $groups($prov_subscriber->voip_pbx_groups->all) {
                my $group_sub = $groups->group;
                update_pbx_group_prefs(
                    c => $c,
                    schema => $schema,
                    old_group_id => $group_sub->voip_subscriber->id,
                    new_group_id => undef,
                    username => $prov_subscriber->username,
                    domain => $prov_subscriber->domain->domain,
                    group_rs => $schema->resultset('voip_subscribers')->search({
                            contract_id => $subscriber->contract_id,
                            status => { '!=' => 'terminated' },
                        }),
                );
            }
            NGCP::Panel::Utils::Kamailio::delete_location($c, 
                $prov_subscriber);
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

    if($d eq "voicebox") {
        $d = "sip:vmu$number\@voicebox.local";
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
    } else {
        my $v = $uri;
        $v =~ s/^sips?://;
        my ($vuser, $vdomain) = split(/\@/, $v);
        $vdomain = $domain unless($vdomain);
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
    } else {
        $duri = $d;
        $d = 'uri';
    }
    return ($d, $duri);
}

sub uri_deflate {
    my ($v, $sub) = @_;
    $v =~ s/^sips?://;
    my $t;
    my ($user, $domain) = split(/\@/, $v);
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
        next if ($num->voip_subscribers->first); # is a primary number
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
    my $callee = $params{number};
    my $dir = $params{direction};
    return $callee unless $dir =~ /^(caller_in|callee_in|caller_out|callee_out)$/;

    my ($field, $direction) = split /_/, $dir;
    $dir = "rewrite_".$dir."_dpid";

    my $rwr_rs = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
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

    my $rule_rs = $c->model('DB')->resultset('voip_rewrite_rules')->search({
        'ruleset.'.$field.'_'.$direction.'_dpid' => $rwr_rs->first->value,
        direction => $direction,
        field => $field,
    }, {
        join => 'ruleset',
        order_by => { -asc => 'priority' }
    });
    my $cache = {};
    foreach my $r($rule_rs->all) {
        my @entries = ();
        my $match = $r->match_pattern;
        my $replace = $r->replace_pattern;

        #print ">>>>>>>>>>> match=$match, replace=$replace\n";
        for my $field($match, $replace) {
            #print ">>>>>>>>>>> normalizing $field\n";
            my @avps = ();
            @avps = ($field =~ /\$\(?avp\(s:calle(?:r|e)_([^\)]+)\)/g);
            @avps = keys %{{ map { $_ => 1 } @avps }};
            for my $avp(@avps) {
                if(!exists $cache->{$avp}) {
                    if($avp eq "cloud_pbx_account_cli_list") {
                        $cache->{$avp} = [];
                        foreach my $sub($subscriber->contract->voip_subscribers->all) {
                            foreach my $num($sub->voip_numbers->search({ status => 'active' })->all) {
                                my $v = $num->cc . ($num->ac // '') . $num->sn;
                                unless(grep { $v eq $_ } @{ $cache->{$avp} }) {
                                    push @{ $cache->{$avp} }, $v;
                                }
                            }
                        }
                    } else {
                        my $pref_rs = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                            c => $c, attribute => $avp,
                            prov_subscriber => $subscriber->provisioning_voip_subscriber,
                        );
                        unless($pref_rs && $pref_rs->count) {
                            $pref_rs = NGCP::Panel::Utils::Preferences::get_dom_preference_rs(
                                c => $c, attribute => $avp,
                                prov_domain => $subscriber->provisioning_voip_subscriber->domain,
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
                        $tmporig =~ s/\$avp\(s:calle(?:r|e)_$avp\)/$v/g;
                        $tmporig =~ s/\$\(avp\(s:calle(?:r|e)_$avp\)\[\*\]\)/$v/g;
                        push @{ $field }, $tmporig;
                    }
                } else {
                    my $orig = $field;
                    $orig = shift @{ $orig } if(ref $orig eq "ARRAY");
                    $orig =~ s/\$avp\(s:calle(?:r|e)_$avp\)/$val/g;
                    $field = [] unless(ref $field eq "ARRAY");
                    push @{ $field }, $orig;
                }
                #print ">>>>>>>>>>> normalized $field\n";
            }
        }

        $match = [ $match ] if(ref $match ne "ARRAY");

        $replace = shift @{ $replace } if(ref $replace eq "ARRAY");
        $replace =~ s/\\(\d{1})/\$$1/g;

        $replace =~ s/\"/\\"/g;
        $replace = qq{"$replace"};

        my $found;
        #print ">>>>>>>>>>> apply matches\n";
        foreach my $m(@{ $match }) {
            #print ">>>>>>>>>>>     m=$m, r=$replace\n";
            if($callee =~ s/$m/$replace/eeg) {
                # we only process one match
                #print ">>>>>>>>>>> match found, callee=$callee\n";
                $found = 1;
                last;
            }
        }
        last if $found;
        #print ">>>>>>>>>>> done, match=$match, replace=$replace, callee is $callee\n";
    }

    return $callee;
}

sub check_cf_ivr {
    my (%params) = @_;

    my $subscriber = $params{subscriber};
    my $schema = $params{schema};
    my $new_aa = $params{new_aa}; # boolean, false on delete
    my $old_aa = $params{old_aa}; # boolean, false on create
    if ($old_aa && !$new_aa) {
        NGCP::Panel::Utils::Events::insert(
            schema => $schema, subscriber => $subscriber,
            type => 'end_ivr',
        );
    } elsif (!$old_aa && $new_aa) {
        NGCP::Panel::Utils::Events::insert(
            schema => $schema, subscriber => $subscriber,
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

# order: voicemail_echo_number, cli, primary_number, '0'
sub update_voicemail_number {
    my (%params) = @_;

    my $schema = $params{schema};
    my $subscriber = $params{subscriber};

    my $prov_subs = $subscriber->provisioning_voip_subscriber;
    return unless $prov_subs;
    my $voicemail_user = $prov_subs->voicemail_user;
    my $new_cli;

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
    if (defined $echonumber_pref_rs->first) {
        $new_cli = $echonumber_pref_rs->first->value;
    } elsif (defined $cli_pref_rs->first) {
        $new_cli = $cli_pref_rs->first->value;
    } elsif (defined $subscriber->primary_number) {
        my $n = $subscriber->primary_number;
        $new_cli = $n->cc . ($n->ac // '') . $n->sn;
    } else {
        $new_cli = $subscriber->uuid;
    }

    if (defined $voicemail_user) {
        $voicemail_user->update({ mailbox => $new_cli });
    }

    for my $cfset ($prov_subs->voip_cf_destination_sets->all) {
        for my $cf ($cfset->voip_cf_destinations->all) {
            if($cf->destination =~ /\@voicebox\.local$/) {
                $cf->update({ destination => 'sip:vmu'.$new_cli.'@voicebox.local' });
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
