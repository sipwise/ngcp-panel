package NGCP::Panel::Utils::Rtc;

use warnings;
use strict;

use JSON qw//;
use UUID;

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
            'Rtc Login failed. Check config settings. Status code: ' . $comx->login_status->{code}, $comx->login_status->{debug});
    }
    my ($uuid_bin, $uuid);
    UUID::generate($uuid_bin);
    UUID::unparse($uuid_bin, $uuid);
    my $rand = get_random(10, $err_code);
    return unless $rand;
    my $pass = unpack("H*", $rand);
    my $user = $comx->create_user(
            $uuid . '@ngcp.local',
            $pass,
        );
    if ($user->{code} != 201) {
        return unless &{$err_code}(
            'Creating rtc user failed. Error code: ' . $user->{code}, $user->{debug});
    }

    # 3. create relation in our db
    $reseller_item->create_related('rtc_user', {
            rtc_user_id => $user->{data}{id},
        });

    # 4. create related app
    my $app = $comx->create_app(
            $uuid . '_default_app',
            $uuid . '.sipwise.local',
            $user->{data}{id},
        );
    if ($app->{code} != 201) {
        return unless &{$err_code}(
            'Creating rtc app failed. Error code: ' . $app->{code}, $app->{debug});
    }

    # 5. create related networks
    for my $n (@{ $rtc_networks }) {
        my $connector;
        if ($n =~ m/^(sip|xmpp)$/) {
            $connector = "$n-connector";
        } else {
            $connector = $n;
        }
        my $n_response = $comx->create_network(
                $n,
                $connector,
                {xms => JSON::false},
                $user->{data}{id},
            );
        if ($n_response->{code} != 201) {
            return unless &{$err_code}(
                'Creating rtc network failed. Error code: ' . $n_response->{code}, $n_response->{debug});
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
            'Rtc Login failed. Check config settings. Status code: ' . $comx->login_status->{code}, $comx->login_status->{debug});
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
            'Deleting rtc user failed. Error code: ' . $delete_resp->{code}, $delete_resp->{debug});
    }
    return;
}

sub get_rtc_apps {
    my %params = @_;
    my ($rtc_user_id, $config, $include_id, $err_code) =
        @params{qw/rtc_user_id config include_id err_code/};

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

    my $apps_resp = $comx->get_apps_by_user_id($rtc_user_id);
    my $apps = $apps_resp->{data};
    unless (defined $apps  && 'ARRAY' eq ref $apps && @{ $apps }) {
        return unless &{$err_code}(
            'Fetching apps failed. Code: ' . $apps_resp->{code});
    }

    my $res = [map {{
            domain =>$_->{domain},
            name => $_->{name},
            secret => $_->{secret},
            api_key => $_->{apiKey}, # todo: which spelling do we use?
            $include_id ? (id => $_->{id}) : (),
        }} @{ $apps }];

    return $res;
}

sub modify_rtc_apps {
    my %params = @_;
    my ($old_resource, $resource, $config, $reseller_item, $err_code) =
        @params{qw/old_resource resource config reseller_item err_code/};
    #TODO: stub, to be done

    if (!defined $err_code || ref $err_code ne 'CODE') {
        $err_code = sub { return 0; };
    }

    if ((!defined $old_resource) || (!defined $resource)) { # can only modify (no create/delete) the whole resource
        return unless &{$err_code}(
            'Cannot Modify rtc app. Old or new resource missing.');
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
            'Rtc Login failed. Check config settings. Status code: ' . $comx->login_status->{code}, $comx->login_status->{debug});
    }

    my (@deleted, @new);
    for my $a (@{ $resource->{apps} }) {
        my $app_name = $a->{name};
        my ($old_app) = grep {$app_name eq $_->{name}} @{ $old_resource->{apps} };
        if (!defined $old_app) {
            push @new, $a;
        } else {
            if ($a->{domain} ne $old_app->{domain}) {
                push @deleted, $old_app;
                push @new, $a;
            }
        }
    }
    for my $a (@{ $old_resource->{apps} }) {
        my $app_name = $a->{name};

        my ($new_app) = grep {$app_name eq $_->{name}} @{ $resource->{apps} };
        if (!defined $new_app) {
            push @deleted, $a;
        }
    }

    for my $app (@deleted) {
        my $a_response = $comx->delete_app($app->{id});
        if ($a_response->{code} != 200) {
            return unless &{$err_code}(
                'Deleting rtc app failed. Error code: ' . $a_response->{code});
        }
    }
    for my $app (@new) {
        my $a_response = $comx->create_app(
                $app->{name},
                $app->{domain},
                $old_resource->{rtc_user_id},
            );
        if ($a_response->{code} != 201) {
            return unless &{$err_code}(
                'Creating rtc app failed. Error code: ' . $a_response->{code});
        }
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
            'Rtc Login failed. Check config settings. Status code: ' . $comx->login_status->{code}, $comx->login_status->{debug});
    }

    my $networks_resp = $comx->get_networks_by_user_id($rtc_user_id);
    my $networks = $networks_resp->{data};
    unless (defined $networks  && 'ARRAY' eq ref $networks && @{ $networks }) {
        return unless &{$err_code}(
            'Fetching networks failed. Code: ' . $networks_resp->{code}, $networks_resp->{debug});
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
                'Deleting rtc network failed. Error code: ' . $n_response->{code}, $n_response->{debug});
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
                'Creating rtc network failed. Error code: ' . $n_response->{code}, $n_response->{debug});
        }
    }
    return;
}

# returns enable_rtc (true|false) and rtc_browser_token (string)
sub get_rtc_subscriber_data {
    my %params = @_;
    my ($prov_subs, $config, $err_code) =
        @params{qw/prov_subs config err_code/};

    if (!defined $err_code || ref $err_code ne 'CODE') {
        $err_code = sub { return 0; };
    }

    unless ($prov_subs) {
        return unless &{$err_code}(
            "Couldn't get rtc_subscriber_data. No provisioning subscriber.");
    }

    my $rtc_session = $prov_subs->rtc_session;
    unless ($rtc_session) {
        return {enable_rtc => 0};  # JSON::false ?
    }

    # TODO: huh? is this the right browser token?
    return {enable_rtc => 1, rtc_browser_token => 'abcde TODO'};
}

sub modify_subscriber_rtc {
    my %params = @_;
    my ($old_resource, $resource, $config, $prov_subs, $err_code) =
        @params{qw/old_resource resource config prov_subs err_code/};

    if (!defined $err_code || ref $err_code ne 'CODE') {
        $err_code = sub { return 0; };
    }

    if ((!defined $old_resource) && (defined $resource)) { # newly created reseller

        # 1. enable_rtc is off -> do nothing
        if (!$resource->{enable_rtc}) {
            return;
        }

        _create_subscriber_rtc(
            resource => $resource,
            config => $config,
            prov_subs => $prov_subs,
            err_code => $err_code);

    } elsif ((defined $old_resource) && (defined $resource)) {

        if($old_resource->{status} ne 'terminated' &&
                $resource->{status} eq 'terminated' &&
                $old_resource->{enable_rtc}) {  # just terminated

            $resource->{enable_rtc} = JSON::false;
            _delete_subscriber_rtc(
                    config => $config,
                    prov_subs => $prov_subs,
                    err_code => $err_code);

        } elsif ($old_resource->{enable_rtc} &&
                !$resource->{enable_rtc}) {  # disable rtc

            _delete_subscriber_rtc(
                config => $config,
                prov_subs => $prov_subs,
                err_code => $err_code);
        } elsif (!$old_resource->{enable_rtc} &&
                $resource->{enable_rtc} &&
                $resource->{status} ne 'terminated') {  # enable rtc

            _create_rtc_user(
                resource => $resource,
                config => $config,
                prov_subs => $prov_subs,
                err_code => $err_code);
        }
    }
    return;
}

