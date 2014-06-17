package NGCP::Panel::Utils::Sems;

use Sipwise::Base;
use NGCP::Panel::Utils::XMLDispatcher;
use Data::Dumper;

sub create_peer_registration {
    my ($c, $prov_subscriber, $prefs) = @_;

    if($c->config->{features}->{debug}) {
        $c->log->debug("skip creating peer registration for subscriber '".$prov_subscriber->username.'@'.$prov_subscriber->domain->domain."'");
        return 1;
    }

    my $dispatcher = NGCP::Panel::Utils::XMLDispatcher->new;

    $c->log->debug("creating peer registration for subscriber '".$prov_subscriber->username.'@'.$prov_subscriber->domain->domain."'");

    my $sid = $prov_subscriber->id;
    my $uuid = $prov_subscriber->uuid;
    my $contact = $c->config->{sip}->{lb_ext};

    my @ret = $dispatcher->dispatch($c, "appserver", 1, 1, <<EOF);
<?xml version="1.0"?>
  <methodCall>
    <methodName>db_reg_agent.createRegistration</methodName>
    <params>
      <param><value><int>$sid</int></value></param>
      <param><value><string>$$prefs{peer_auth_user}</string></value></param>
      <param><value><string>$$prefs{peer_auth_pass}</string></value></param>
      <param><value><string>$$prefs{peer_auth_realm}</string></value></param>
      <param><value><string>sip:$$prefs{peer_auth_user}\@$contact;uuid=$uuid</string></value></param>
    </params>
  </methodCall>
EOF

    if(grep { $$_[1] != 1 or $$_[2] !~ m#<value>OK</value># } @ret) {  # error
        $c->log->error("Failed XML-RPC call to appserver: ". Dumper \@ret);

        # remove reg from successsful backends
        foreach my $ret (grep {!$$_[1]} @ret) { # successful backends
            $dispatcher->dispatch($c, $$ret[0], 1, 1, <<EOF);
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
    my ($c, $prov_subscriber, $prefs, $oldprefs) = @_;

    if($c->config->{features}->{debug}) {
        $c->log->debug("skip updating peer registration for subscriber '".$prov_subscriber->username.'@'.$prov_subscriber->domain->domain."'");
        return 1;
    }

    my $dispatcher = NGCP::Panel::Utils::XMLDispatcher->new;

    $c->log->debug("trying to update peer registration for subscriber '".$prov_subscriber->username.'@'.$prov_subscriber->domain->domain."'");

    my $sid = $prov_subscriber->id;
    my $uuid = $prov_subscriber->uuid;
    my $contact = $c->config->{sip}->{lb_ext};

    use Data::Dumper;
    $c->log->debug("+++++++++++++++++++ old peer auth params: " . Dumper $oldprefs);
    $c->log->debug("+++++++++++++++++++ new peer auth params: " . Dumper $prefs);
    $c->log->debug("+++++++++++++++++++ sid=$sid");
    $c->log->debug("+++++++++++++++++++ uuid=$uuid");
    $c->log->debug("+++++++++++++++++++ contact=$contact");

    my @ret = $dispatcher->dispatch($c, "appserver", 1, 1, <<EOF);
<?xml version="1.0"?>
  <methodCall>
    <methodName>db_reg_agent.updateRegistration</methodName>
    <params>
      <param><value><int>$sid</int></value></param>
      <param><value><string>$$prefs{peer_auth_user}</string></value></param>
      <param><value><string>$$prefs{peer_auth_pass}</string></value></param>
      <param><value><string>$$prefs{peer_auth_realm}</string></value></param>
      <param><value><string>sip:$$prefs{peer_auth_user}\@$contact;uuid=$uuid</string></value></param>
    </params>
  </methodCall>
EOF

    if(grep { $$_[1] != 1 or $$_[2] !~ m#<value>OK</value># } @ret) {  # error
        $c->log->error("Failed XML-RPC call to appserver: ". Dumper \@ret);

        # undo update on successsful backends
        foreach my $ret (grep {!$$_[1]} @ret) { # successful backends
            $dispatcher->dispatch($c, $$ret[0], 1, 1, <<EOF);
<?xml version="1.0"?>
      <methodCall>
        <methodName>db_reg_agent.updateRegistration</methodName>
        <params>
          <param><value><int>$sid</int></value></param>
          <param><value><string>$$oldprefs{peer_auth_user}</string></value></param>
          <param><value><string>$$oldprefs{peer_auth_pass}</string></value></param>
          <param><value><string>$$oldprefs{peer_auth_realm}</string></value></param>
          <param><value><string>sip:$$oldprefs{peer_auth_user}\@$contact;uuid=$uuid</string></value></param>
        </params>
      </methodCall>
EOF
        }
        die "Failed to update peer registration on application servers\n";
    }
            
    return 1;
}

sub delete_peer_registration {
    my ($c, $prov_subscriber, $oldprefs) = @_;

    if($c->config->{features}->{debug}) {
        $c->log->debug("skip deleting peer registration for subscriber '".$prov_subscriber->username.'@'.$prov_subscriber->domain->domain."'");
        return 1;
    }

    my $dispatcher = NGCP::Panel::Utils::XMLDispatcher->new;

    $c->log->debug("trying to delete peer registration for subscriber '".$prov_subscriber->username.'@'.$prov_subscriber->domain->domain."'");

    my $sid = $prov_subscriber->id;
    my $uuid = $prov_subscriber->uuid;
    my $contact = $c->config->{sip}->{lb_ext};

    my @ret = $dispatcher->dispatch($c, "appserver", 1, 1, <<EOF);
<?xml version="1.0"?>
      <methodCall>
        <methodName>db_reg_agent.removeRegistration</methodName>
        <params>
          <param><value><int>$sid</int></value></param>
        </params>
      </methodCall>
EOF

    if(grep { $$_[1] != 1 or $$_[2] !~ m#<value>OK</value># } @ret) {  # error
        $c->log->error("Failed XML-RPC call to appserver: ". Dumper \@ret);

        # remove reg from successsful backends
        foreach my $ret (grep {!$$_[1]} @ret) { # successful backends
            $dispatcher->dispatch($c, $ret[0], 1, 1, <<EOF);
<?xml version="1.0"?>
  <methodCall>
    <methodName>db_reg_agent.createRegistration</methodName>
    <params>
      <param><value><int>$sid</int></value></param>
      <param><value><string>$$oldprefs{peer_auth_user}</string></value></param>
      <param><value><string>$$oldprefs{peer_auth_pass}</string></value></param>
      <param><value><string>$$oldprefs{peer_auth_realm}</string></value></param>
      <param><value><string>sip:$$oldprefs{peer_auth_user}\@$contact;uuid=$uuid</string></value></param>
    </params>
  </methodCall>
EOF

        }
        die "Failed to delete peer registration on application servers\n";
    }
            
    return 1;
}

sub clear_audio_cache {
    my ($c, $service, $sound_set_id, $handle_name) = @_;

    my $dispatcher = NGCP::Panel::Utils::XMLDispatcher->new;

    my @ret = $dispatcher->dispatch($c, $service, 1, 1, <<EOF );
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

    if(grep { $$_[1] != 1 or $$_[2] !~ m#<value>OK</value># } @ret) {  # error
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

    my $dispatcher = NGCP::Panel::Utils::XMLDispatcher->new;
    my $ret = $dispatcher->dispatch($c, "appserver", 0, 1, <<EOF );
<?xml version="1.0"?>
<methodCall>
  <methodName>dial_auth_b2b</methodName>
  <params>
    <param><value><string>click2dial</string></value></param>
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
    if(!$ret or $ret->[1] != 1 or $ret->[2] =~ m#<name>faultString</name>#) {
        die "failed to trigger dial-out";
    }
    return 1;
}

1;

# vim: set tabstop=4 expandtab:
