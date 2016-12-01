package NGCP::Panel::Utils::SMS;

use Sipwise::Base;
use LWP::UserAgent;
use URI;

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
            coding => $coding // "2",
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

1;