sub _create_subscriber_rtc {
    my %params = @_;
    my ($resource, $config, $prov_subs, $err_code) =
        @params{qw/resource config prov_subs err_code/};

    my $reseller = $prov_subs->voip_subscriber->contract->contact->reseller;
    unless ($reseller) {
        return unless &{err_code}(
            'Creating subscriber rtc data failed. Reseller not found.');
    }
    my $rtc_user = $reseller->rtc_user;
    unless ($rtc_user) {
        return unless &{err_code}(
            'Creating subscriber rtc data failed. Reseller has not enabled rtc.');
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
            'Rtc Login failed. Check config settings. Status code: ' . $comx->login_status->{code}, $comx->login_status->{debug});
    }

    my $comx_apps = $comx->get_apps_by_user_id($rtc_user->rtc_user_id);
    my $comx_app;
    if ($comx_apps->{data} && @{ $comx_apps->{data} }){
        $comx_app = $comx_apps->{data}[0];
    } else {
        return unless &{$err_code}(
            '_create_subscriber_rtc: Could not find app.');
    }

    my $session = $comx->create_session(
            $comx_app->{id},
            $rtc_user->rtc_user_id,
        );
    if ($session->{code} != 201) {
        return unless &{$err_code}(
            'Creating rtc session failed. Error code: ' . $session->{code}, $session->{debug});
    }

    # # 3. create relation in our db
    # $prov_subs->create_related('rtc_session', {
    #         rtc_session_id => $session->{data}{id},
    #     });

    # # 4. create related app
    # my $app = $comx->create_app(
    #         $reseller_name . '_app',
    #         $reseller_name . 'www.sipwise.com',
    #         $user->{data}{id},
    #     );
    # if ($app->{code} != 201) {
    #     return unless &{$err_code}(
    #         'Creating rtc app failed. Error code: ' . $app->{code});
    # }

    # # 5. create related networks
    # for my $n (@{ $rtc_networks }) {
    #     my $n_response = $comx->create_network(
    #             $reseller_name . "_$n",
    #             $n . '-connector',
    #             {xms => JSON::false},
    #             $user->{data}{id},
    #         );
    #     if ($n_response->{code} != 201) {
    #         return unless &{$err_code}(
    #             'Creating rtc network failed. Error code: ' . $n_response->{code});
    #     }
    # }
    # return;
}

sub _delete_subscriber_rtc {
    # my %params = @_;
    # my ($config, $prov_subs, $err_code) =
    #     @params{qw/config prov_subs err_code/};

    # my $comx = NGCP::Panel::Utils::ComxAPIClient->new(
    #     host => $config->{rtc}{schema}.'://'.
    #     $config->{rtc}{host}.':'.$config->{rtc}{port}.
    #     $config->{rtc}{path},
    # );
    # $comx->login(
    #     $config->{rtc}{user},
    #     $config->{rtc}{pass},
    #     $config->{rtc}{host}.':'.$config->{rtc}{port});
    # if ($comx->login_status->{code} != 200) {
    #     return unless &{$err_code}(
    #         'Rtc Login failed. Check config settings. Status code: ' . $comx->login_status->{code}, $comx->login_status->{debug});
    # }

    # my $rtc_user = $reseller_item->rtc_user;
    # if (!defined $rtc_user) {
    #     return unless &{$err_code}(
    #         'No rtc user found in db for this reseller.');
    # }
    # # app and networks are deleted automatically
    # my $delete_resp = $comx->delete_user(
    #         $rtc_user->rtc_user_id,
    #     );
    # if ($delete_resp->{code} == 200) {
    #     $rtc_user->delete;
    # } else {
    #     return unless &{$err_code}(
    #         'Deleting rtc user failed. Error code: ' . $delete_resp->{code});
    # }
    # return;
}

sub create_rtc_session {
    my %params = @_;
    my ($config, $err_code, $resource, $subscriber_item) =
        @params{qw/config err_code resource subscriber_item/};

    if (!defined $err_code || ref $err_code ne 'CODE') {
        $err_code = sub { return 0; };
    }

    my $reseller = $subscriber_item->contract->contact->reseller;
    unless ($reseller) {
        return unless &{$err_code}(
            'Creating subscriber rtc data failed. Reseller not found.');
    }

    my $rtc_user = $reseller->rtc_user;
    unless ($rtc_user) {
        return unless &{$err_code}(
            'Creating subscriber rtc data failed. Reseller has not enabled rtc.');
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
            'Rtc Login failed. Check config settings. Status code: ' . $comx->login_status->{code}, $comx->login_status->{debug});
    }

    my $comx_apps = $comx->get_apps_by_user_id($rtc_user->rtc_user_id);
    my $comx_app;
    if ($comx_apps->{data} && @{ $comx_apps->{data} }){
        if ($resource->{rtc_app_name}) {
            ($comx_app) = grep {$_->{name} eq $resource->{rtc_app_name}} @{ $comx_apps->{data} };
        } else { # default app
            ($comx_app) = grep {$_->{name} =~ m/_default_app$/;} @{ $comx_apps->{data} };
        }
    }
    unless ($comx_app) {
        return unless &{$err_code}(
            'create_rtc_session: Could not find app.');
    }

    my $comx_networks = $comx->get_networks_by_user_id($rtc_user->rtc_user_id);
    my $comx_network_tags = [];
    if ($comx_networks->{data} && 'ARRAY' eq ref $comx_networks->{data}) {
        $comx_network_tags = [ map { $_->{tag} } @{ $comx_networks->{data} } ];
    } else {
        return unless &{$err_code}(
            'create_rtc_session: Could not fetch networks for given rtc user.');
    }

    my $session = $comx->create_session(
            $comx_app->{id},
            $rtc_user->rtc_user_id,
        );
    if ($session->{code} != 201) {
        return unless &{$err_code}(
            'Creating rtc session failed. Error code: ' . $session->{code}, $session->{debug});
    }
    for my $n (@{ $comx_networks->{data} }) {
        my $identifier;
        if ($n->{connector} eq "sip-connector") {
            $identifier = 'sip:' . $subscriber_item->username . '@' . $subscriber_item->domain->domain;
        } elsif ($n->{connector} eq "xmpp-connector") {
            $identifier = 'xmpp:' . $subscriber_item->username . '@' . $subscriber_item->domain->domain;
        } else { # webrtc, ...
            $identifier = $subscriber_item->username;
        }
        my $account = $comx->create_account(
            $session->{data}{id},
            $rtc_user->rtc_user_id,
            $identifier,
            $n->{tag},
            $subscriber_item->provisioning_voip_subscriber->password,
            {xms => JSON::false},
        );
        if ($account->{code} != 201) {
            return unless &{$err_code}(
                "Creating rtc account ($n->{tag}) failed. Error code: " . $account->{code}, $account->{debug});
        }
    }

    my $rtc_session_item = $subscriber_item->provisioning_voip_subscriber->create_related('rtc_session', {
            rtc_session_id => $session->{data}{id},
        });
    return $rtc_session_item;
}

sub get_rtc_session {
    my %params = @_;
    my ($config, $item, $err_code) =
        @params{qw/config item err_code/};

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
            'Rtc Login failed. Check config settings. Status code: ' . $comx->login_status->{code}, $comx->login_status->{debug});
    }

    my $session = $comx->get_session($item->rtc_session_id);
    if ($session->{code} != 200) {
        return unless &{$err_code}(
            "Couldn't find session. Error code: " . $session->{code}, $session->{debug});
    }
    return $session;
}

sub get_random {
    my ($num, $err_code) = @_;
    my ($fd, $buf);
    unless(open($fd, '<', '/dev/urandom')) {
        return unless &{$err_code}("Failed to open /dev/urandom: $!");
    }
    unless(read($fd, $buf, $num) == $num) {
        return unless &{$err_code}("Failed to read $num bytes from /dev/urandom: $!");
    }
    close($fd);
    return $buf;
}

1;

# vim: set tabstop=4 expandtab:
