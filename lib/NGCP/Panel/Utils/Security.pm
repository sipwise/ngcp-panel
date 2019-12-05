package NGCP::Panel::Utils::Security;
use Sipwise::Base;

use XML::LibXML;
use URI::Encode;
use NGCP::Panel::Utils::XMLDispatcher;
use NGCP::Panel::Utils::DateTime;

sub list_banned_ips  {
    my ( $c, %params ) = @_;
    my $dispatcher = NGCP::Panel::Utils::XMLDispatcher->new;
    my $xml_parser = XML::LibXML->new();

    my $ip_xml = <<'EOF';
<?xml version="1.0" ?>
<methodCall>
    <methodName>htable.dump</methodName>
    <params>
        <param><value><string>ipban</string></value></param>
    </params>
</methodCall>
EOF

    my $ip_res = $dispatcher->dispatch($c, "loadbalancer", 1, 1, $ip_xml);

    my @ips = ();
    XML_RESULTS_LOOP: for my $host (grep {$$_[1]} @$ip_res) {
        my $xmlDoc = $xml_parser->parse_string($host->[2]);
        foreach my $node ($xmlDoc->findnodes('//member')) {
            my $name = $node->findvalue('./name');
            my $value = $node->findvalue('./value/string');
            if ($name eq 'name') {
                if (!defined $params{id} || $params{id} eq $value) {
                    push @ips, { ip => $value, id => $value, };
                    if (defined $params{id}) {
                        last XML_RESULTS_LOOP;
                    }
                }
            }
        }
    }
    return \@ips;
}

sub list_banned_users  {
    my ( $c, %params ) = @_;

    my $dispatcher = NGCP::Panel::Utils::XMLDispatcher->new;
    my $xml_parser = XML::LibXML->new();

    my $user_xml = <<'EOF';
<?xml version="1.0" ?>
<methodCall>
    <methodName>htable.dump</methodName>
    <params>
        <param><value><string>auth</string></value></param>
    </params>
</methodCall>
EOF

    my $user_res = $dispatcher->dispatch($c, "loadbalancer", 1, 1, $user_xml);
    my @users = ();
    my $usr = {};
    for my $host (grep {$$_[1]} @$user_res) {
        my $xmlDoc = $xml_parser->parse_string($host->[2]);
        my $username = '';
        my $key = '';
        foreach my $node ($xmlDoc->findnodes('//member')) {
            my $name = $node->findvalue('./name');
            my $value = $node->findvalue('./value/string') ||
                        $node->findvalue('./value/int');
            if ($name eq 'name') {
                $value =~ m/(?<user>.*)::(?<key>.*)/;
                $username = $+{user};
                $key = $+{key};
            } elsif ($name eq 'value' && $username && $key) {
                # there souldn't be any other keys
                $key eq 'auth_count' and $usr->{$username}->{auth_count} = $value;
                $key eq 'last_auth' and $usr->{$username}->{last_auth} = $value;
            }
        }
    }
    my $config_failed_auth_attempts = $c->config->{security}->{failed_auth_attempts} // 3;
    #in case we requested to filter by username, we will use it as the only possible key
    my @user_ids;
    if (defined $params{id}) {
        if (exists $usr->{$params{id}}) {
            @user_ids = ($params{id});
        }
    }
    else {
        @user_ids = (keys %{ $usr });
    }
    for my $key (@user_ids) {
        my $last_auth = $usr->{$key}->{last_auth} ? NGCP::Panel::Utils::DateTime::epoch_local($usr->{$key}->{last_auth}) : undef;
        if($last_auth && $params{data_for_json}){
            $last_auth =  $last_auth->ymd.' '. $last_auth->hms;
        }
        if( defined $usr->{$key}->{auth_count} 
            && $usr->{$key}->{auth_count} >= $config_failed_auth_attempts ) {
            push @users, {
                username => $key,
                id => $key,
                auth_count => $usr->{$key}->{auth_count},
                last_auth  => $last_auth,
            };
        }
    }
    return \@users;
}

sub ip_unban {
    my ( $c, $ip ) = @_;
    my $decoder = URI::Encode->new;
    $ip = $decoder->decode($ip);
    my $dispatcher = NGCP::Panel::Utils::XMLDispatcher->new;

    my $xml = <<"EOF";
<?xml version="1.0" ?>
<methodCall>
    <methodName>htable.delete</methodName>
    <params>
        <param><value><string>ipban</string></value></param>
        <param><value><string>$ip</string></value></param>
    </params>
</methodCall>
EOF

    $dispatcher->dispatch($c, "loadbalancer", 1, 1, $xml);
}

sub user_unban {
    my ( $c, $user ) = @_;
    my $decoder = URI::Encode->new;
    $user = $decoder->decode($user);
    my $dispatcher = NGCP::Panel::Utils::XMLDispatcher->new;

    my @keys = ($user.'::auth_count', $user.'::last_auth');
    foreach my $key (@keys) {
        my $xml = <<"EOF";
<?xml version="1.0" ?>
<methodCall>
    <methodName>htable.delete</methodName>
    <params>
        <param><value><string>auth</string></value></param>
        <param><value><string>$key</string></value></param>
    </params>
</methodCall>
EOF

        $dispatcher->dispatch($c, "loadbalancer", 1, 1, $xml);
    }
}

1;

# vim: set tabstop=4 expandtab:
