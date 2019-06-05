package NGCP::Panel::Utils::SMS;

use Sipwise::Base;
use LWP::UserAgent;
use URI;
use POSIX;
use UUID;
use Module::Load::Conditional qw/can_load/;

use NGCP::Panel::Utils::Utf8;
use NGCP::Panel::Utils::Preferences;
use NGCP::Panel::Utils::BillingMappings qw();

sub get_coding {
    my $text = shift;

    # if unicode, we have to use utf8 encoding, limiting our
    # text length to 70; otherwise send as default
    # encoding, allowing 160 chars

    my $coding;
    if(NGCP::Panel::Utils::Utf8::is_within_ascii($text) ||
       NGCP::Panel::Utils::Utf8::is_within_latin1($text)) {
        $coding = 0;
    } else {
        $coding = 2;
    }

    return $coding;
}

sub send_sms {
    my (%args) = @_;
    my $c = $args{c};
    my $caller = $args{caller};
    my $callee = $args{callee};
    my $text = $args{text};
    my $coding = $args{coding};
    my $err_code = $args{err_code};
    my $smsc_peer = $args{smsc_peer};

    if (!defined $err_code || ref $err_code ne 'CODE') {
        $err_code = sub { return; };
    }

    unless(defined $coding) {
        $coding = get_coding($text);
    }

    my $schema = $c->config->{sms}{schema};
    my $host = $c->config->{sms}{host};
    my $port = $c->config->{sms}{port};
    my $path = $c->config->{sms}{path};
    my $user = $c->config->{sms}{user};
    my $pass = $c->config->{sms}{pass};

    my $fullpath = "$schema://$host:$port$path";
    my $ua = LWP::UserAgent->new(
            #ssl_opts => { verify_hostname => 0, SSL_verify_mode => 0 },
            timeout => 5,
        );
    my $uri = URI->new($fullpath);
    $uri->query_form(
            charset => "UTF-8",
            smsc => $smsc_peer,
            coding => $coding,
            user => "$user",
            pass => "$pass",
            text => $text,
            to => $callee,
            from => $caller,
        );
    my $res = $ua->get($uri);
    if ($res->is_success) {
        return 1;
    } else {
        &{$err_code}("Error sending sms: " . $res->status_line);
        return;
    }
}

# false if error, true if ok
# TODOs: normalization?
sub check_numbers {
    my ($c, $resource, $prov_subscriber, $err_code) = @_;

    if (!defined $err_code || ref $err_code ne 'CODE') {
        $err_code = sub { return; };
    }

    my $pref_rs_allowed_clis = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
            c => $c, attribute => "allowed_clis",
            prov_subscriber => $prov_subscriber,
        );
    my @allowed_clis = $pref_rs_allowed_clis->get_column('value')->all;
    my $pref_rs_user_cli = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
            c => $c, attribute => "user_cli",
            prov_subscriber => $prov_subscriber,
        );
    my $user_cli = defined $pref_rs_user_cli->first ? $pref_rs_user_cli->first->value : undef;
    my $pref_rs_cli = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
            c => $c, attribute => "cli",
            prov_subscriber => $prov_subscriber,
        );
    my $cli = defined $pref_rs_cli->first ? $pref_rs_cli->first->value : undef;

    if ($resource->{caller}) {
        my $anumber_ok = 0;
        for my $number (@allowed_clis, $user_cli, $cli) {
            next unless $number;
            if ( _glob_matches($number, $resource->{caller}) ) {
                $anumber_ok = 1;
            }
        }
        unless ($anumber_ok) {
            return unless &{$err_code}("Invalid 'caller'", 'caller');
        }
    } else {
        if ($user_cli) {
            $resource->{caller} = $user_cli;
        } elsif ($cli) {
            $resource->{caller} = $cli;
        } else {
            return unless &{$err_code}("Could not set value for 'caller'", 'caller');
        }
    }

    # done setting/checking anumber
    # checking bnumber
    for my $adm ('adm_', '') {
        my $pref_rs_block_out_list = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                c => $c, attribute => $adm."block_out_list",
                prov_subscriber => $prov_subscriber,
            );
        my @block_out_list = $pref_rs_block_out_list->all;
        my $pref_rs_block_out_mode = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                c => $c, attribute => $adm."block_out_mode",
                prov_subscriber => $prov_subscriber,
            );
        my $block_out_mode = defined $pref_rs_block_out_mode->first ? $pref_rs_block_out_mode->first->value : undef;

        if ($block_out_mode) {  # whitelist
            my $bnumber_ok = 0;
            for my $number (@block_out_list) {
                if (_glob_matches($number->value, $resource->{callee})) {
                    $bnumber_ok = 1;
                }
            }
            unless ($bnumber_ok) {
                return unless &{$err_code}("Callee Number is not on whitelist for outgoing calls (${adm}block_out_list)", 'callee');
            }
        } else {  # blacklist
            for my $number (@block_out_list) {
                if (_glob_matches($number->value, $resource->{callee})) {
                    return unless &{$err_code}("Callee Number is on blocklist for outgoing calls (${adm}block_out_list)", 'callee');
                }
            }
        }
    }

    return 1;
}

sub _glob_matches {
    my ($glob, $string) = @_;

    use Text::Glob;
    return !!Text::Glob::match_glob($glob, $string);
}

sub get_number_of_parts {
    my $text = shift;
    my $maxlen;
    if(NGCP::Panel::Utils::Utf8::is_within_ascii($text) ||
       NGCP::Panel::Utils::Utf8::is_within_latin1($text)) {
        # multi-part sms consist of 153 char chunks in ascii/latin1,
        # otherwise 160 for single sms
        $maxlen = length($text) <= 160 ? 160 : 153;
    } else {
        # multi-part sms consist of 67 char chunks in utf8,
        # otherwise 70 for single sms
        $maxlen = length($text) <= 70 ? 70 : 67;
    }
    return ceil(length($text) / $maxlen);
}

sub init_prepaid_billing {
    my (%args) = @_;
    my $c = $args{c};
    my $prov_subscriber = $args{prov_subscriber};
    my $parts = $args{parts};
    my $caller = $args{caller};
    my $callee = $args{callee};

    my ($uuid, $session_id);
    UUID::generate($uuid);
    UUID::unparse($uuid, $session_id);

    my $session = {
        caller => $caller,
        callee => $callee,
        status => 'ok',
        reason => 'accepted',
        parts  => [],
        sid    => $session_id,
        rpc    => $parts,
    };

    my ($prepaid_lib, $is_prepaid);
    my $bm_actual = NGCP::Panel::Utils::BillingMappings::get_actual_billing_mapping(c => $c, contract => $prov_subscriber->contract, );
    $prepaid_lib = $bm_actual->billing_profile->prepaid_library if $bm_actual;
    $is_prepaid = ($bm_actual->billing_profile->prepaid ? 1 : 0) if $bm_actual;

    # currently only inew rating supported, let others pass
    unless ($is_prepaid && $prepaid_lib && $prepaid_lib eq "libinewrate") {
        $session->{reason} = 'not prepaid/libinewrate';
        return $session;
    }

    my $use_list = { 'NGCP::Rating::Inew::SmsSession' => undef };
    unless(can_load(modules => $use_list, nocache => 0, autoload => 0)) {
        $c->log->error(sprintf
            "Failed to load NGCP::Rating::Inew::SmsSession for sms=%s from=%s to=%s",
                $session_id, $c->qs($caller), $c->qs($callee)
        );
        $session->{status} = 'failed';
        $session->{reason} =
            sprintf 'failed to init sms session sid=%s from=%s to=%s',
                $session_id, $c->qs($caller), $c->qs($callee);
        return;
    }
    my $amqr = NGCP::Rating::Inew::SmsSession::init(
        $c->config->{libinewrate}->{soap_uri},
        $c->config->{libinewrate}->{openwire_uri},
    );
    unless($amqr) {
        $c->log->error(sprintf
            "Failed to create sms amqr handle for sms sid=%s from=%s to=%s",
                $session_id, $c->qs($caller), $c->qs($callee)
        );
        $session->{status} = 'failed';
        $session->{reason} =
            sprintf 'failed to create sms session sid=%s from=%s to=%s',
                $session_id, $c->qs($caller), $c->qs($callee);
        return;
    }
    $session->{amqr_h} = $amqr;

    # Reserve credit for each part, and then commit each reservation.
    # If we can charge multiple times within one session - perfect.
    # Otherwise we have to create one session per part, store it in an
    # array, then after all reservations were successful, commit each
    # of them!
    for(my $i = 0; $i < $parts; ++$i) {
        my $has_credit = 1;
        my $this_session_id = $session_id."-".$i;

        my $sess = NGCP::Rating::Inew::SmsSession::session_create(
            $amqr, $this_session_id, $caller, $callee, sub {
                $has_credit = 0;
        });

        if (not defined $sess or $sess == -1) {
            $c->log->error("Failed to create sms rating session from " . $c->qs($caller) . ' to ' . $c->qs($callee) . " with session id $this_session_id");
            $session->{status} = 'failed';
            $session->{reason} = 'failed to create sms session';
            last;
        } elsif ($sess == 0) {
            $c->log->error("Remote denied sms rating session from " . $c->qs($caller) . ' to ' . $c->qs($callee) . " with session id $this_session_id (subscriber=inactive)");
            $session->{status} = 'failed';
            $session->{reason} = 'remote denied sms session (subscriber=inactive)';
            last;
        }

        unless($has_credit) {
            $c->log->info("No credit for sms from " . $c->qs($caller) . ' to ' . $c->qs($callee) . " with session id $this_session_id");
            $session->{status} = 'failed';
            $session->{reason} = 'insufficient credit';
            NGCP::Rating::Inew::SmsSession::session_destroy($sess);
            last;
        }

        push @{$session->{parts}}, $sess;

        unless(NGCP::Rating::Inew::SmsSession::session_sms_reserve($sess)) {
            $c->log->error("Failed to reserve sms session from " . $c->qs($caller) . ' to ' . $c->qs($callee) . " with session id $this_session_id");
            $session->{status} = 'failed';
            $session->{reason} = 'failed to reserve sms session';
            last;
        }
    }
    return $session;
}

sub perform_prepaid_billing {
    my (%args) = @_;
    my $c = $args{c};
    my $session = $args{session} // return;
    my $amqr    = $session->{amqr_h} // return;
    my ($rpc, $status, $reason, $parts) =
        @{$session}{qw(rpc status reason parts)};

    if ($status eq 'ok' && $rpc == $#{$parts}+1) {
        foreach my $sess (@{$parts}) {
            NGCP::Rating::Inew::SmsSession::session_sms_commit($sess);
            NGCP::Rating::Inew::SmsSession::session_destroy($sess);
        }
        NGCP::Rating::Inew::SmsSession::destroy($amqr);
    } else {
        cancel_prepaid_billing(%args);
    }
    return;
}

sub cancel_prepaid_billing {
    my (%args) = @_;
    my $c = $args{c};
    my $session = $args{session} // return;
    my $amqr    = $session->{amqr_h} // return;
    my ($rpc, $status, $reason, $parts) =
        @{$session}{qw(rpc status reason parts)};

    $reason //= 'unknown';

    foreach my $sess (@{$parts}) {
        NGCP::Rating::Inew::SmsSession::session_set_cancel_reason($sess, $reason);
        NGCP::Rating::Inew::SmsSession::session_sms_discard($sess);
        NGCP::Rating::Inew::SmsSession::session_destroy($sess);
    }
    NGCP::Rating::Inew::SmsSession::destroy($amqr);

    return;
}

sub add_journal_record {
    my (%args) = @_;
    my $c = $args{c};
    my $prov_subscriber = $args{prov_subscriber};

    $args{status} //= '';
    $args{reason} //= '';
    $args{coding} //= 0;
    $args{subscriber_id} = $args{prov_subscriber}->id;

    delete $args{c};
    delete $args{prov_subscriber};

    my $pref_rs_cli = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
            c => $c, attribute => "user_cli",
            prov_subscriber => $prov_subscriber,
        );

    my $cli = defined $pref_rs_cli->first ? $pref_rs_cli->first->value : undef;

    unless ($cli) {
        my $pref_rs_cli = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                c => $c, attribute => "cli",
                prov_subscriber => $prov_subscriber,
            );
        $cli = defined $pref_rs_cli->first ? $pref_rs_cli->first->value : '';
    }

    $args{cli} = $cli;

    return $c->model('DB')->resultset('sms_journal')->create(\%args);
}

1;
