package NGCP::Panel::Utils::Rtc;

use warnings;
use strict;

use DDP use_prototypes=>0;

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

        $reseller_item->create_related('rtc_user', {
                rtc_user_id => $user->{data}{id},
            });
    }
}

1;

# vim: set tabstop=4 expandtab:
