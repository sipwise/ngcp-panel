package NGCP::Panel::Utils::Rtc;

use warnings;
use strict;

use DDP use_prototypes=>0;
use JSON qw//;

use NGCP::Panel::Utils::ComxAPIClient;

sub modify_reseller_rtc {
    my ($old_resource, $resource, $config, $reseller_item, $err_code) = @_;

    if (!defined $err_code || ref $err_code ne 'CODE') {
        $err_code = sub { return 0; };
    }

    if ((!defined $old_resource) && (defined $resource)) { # newly created reseller

        # 1. enable_rtc is off -> do nothing
        if (!$resource->{enable_rtc}) {
            return;
        }

        _create_rtc_user($resource, $config, $reseller_item, $err_code);

    } elsif ((defined $old_resource) && (defined $resource)) {

        p $reseller_item;
        p $reseller_item->rtc_user;
        if($old_resource->{status} ne 'terminated' &&
                $resource->{status} eq 'terminated' &&
                $old_resource->{enable_rtc}) {  # just terminated

            $resource->{enable_rtc} = JSON::false;
            _delete_rtc_user($config, $reseller_item, $err_code);

        } elsif ($old_resource->{enable_rtc} &&
                !$resource->{enable_rtc}) {  # disable rtc

            _delete_rtc_user($config, $reseller_item, $err_code);
        } elsif (!$old_resource->{enable_rtc} &&
                $resource->{enable_rtc} &&
                $resource->{status} ne 'terminated') {  # enable rtc

            _create_rtc_user($resource, $config, $reseller_item, $err_code);
        }
    }
}

sub _create_rtc_user {
    my ($resource, $config, $reseller_item, $err_code) = @_;

    my $rtc_networks = $resource->{rtc_networks} // [];
    if ('ARRAY' ne (ref $rtc_networks)) {
        $rtc_networks = [$rtc_networks];
    }

    # 2. create user w reseller-name and reseller-name _ "pass"
    my $reseller_name = $resource->{name} =~ s/\s+//rg;

    my $comx = NGCP::Panel::Utils::ComxAPIClient->new(
        host => $config->{rtc}{host},
    );
    $comx->login($config->{rtc}{user},
        $config->{rtc}{pass}, $config->{rtc}{netloc});
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
        if ($user->{code} != 201) {
            return unless &{$err_code}(
                'Creating rtc network failed. Error code: ' . $user->{code});
        }
    }
}

sub _delete_rtc_user {
    my ($config, $reseller_item, $err_code) = @_;

    my $comx = NGCP::Panel::Utils::ComxAPIClient->new(
        host => $config->{rtc}{host},
    );
    $comx->login($config->{rtc}{user},
        $config->{rtc}{pass}, $config->{rtc}{netloc});
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
}

sub get_rtc_networks {
    my ($rtc_user_id, $config, $reseller_item, $err_code) = @_;

    if (!defined $err_code || ref $err_code ne 'CODE') {
        $err_code = sub { return 0; };
    }

    my $comx = NGCP::Panel::Utils::ComxAPIClient->new(
        host => $config->{rtc}{host},
    );
    $comx->login($config->{rtc}{user},
        $config->{rtc}{pass}, $config->{rtc}{netloc});
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

    my $res = [map {{config =>$_->{config}, connector => $_->{connector}, tag => $_->{tag}}} @{ $networks }];

    return $res;
}

1;

# vim: set tabstop=4 expandtab:
