package NGCP::Panel::Utils::Sems;

use Sipwise::Base;
use NGCP::Panel::Utils::XMLDispatcher;
use Data::Dumper;

sub _get_outbound_socket {
    my ($c, $prefs) = @_;
    my ($contact, $transport);
    my $peer_rs = $c->model('DB')->resultset('voip_peer_hosts')->search({
        -or => [ ip => $prefs->{peer_auth_realm}, host => $prefs->{peer_auth_realm} ]
    });
    if($peer_rs->count) {
        my $peer = $peer_rs->first;
        my $outbound_sock_rs = NGCP::Panel::Utils::Preferences::get_peer_preference_rs(
            c => $c, attribute => 'outbound_socket',
            peer_host => $peer);
        if($outbound_sock_rs->count) {
            $contact  = substr($outbound_sock_rs->first->value, 4);
            $transport = ';transport=' . substr($outbound_sock_rs->first->value, 0, 3);
            return { contact => $contact, transport => $transport };
        }
    }
    return;
}

sub create_peer_registration {
    my ($c, $prov_obj, $type, $prefs) = @_;

    my $sid;
    my $uuid;
    my $username;
    my $domain;

    my $contact = $c->config->{sip}->{lb_ext};
    my $transport = '';

    if ($type eq 'peering') {
        # outbound registration for a peering
        $sid = $prov_obj->{id};
        $uuid = $prov_obj->{uuid};
        $username = $prov_obj->{username};
        $domain = $prov_obj->{domain};
    } elsif ($type eq "subscriber") {
        # outbound registration for usual subscriber
        $sid = $prov_obj->kamailio_subscriber->id;
        $uuid = $prov_obj->uuid;
        $username = $prov_obj->username;
        $domain = $prov_obj->domain->domain;
    } else {
        $c->log->debug("skip creating a registration for undefined type!");
        return 1;
    }

    if($c->config->{features}->{debug}) {
        $c->log->debug("skip creating peer registration for subscriber '".$username.'@'.$domain."'");
        return 1;
    }

    my $all = 1;
    if($c->config->{sems}->{single_host_registration}) {
        $all = 0;
    }

    $c->log->debug("creating peer registration for subscriber '".$username.'@'.$domain."'");

    if ($type eq 'peering') {
        # outbound_sock preference is only available for peerings
        my $outbound_sock = _get_outbound_socket($c, $prefs);

        # if the socket is not default, then a precedence for picking
        # the transport is given to the transport of the outbound socket
        if($outbound_sock) {
            $contact = $outbound_sock->{contact};
            $transport = $outbound_sock->{transport};

        # if the outbound socket is default, then use the transport
        # of the peering's parameters (Protocol: UDP/TCP/TLS)
        } else {
            SWITCH: for ($c->stash->{server_result}->transport) {
                /^2$/ && do {
                    $transport = ';transport=tcp';
                    last SWITCH;
                };
                /^3$/ && do {
                    $transport = ';transport=tls';
                    last SWITCH;
                };
                # default UDP always
                $transport = ';transport=udp';
            }
        }
        $c->log->debug("transport picked for the outbound peering registration is '$transport'");
    }

    # if no specific username defined for the Authorization header
    # use the value of the peer_auth_user instead
    my $authorization_username = $$prefs{peer_auth_hf_user} // $$prefs{peer_auth_user};

    my @ret = NGCP::Panel::Utils::XMLDispatcher::dispatch($c, "appserver", $all, 1, <<EOF);
<?xml version="1.0"?>
  <methodCall>
    <methodName>db_reg_agent.createRegistration</methodName>
    <params>
      <param><value><int>$sid</int></value></param>
      <param><value><string>$$prefs{peer_auth_user}</string></value></param>
      <param><value><string>$$prefs{peer_auth_pass}</string></value></param>
      <param><value><string>$$prefs{peer_auth_realm}</string></value></param>
      <param><value><string>sip:$$prefs{peer_auth_user}\@$contact;uuid=$uuid$transport</string></value></param>
      <param><value><string>$authorization_username</string></value></param>
      <param><value><string>$type</string></value></param>
    </params>
  </methodCall>
EOF

    if (!$all && @ret && $ret[-1][1] == 1 && $ret[-1][2] =~ m#<value>OK</value>#) { # single host okay
        return 1;
    }

    if(grep { $$_[1] == 0 or $$_[2] !~ m#<value>OK</value># } @ret) {  # error
        $c->log->error("Failed XML-RPC call to appserver: ". Dumper \@ret);

        # remove reg from successsful backends
        foreach my $ret (grep {!$$_[1]} @ret) { # successful backends
            NGCP::Panel::Utils::XMLDispatcher::dispatch($c, $$ret[0], 1, 1, <<EOF);
<?xml version="1.0"?>
      <methodCall>
        <methodName>db_reg_agent.removeRegistration</methodName>
        <params>
          <param><value><int>$sid</int></value></param>
        </params>
      </methodCall>
EOF
        }
        die "Failed to add peer registration on application servers\n";
    }
            
    return 1;
}

sub update_peer_registration {
    my ($c, $prov_obj, $type, $prefs, $oldprefs) = @_;

    my $sid;
    my $uuid;
    my $username;
    my $domain;

    my $contact = $c->config->{sip}->{lb_ext};
    my $transport = '';

    if ($type eq 'peering') {
        # outbound registration for a peering
        $sid = $prov_obj->{id};
        $uuid = $prov_obj->{uuid};
        $username = $prov_obj->{username};
        $domain = $prov_obj->{domain};
    } elsif ($type eq "subscriber") {
        # outbound registration for usual subscriber
        $sid = $prov_obj->kamailio_subscriber->id;
        $uuid = $prov_obj->uuid;
        $username = $prov_obj->username;
        $domain = $prov_obj->domain->domain;
    } else {
        $c->log->debug("skip updating a registration for undefined type!");
        return 1;
    }

    if($c->config->{features}->{debug}) {
        $c->log->debug("skip updating peer registration for subscriber '".$username.'@'.$domain."'");
        return 1;
    }

    my $all = 1;
    if($c->config->{sems}->{single_host_registration}) {
        $all = 0;
    }

    $c->log->debug("trying to update peer registration for subscriber '".$username.'@'.$domain."'");

    if ($type eq 'peering') {
        # outbound_sock preference is only available for peerings
        my $outbound_sock = _get_outbound_socket($c, $prefs);

        # if the socket is not default, then a precedence for picking
        # the transport is given to the transport of the outbound socket
        if($outbound_sock) {
            $contact = $outbound_sock->{contact};
            $transport = $outbound_sock->{transport};

        # if the outbound socket is default, then use the transport
        # of the peering's parameters (Protocol: UDP/TCP/TLS)
        } else {
            SWITCH: for ($c->stash->{server_result}->transport) {
                /^2$/ && do {
                    $transport = ';transport=tcp';
                    last SWITCH;
                };
                /^3$/ && do {
                    $transport = ';transport=tls';
                    last SWITCH;
                };
                # default UDP always
                $transport = ';transport=udp';
            }
        }
        $c->log->debug("transport picked for the outbound peering registration is '$transport'");
    }

    use Data::Dumper;
    $c->log->debug("update_peer_registration():");
    $c->log->debug(" old peer auth params: " . Dumper $oldprefs);
    $c->log->debug(" new peer auth params: " . Dumper $prefs);
    $c->log->debug(" sid=$sid");
    $c->log->debug(" uuid=$uuid");
    $c->log->debug(" contact=$contact");

    # if no specific username defined for the Authorization header
    # use the value of the peer_auth_user instead
    my $authorization_username = $$prefs{peer_auth_hf_user} // $$prefs{peer_auth_user};

    my @ret = NGCP::Panel::Utils::XMLDispatcher::dispatch($c, "appserver", $all, 1, <<EOF);
<?xml version="1.0"?>
  <methodCall>
    <methodName>db_reg_agent.updateRegistration</methodName>
    <params>
      <param><value><int>$sid</int></value></param>
      <param><value><string>$$prefs{peer_auth_user}</string></value></param>
      <param><value><string>$$prefs{peer_auth_pass}</string></value></param>
      <param><value><string>$$prefs{peer_auth_realm}</string></value></param>
      <param><value><string>sip:$$prefs{peer_auth_user}\@$contact;uuid=$uuid$transport</string></value></param>
      <param><value><string>$authorization_username</string></value></param>
      <param><value><string>$type</string></value></param>
    </params>
  </methodCall>
EOF

    if (!$all && @ret && $ret[-1][1] == 1 && $ret[-1][2] =~ m#<value>OK</value>#) { # single host okay
        return 1;
    }

    # if no specific username defined for the Authorization header
    # use the value of the peer_auth_user instead
    my $old_authorization_username = $$oldprefs{peer_auth_hf_user} // $$oldprefs{peer_auth_user};

    if(grep { $$_[1] == 0 or $$_[2] !~ m#<value>OK</value># } @ret) {  # error
        $c->log->error("Failed XML-RPC call to appserver: ". Dumper \@ret);

        # undo update on successsful backends
        foreach my $ret (grep {!$$_[1]} @ret) { # successful backends
            NGCP::Panel::Utils::XMLDispatcher::dispatch($c, $$ret[0], 1, 1, <<EOF);
<?xml version="1.0"?>
      <methodCall>
        <methodName>db_reg_agent.updateRegistration</methodName>
        <params>
          <param><value><int>$sid</int></value></param>
          <param><value><string>$$oldprefs{peer_auth_user}</string></value></param>
          <param><value><string>$$oldprefs{peer_auth_pass}</string></value></param>
          <param><value><string>$$oldprefs{peer_auth_realm}</string></value></param>
          <param><value><string>sip:$$oldprefs{peer_auth_user}\@$contact;uuid=$uuid</string></value></param>
          <param><value><string>$old_authorization_username</string></value></param>
          <param><value><string>$type</string></value></param>
        </params>
      </methodCall>
EOF
        }
        die "Failed to update peer registration on application servers\n";
    }
            
    return 1;
}

sub delete_peer_registration {
    my ($c, $prov_obj, $type, $oldprefs) = @_;

    my $sid;
    my $uuid;
    my $username;
    my $domain;

    my $contact = $c->config->{sip}->{lb_ext};

    if ($type eq 'peering') {
        # outbound registration for a peering
        $sid = $prov_obj->{id};
        $uuid = $prov_obj->{uuid};
        $username = $prov_obj->{username};
        $domain = $prov_obj->{domain};
    } elsif ($type eq "subscriber") {
        # outbound registration for usual subscriber
        $sid = $prov_obj->kamailio_subscriber->id;
        $uuid = $prov_obj->uuid;
        $username = $prov_obj->username;
        $domain = $prov_obj->domain->domain;
    } else {
        $c->log->debug("skip deleting a registration for undefined type!");
        return 1;
    }

    if($c->config->{features}->{debug}) {
        $c->log->debug("skip deleting peer registration for subscriber '".$username.'@'.$domain."'");
        return 1;
    }

    my $all = 1;
    if($c->config->{sems}->{single_host_registration}) {
        $all = 0;
    }

    $c->log->debug("trying to delete peer registration for subscriber '".$username.'@'.$domain."'");

    my @ret = NGCP::Panel::Utils::XMLDispatcher::dispatch($c, "appserver", $all, 1, <<EOF);
<?xml version="1.0"?>
      <methodCall>
        <methodName>db_reg_agent.removeRegistration</methodName>
        <params>
          <param><value><int>$sid</int></value></param>
          <param><value><string>$type</string></value></param>
        </params>
      </methodCall>
EOF

    if (!$all && @ret && $ret[-1][1] == 1 && $ret[-1][2] =~ m#<value>OK</value>#) { # single host okay
        return 1;
    }

    # if no specific username defined for the Authorization header
    # use the value of the peer_auth_user instead
    my $old_authorization_username = $$oldprefs{peer_auth_hf_user} // $$oldprefs{peer_auth_user};

    if(grep { $$_[1] == 0 or $$_[2] !~ m#<value>OK</value># } @ret) {  # error
        $c->log->error("Failed XML-RPC call to appserver: ". Dumper \@ret);

        # remove reg from successsful backends
        foreach my $ret (grep {!$$_[1]} @ret) { # successful backends
            NGCP::Panel::Utils::XMLDispatcher::dispatch($c, $ret[0], 1, 1, <<EOF);
<?xml version="1.0"?>
  <methodCall>
    <methodName>db_reg_agent.createRegistration</methodName>
    <params>
      <param><value><int>$sid</int></value></param>
      <param><value><string>$$oldprefs{peer_auth_user}</string></value></param>
      <param><value><string>$$oldprefs{peer_auth_pass}</string></value></param>
      <param><value><string>$$oldprefs{peer_auth_realm}</string></value></param>
      <param><value><string>sip:$$oldprefs{peer_auth_user}\@$contact;uuid=$uuid</string></value></param>
      <param><value><string>$old_authorization_username</string></value></param>
      <param><value><string>$type</string></value></param>
    </params>
  </methodCall>
EOF

        }
        die "Failed to delete peer registration on application servers\n";
    }
            
    return 1;
}

sub clear_audio_cache {
    my ($c, $sound_set_id, $handle_name, $group_name) = @_;

    my @pbx = $c->config->{features}->{cloudpbx} ? ('pbx') : ();
    my @services;
    if ($group_name eq "pbx" )  {
        @services = (@pbx);
    } elsif ($group_name =~ /^(music_on_hold|digits|custom_announcements)$/) {
        @services = (@pbx, "appserver");
    } elsif ($group_name =~ /^(malicious_call_identification|voucher_recharge|play_balance|conference|calling_card)$/) {
        @services = ("appserver");
    }

    for my $service (@services) {
        _clear_audio_cache_service($c, $service, $sound_set_id, $handle_name);
    }
    return;
}

sub _clear_audio_cache_service {
    my ($c, $service, $sound_set_id, $handle_name) = @_;

    my @ret = NGCP::Panel::Utils::XMLDispatcher::dispatch($c, $service, 1, 1, <<EOF );
<?xml version="1.0"?>
  <methodCall>
    <methodName>postDSMEvent</methodName>
    <params>
      <param>
        <value><string>sw_audio</string></value>
      </param>
      <param>
        <value><array><data>
          <value><array><data>
            <value><string>cmd</string></value>
            <value><string>clearFile</string></value>
          </data></array></value>
          <value><array><data>
          <value><string>audio_id</string></value>
            <value><string>$handle_name</string></value>
         </data></array></value>
         <value><array><data>
           <value><string>sound_set_id</string></value>
           <value><string>$sound_set_id</string></value>
         </data></array></value>
       </data></array></value>
     </param>
   </params>
  </methodCall>
EOF

    if(grep { $$_[1] == 0 or $$_[2] !~ m#<value>OK</value># } @ret) {  # error
        die "failed to clear SEMS audio cache";
    }

    return 1;
}

sub dial_out {
    my ($c, $prov_subscriber, $callee_user, $callee_domain) = @_; 
    # TODO: what about announcement
    my $announcement = 'test.wav';

    my $proxy_rs = $c->model('DB')->resultset('xmlhosts')->search({
        'group.name' => 'proxy',
    },{
        join => { xmlhostgroups => 'group' },
        order_by => \'rand()',
    });
    my $proxy = $proxy_rs->first;
    unless($proxy) {
        die "failed to fetch proxy for dial-out, none available";
    }
    my $proxyuri = $proxy->ip . ':' . $proxy->sip_port;

    my $caller_username = $prov_subscriber->username;
    my $caller_domain = $prov_subscriber->domain->domain;
    my $caller_password = $prov_subscriber->password;
    my $click2dial;
    if ($c->config->{click2dial}->{version} == 1) {
      $click2dial = 'click2dial';
    }
    elsif ($c->config->{click2dial}->{version} == 2) {
      $click2dial = 'click2dial2';
    }

    my $ret = NGCP::Panel::Utils::XMLDispatcher::dispatch($c, "appserver", 0, 1, <<EOF );
<?xml version="1.0"?>
<methodCall>
  <methodName>dial_auth_b2b</methodName>
  <params>
    <param><value><string>$click2dial</string></value></param>
    <param><value><string>$announcement</string></value></param>
    <param><value><string>sip:$caller_username\@$caller_domain</string></value></param>
    <param><value><string>sip:$callee_user\@$callee_domain</string></value></param>
    <param><value><string>sip:$caller_username\@$proxyuri;sw_domain=$caller_domain</string></value></param>
    <param><value><string>sip:$callee_user\@$proxyuri;sw_domain=$callee_domain</string></value></param>
    <param><value><string>$caller_domain</string></value></param>
    <param><value><string>$caller_username</string></value></param>
    <param><value><string>$caller_password</string></value></param>
  </params>
</methodCall>
EOF

    use Data::Dumper;
    $c->log->info("received from dispatcher: " . Dumper $ret);
    if(!$ret || $ret->[1] != 1 || $ret->[2] =~ m#<name>faultString</name>#) {
        die "failed to trigger dial-out";
    }
    return 1;
}

sub party_call_control {
    my ($c, $data) = @_;

    foreach my $param (qw(caller callee callid status token)) {
        die "missing '$param' parameter'" unless $data->{$param};
    }

    my ($caller, $callee, $callid, $status, $token) =
        @{$data}{qw(caller callee callid status token)};

    my $service = 'appserver';

    my @ret = NGCP::Panel::Utils::XMLDispatcher::dispatch($c, $service, 1, 1, <<EOF );
<?xml version="1.0"?>
  <methodCall>
    <methodName>postDSMEvent</methodName>
    <params>
      <param>
        <value><string>$token</string></value>
      </param>
      <param>
        <value><array><data>
          <value><array><data>
            <value><string>cmd</string></value>
            <value><string>handleCall</string></value>
          </data></array></value>
          <value><array><data>
            <value><string>callid</string></value>
            <value><string>$callid</string></value>
          </data></array></value>
          <value><array><data>
            <value><string>caller</string></value>
            <value><string>$caller</string></value>
          </data></array></value>
          <value><array><data>
            <value><string>callee</string></value>
            <value><string>$callee</string></value>
          </data></array></value>
          <value><array><data>
            <value><string>status</string></value>
            <value><string>$status</string></value>
          </data></array></value>
        </data></array></value>
      </param>
    </params>
  </methodCall>
EOF

    if(grep { $$_[1] == 0 or $$_[2] !~ m#<value>OK</value># } @ret) {
        die "failed to handle party call control request";
    }

    return 1;
}

1;

# vim: set tabstop=4 expandtab:
