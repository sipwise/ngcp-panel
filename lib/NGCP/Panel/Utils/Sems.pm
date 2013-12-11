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

    my @ret = $dispatcher->dispatch("appserver", 1, 1, <<EOF);
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
            $dispatcher->dispatch($$ret[0], 1, 1, <<EOF);
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

    my @ret = $dispatcher->dispatch("appserver", 1, 1, <<EOF);
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
            $dispatcher->dispatch($$ret[0], 1, 1, <<EOF);
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

    my @ret = $dispatcher->dispatch("appserver", 1, 1, <<EOF);
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
            $dispatcher->dispatch($ret[0], 1, 1, <<EOF);
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

1;

# vim: set tabstop=4 expandtab:
