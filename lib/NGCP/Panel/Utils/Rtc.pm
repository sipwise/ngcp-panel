package NGCP::Panel::Utils::Rtc;

use warnings;
use strict;

use JSON qw//;

use NGCP::Panel::Utils::ComxAPIClient;
use NGCP::Panel::Utils::Generic qw/compare/;

sub modify_reseller_rtc {
    my %params = @_;
    my ($old_resource, $resource, $config, $reseller_item, $err_code) =
        @params{qw/old_resource resource config reseller_item err_code/};

    if (!defined $err_code || ref $err_code ne 'CODE') {
        $err_code = sub { return 0; };
    }

    if ((!defined $old_resource) && (defined $resource)) { # newly created reseller

        # 1. enable_rtc is off -> do nothing
        if (!$resource->{enable_rtc}) {
            return;
        }

        _create_rtc_user(
            resource => $resource,
            config => $config,
            reseller_item => $reseller_item,
            err_code => $err_code);

    } elsif ((defined $old_resource) && (defined $resource)) {

        if($old_resource->{status} ne 'terminated' &&
                $resource->{status} eq 'terminated' &&
                $old_resource->{enable_rtc}) {  # just terminated

            $resource->{enable_rtc} = JSON::false;
            _delete_rtc_user(
                    config => $config,
                    reseller_item => $reseller_item,
                    err_code => $err_code);

        } elsif ($old_resource->{enable_rtc} &&
                !$resource->{enable_rtc}) {  # disable rtc

            _delete_rtc_user(
                config => $config,
                reseller_item => $reseller_item,
                err_code => $err_code);
        } elsif (!$old_resource->{enable_rtc} &&
                $resource->{enable_rtc} &&
                $resource->{status} ne 'terminated') {  # enable rtc

            _create_rtc_user(
                resource => $resource,
                config => $config,
                reseller_item => $reseller_item,
                err_code => $err_code);
        }
    }
    return;
}

sub _create_rtc_user {
    my %params = @_;
    my ($resource, $config, $reseller_item, $err_code) =
        @params{qw/resource config reseller_item err_code/};

    my $rtc_networks = $resource->{rtc_networks} // [];
    if ('ARRAY' ne (ref $rtc_networks)) {
        $rtc_networks = [$rtc_networks];
    }

    # 2. create user w reseller-name and reseller-name _ "pass"
    my $reseller_name = $resource->{name} =~ s/\s+//rg;

    my $comx = NGCP::Panel::Utils::ComxAPIClient->new(
        host => $config->{rtc}{schema}.'://'.
        $config->{rtc}{host}.':'.$config->{rtc}{port}.
        $config->{rtc}{path},
    );
    $comx->login(
        $config->{rtc}{user},
        $config->{rtc}{pass},
        $config->{rtc}{host}.':'.$config->{rtc}{port});
    if ($comx->login_status->{code} != 200) {
        return unless &{$err_code}(
            'Rtc Login failed. Check config settings.');
    }
    my $user = $comx->create_user(
            $reseller_name . '@ngcp.com',
            $reseller_name . 'pass12345',
        );
    if ($user->{code} != 201) {
        return unless &{$err_code}(
            'Creating rtc user failed. Error code: ' . $user->{code});
    }

    # 3. create relation in our db
    $reseller_item->create_related('rtc_user', {
            rtc_user_id => $user->{data}{id},
        });

    # 4. create related app
    my $app = $comx->create_app(
            $reseller_name . '_app',
            $reseller_name . 'www.sipwise.com',
            $user->{data}{id},
        );
    if ($app->{code} != 201) {
        return unless &{$err_code}(
            'Creating rtc app failed. Error code: ' . $app->{code});
    }

    # 5. create related networks
    for my $n (@{ $rtc_networks }) {
        my $n_response = $comx->create_network(
                $reseller_name . "_$n",
                $n . '-connector',
                {xms => JSON::false},
                $user->{data}{id},
            );
        if ($n_response->{code} != 201) {
            return unless &{$err_code}(
                'Creating rtc network failed. Error code: ' . $n_response->{code});
        }
    }
    return;
}

sub _delete_rtc_user {
    my %params = @_;
    my ($config, $reseller_item, $err_code) =
        @params{qw/config reseller_item err_code/};

    my $comx = NGCP::Panel::Utils::ComxAPIClient->new(
        host => $config->{rtc}{schema}.'://'.
        $config->{rtc}{host}.':'.$config->{rtc}{port}.
        $config->{rtc}{path},
    );
    $comx->login(
        $config->{rtc}{user},
        $config->{rtc}{pass},
        $config->{rtc}{host}.':'.$config->{rtc}{port});
    if ($comx->login_status->{code} != 200) {
        return unless &{$err_code}(
            'Rtc Login failed. Check config settings.');
    }

    my $rtc_user = $reseller_item->rtc_user;
    if (!defined $rtc_user) {
        return unless &{$err_code}(
            'No rtc user found in db for this reseller.');
    }
    # app and networks are deleted automatically
    my $delete_resp = $comx->delete_user(
            $rtc_user->rtc_user_id,
        );
    if ($delete_resp->{code} == 200) {
        $rtc_user->delete;
    } else {
        return unless &{$err_code}(
            'Deleting rtc user failed. Error code: ' . $delete_resp->{code});
    }
    return;
}

sub get_rtc_networks {
    my %params = @_;
    my ($rtc_user_id, $config, $reseller_item, $include_id, $err_code) =
        @params{qw/rtc_user_id config reseller_item include_id err_code/};

    if (!defined $err_code || ref $err_code ne 'CODE') {
        $err_code = sub { return 0; };
    }

    my $comx = NGCP::Panel::Utils::ComxAPIClient->new(
        host => $config->{rtc}{schema}.'://'.
        $config->{rtc}{host}.':'.$config->{rtc}{port}.
        $config->{rtc}{path},
    );
    $comx->login(
        $config->{rtc}{user},
        $config->{rtc}{pass},
        $config->{rtc}{host}.':'.$config->{rtc}{port});
    if ($comx->login_status->{code} != 200) {
        return unless &{$err_code}(
            'Rtc Login failed. Check config settings.');
    }

    my $networks_resp = $comx->get_networks_by_user_id($rtc_user_id);
    my $networks = $networks_resp->{data};
    unless (defined $networks  && 'ARRAY' eq ref $networks && @{ $networks }) {
        return unless &{$err_code}(
            'Fetching networks failed. Code: ' . $networks_resp->{code});
    }

    my $res = [map {{
            config =>$_->{config},
            connector => $_->{connector},
            tag => $_->{tag},
            $include_id ? (id => $_->{id}) : (),
        }} @{ $networks }];

    return $res;
}

sub modify_rtc_networks {
    my %params = @_;
    my ($old_resource, $resource, $config, $reseller_item, $err_code) =
        @params{qw/old_resource resource config reseller_item err_code/};

    if (!defined $err_code || ref $err_code ne 'CODE') {
        $err_code = sub { return 0; };
    }

    if ((!defined $old_resource) || (!defined $resource)) { # can only modify (no create/delete) the whole resource
        return unless &{$err_code}(
            'Cannot Modify rtc network. Old or new resource missing.');
    }

    my $comx = NGCP::Panel::Utils::ComxAPIClient->new(
        host => $config->{rtc}{schema}.'://'.
        $config->{rtc}{host}.':'.$config->{rtc}{port}.
        $config->{rtc}{path},
    );
    $comx->login(
        $config->{rtc}{user},
        $config->{rtc}{pass},
        $config->{rtc}{host}.':'.$config->{rtc}{port});
    if ($comx->login_status->{code} != 200) {
        return unless &{$err_code}(
            'Rtc Login failed. Check config settings.');
    }

    my (@deleted, @new);
    for my $nw (@{ $resource->{networks} }) {
        my $nw_tag = $nw->{tag};
        my ($old_nw) = grep {$nw_tag eq $_->{tag}} @{ $old_resource->{networks} };
        if (!defined $old_nw) {
            push @new, $nw;
        } else {
            if ($nw->{connector} ne $old_nw->{connector}
                    || !compare($nw->{config}, $old_nw->{config})
                ) {
                push @deleted, $old_nw;
                push @new, $nw;
            }
        }
    }
    for my $nw (@{ $old_resource->{networks} }) {
        my $nw_tag = $nw->{tag};

        my ($new_nw) = grep {$nw_tag eq $_->{tag}} @{ $resource->{networks} };
        if (!defined $new_nw) {
            push @deleted, $nw;
        }
    }

    for my $nw (@deleted) {
        my $n_response = $comx->delete_network($nw->{id});
        if ($n_response->{code} != 200) {
            return unless &{$err_code}(
                'Deleting rtc network failed. Error code: ' . $n_response->{code});
        }
    }
    for my $nw (@new) {
        my $n_response = $comx->create_network(
                $nw->{tag},
                $nw->{connector},
                $nw->{config} // {},
                $old_resource->{rtc_user_id},
            );
        if ($n_response->{code} != 201) {
            return unless &{$err_code}(
                'Creating rtc network failed. Error code: ' . $n_response->{code});
        }
    }
    return;
}

1;

# vim: set tabstop=4 expandtab:
