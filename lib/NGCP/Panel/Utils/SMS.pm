package NGCP::Panel::Utils::SMS;

use Sipwise::Base;
use LWP::UserAgent;
use URI;
use POSIX;
use UUID;
use Module::Load::Conditional qw/can_load/;

use NGCP::Panel::Utils::Utf8;

sub send_sms {
    my (%args) = @_;
    my $c = $args{c};
    my $caller = $args{caller};
    my $callee = $args{callee};
    my $text = $args{text};
    my $coding = $args{coding};
    my $err_code = $args{err_code};

    if (!defined $err_code || ref $err_code ne 'CODE') {
        $err_code = sub { return; };
    }

    unless(defined $coding) {
        # if unicode, we have to use utf8 encoding, limiting our
        # text length to 70; otherwise send as default
        # encoding, allowing 160 chars
        if(NGCP::Panel::Utils::Utf8::is_within_ascii($text)) {
            $coding = 0;
        } else {
            $coding = 2;
        }
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
            charset => "utf-8",
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
        &{$err_code}("Error with send_sms: " . $res->status_line);
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
    if(NGCP::Panel::Utils::Utf8::is_within_ascii($text)) {
        $maxlen = 160;
    } else {
        $maxlen = 70;
    }
    return ceil(length($text) / $maxlen);
}

sub perform_prepaid_billing {
    my (%args) = @_;
    my $c = $args{c};
    my $prov_subscriber = $args{prov_subscriber};
    my $parts = $args{parts};
    my $caller = $args{caller};
    my $callee = $args{callee};

    my ($uuid, $session_id);
    UUID::generate($uuid);
    UUID::unparse($uuid, $session_id);

    my ($prepaid_lib, $is_prepaid);
    my $prepaid_pref_rs = NGCP::Panel::Utils::Preferences::get_dom_preference_rs(
        c => $c, attribute => 'prepaid_library',
        prov_domain => $prov_subscriber->domain,
    );
    if($prepaid_pref_rs && $prepaid_pref_rs->first) {
        $prepaid_lib = $prepaid_pref_rs->first->value;
    }

    $prepaid_pref_rs = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
        c => $c, attribute => 'prepaid',
        prov_subscriber => $prov_subscriber,
    );
    if($prepaid_pref_rs && $prepaid_pref_rs->first && $prepaid_pref_rs->first->value) {
        $is_prepaid = 1;
    } else {
        $is_prepaid = 0;
    }

    # currently only inew rating supported, let others pass
    return 1 unless($is_prepaid && $prepaid_lib eq "libinewrate");

    my $use_list = { 'NGCP::Rating::Inew::SmsSession' => undef };
    unless(can_load($use_list)) {
        $c->log->error("Failed to load NGCP::Rating::Inew::SmsSession for sms from $caller to $callee");
        return;
    }
    my $amqr = NGCP::Rating::Inew::SmsSession::init(
        $c->config->{libinewrate}->{soap_uri},
        $c->config->{libinewrate}->{openwire_uri},
    );
    unless($amqr) {
        $c->log->error("Failed to create sms amqr handle from $caller to $callee");
        return;
    }
    # Reserve credit for each part, and then commit each reservation.
    # If we can charge multiple times within one session - perfect.
    # Otherwise we have to create one session per part, store it in an
    # array, then after all reservations were successful, commit each
    # of them!
    my @sessions = ();
    my @failed_sessions = ();
    for(my $i = 0; $i < $parts; ++$i) {
        my $has_credit = 1;
        my $this_session_id = $session_id."-".$i;
        my $sess = NGCP::Rating::Inew::SmsSession::session_create(
            $amqr, $this_session_id, $caller, $callee, sub {
                $has_credit = 0;
        });
        unless($sess) {
            $c->log->error("Failed to create sms rating session from $caller to $callee with session id $this_session_id");
            last;
        }
        unless(NGCP::Rating::Inew::SmsSession::session_sms_reserve($sess)) {
            $c->log->error("Failed to reserve sms session from $caller to $callee with session id $this_session_id");
            push @failed_sessions, $sess;
            last;
        }
        unless($has_credit) {
            $c->log->info("No credit for sms from $caller to $callee with session id $this_session_id");
            push @failed_sessions, $sess;
            last;
        }
        push @sessions, $sess;
    }
    if(@sessions == $parts) {
        foreach my $sess(@sessions) {
            NGCP::Rating::Inew::SmsSession::session_sms_commit($sess);
            NGCP::Rating::Inew::SmsSession::session_destroy($sess);
        }
        NGCP::Rating::Inew::SmsSession::destroy($amqr);
        return 1;
    } else {
        foreach my $sess(@sessions) {
            NGCP::Rating::Inew::SmsSession::session_sms_discard($sess);
            NGCP::Rating::Inew::SmsSession::session_destroy($sess);
        }
        foreach my $sess(@failed_sessions) {
            NGCP::Rating::Inew::SmsSession::session_sms_discard($sess);
            NGCP::Rating::Inew::SmsSession::session_destroy($sess);
        }
        NGCP::Rating::Inew::SmsSession::destroy($amqr);
        return;
    }
}

1;
