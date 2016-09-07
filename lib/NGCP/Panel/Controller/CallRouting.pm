package NGCP::Panel::Controller::CallRouting;
use NGCP::Panel::Utils::Generic qw(:all);
use Sipwise::Base;

use parent 'Catalyst::Controller';

use NGCP::Panel::Form::CallRouting::Verify;
use NGCP::Panel::Utils::Navigation;
use NGCP::Panel::Utils::Subscriber;
use NGCP::Panel::Utils::Peering;

use Sys::Hostname;

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub root :PathPart('/') :CaptureArgs(0) {
    my ( $self, $c ) = @_;
}

sub callroutingverify :Chained('/') :PathPart('callroutingverify') :Args(0) {
    my ( $self, $c ) = @_;

    my $form = NGCP::Panel::Form::CallRouting::Verify->new(ctx => $c);
    my $params = merge({}, $c->session->{created_objects});
    my $posted = ($c->req->method eq 'POST');
    my $data = $c->req->params;
    my @log;

    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params,
    );

    unless ($posted && $form->validated) {
        $c->stash(
            template => 'callrouting/verify.tt',
            form => $form,
        );
        return;
    }

    # TODO: relocate the logic to a common module that can be centralised and
    # reused by other components

    # caller/callee general parsing
    # remove leading/trailing spaces
    foreach my $type (qw(caller callee)) {
        $data->{$type} =~ s/(^\s+|\s+$)//g;
        $data->{$type} =~ s/^sip://;
    }

    # caller lookup
    if ($data->{caller_subscriber_id}) {
        my $rs = $c->model('DB')->resultset('voip_subscribers')->search({
                id => $data->{caller_subscriber_id},
        });
        unless ($rs->first) {
            push @log, sprintf "no caller subscriber found with id %d",
                $data->{caller_subscriber_id};
            goto RESULT;
        }
        $data->{caller_subscriber} = $rs->first;
    } elsif ($data->{caller_peer_id}) {
        my $rs = $c->model('DB')->resultset('voip_peer_groups')->search({
                id => $data->{caller_peer_id},
        });
        unless ($rs->first) {
            push @log, sprintf "no caller peer found with id %d",
                $data->{caller_peer_id};
            goto RESULT;
        }
        $data->{caller_peer} = $rs->first;

        unless ($data->{caller_peer}->voip_peer_hosts->first) {
            push @log, sprintf "caller peer with id %d does not contain any peer hosts",
                $rs->id;
        }
        $data->{caller_peer_host} = $data->{caller_peer}->voip_peer_hosts->first;
    } else {
        push @log, sprintf "no caller subscriber/peer was specified, using subscriber lookup based on caller %s",
            $data->{caller};
        $data->{caller_subscriber} =
            NGCP::Panel::Utils::Subscriber::lookup(
                                    c => $c,
                                    lookup => $data->{caller},
                                 );
        if ($data->{caller_subscriber}) {
            $data->{caller_subscriber_id} = $data->{caller_subscriber}->id;
            my $sub = sprintf '%s@%s',
                        $data->{caller_subscriber}->username,
                        $data->{caller_subscriber}->domain->domain;
            push @log, sprintf "found caller subscriber '%s' with id %d",
                        $sub, $data->{caller_subscriber_id};
        } else {
            push @log, sprintf "no caller subscriber found.";
            goto RESULT;

        }
    }

    # caller sum up
    push @log, sprintf "call from %s", $data->{caller};
    $log[-1] .= $data->{caller_subscriber}
                    ? sprintf " using subscriber '%s\@%s' id %s",
                        $data->{caller_subscriber}->username,
                        $data->{caller_subscriber}->domain->domain,
                        $data->{caller_subscriber}->id
                    : sprintf " using peer '%s' id %s",
                        $data->{caller_peer}->name,
                        $data->{caller_peer}->id;
    if ($data->{caller_peer_host}) {
        $log[-1] .= sprintf " and peer host %s (ip: %s) with id %d",
                        $data->{caller_peer_host}->name,
                        $data->{caller_peer_host}->ip,
                        $data->{caller_peer_host}->id;
    }

    # subscriber allowed_cli checks
    if ($data->{caller_subscriber}) {
        my %usr_prefs;
        foreach my $pref (qw(allowed_clis allowed_clis_reject_policy cli user_cli)) {
            my $rs = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                c => $c, attribute => $pref,
                prov_subscriber =>
                    $data->{caller_subscriber}->provisioning_voip_subscriber,
            );
            if ($rs->first) {
                @{$usr_prefs{$pref}} = map { $_->value } $rs->all;
            } else {
                $rs = NGCP::Panel::Utils::Preferences::get_dom_preference_rs(
                    c => $c, attribute => $pref,
                    prov_domain =>
                        $data->{caller_subscriber}->provisioning_voip_subscriber->domain,
                );
                if ($rs->first) {
                    @{$usr_prefs{$pref}} = map { $_->value } $rs->all;
                }
            }
        }
        my $match = map { $_ =~ s/\*/.*/g;
                          $data->{caller} =~ /^$_$/;
                        } @{$usr_prefs{allowed_clis}};
        if ($match) {
            push @log, sprintf
                "caller %s is accepted as it matches subscriber's 'allowed_clis'",
                    $data->{caller};
        } else {
            push @log, sprintf
                "caller %s is rejected as it does not match subscriber's 'allowed_clis'",
                    $data->{caller};
            if (defined $usr_prefs{allowed_clis_reject_policy}) {
                SWITCH: for ($usr_prefs{allowed_clis_reject_policy}[0]) {
                    /^override_by_clir$/ && do {
                        push @log,
                            "'allowed_cli' reject policy is 'override_by_clir', anonymising caller";
                        $data->{caller} = 'anonymous';
                        last SWITCH;
                    };
                    /^override_by_usernpn$/ && do {
                        push @log,
                            "'allowed_cli' reject policy is 'override_by_usernpn'";
                        foreach my $cli (qw(user_cli cli)) {
                            if (defined $usr_prefs{$cli}) {
                                $data->{caller} = $usr_prefs{$cli}[0];
                                $log[-1] .= sprintf ", taken from '$cli' %s",
                                    $usr_prefs{$cli}[0];
                                last;
                            }
                        }
                        last SWITCH;
                    };
                    /^reject$/ && do {
                        push @log,
                            "'allowed_cli' reject policy is 'reject', terminating the call";
                        goto RESULT;
                        last SWITCH;
                    };
                }
            }
        }
    }

    # caller inbound rewrite rules lookup
    if ($data->{caller_rewrite_id}) {
        my $rs = $c->model('DB')->resultset('voip_rewrite_rule_sets')->search({
            id => $data->{caller_rewrite_id},
        });
        if ($rs->first) {
            push @log, sprintf "using caller rewrite rule set '%s' with id %d",
                $rs->first->name, $rs->first->id;
            $data->{caller_rewrite} = $rs->first;
        }
    } else {
        my ($lookup_rws, $lookup_rws_type, $rws_rs);
        if ($data->{'caller_subscriber_id'}) {
            my $rs = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                c => $c, attribute => "rewrite_caller_in_dpid",
                prov_subscriber =>
                    $data->{caller_subscriber}->provisioning_voip_subscriber,
            );
            if ($rs->first) {
                $rws_rs = $c->model('DB')->resultset('voip_rewrite_rule_sets')->search({
                    caller_in_dpid => $rs->first->value
                });
            }
            if ($rws_rs && $rws_rs->first) {
                $lookup_rws = $rws_rs->first;
                $lookup_rws_type = 'subscriber';
            } else {
                $rs = NGCP::Panel::Utils::Preferences::get_dom_preference_rs(
                    c => $c, attribute => "rewrite_caller_in_dpid",
                    prov_domain =>
                        $data->{caller_subscriber}->provisioning_voip_subscriber->domain,
                );
                if ($rs->first) {
                    $rws_rs = $c->model('DB')->resultset('voip_rewrite_rule_sets')->search({
                        caller_in_dpid => $rs->first->value
                    });
                }
                if ($rws_rs && $rws_rs->first) {
                    $lookup_rws = $rws_rs->first;
                    $lookup_rws_type = 'domain';
                } else {
                    push @log, sprintf "no caller subscriber/domain rewrite rule sets were found";
                }
            }
        } elsif ($data->{caller_peer_id}) {
            my $rs = NGCP::Panel::Utils::Preferences::get_peer_preference_rs(
                c => $c, attribute => "rewrite_caller_in_dpid",
                peer_host => $data->{caller_peer_host},
            );
            if ($rs->first) {
                $rws_rs = $c->model('DB')->resultset('voip_rewrite_rule_sets')->search({
                    caller_in_dpid => $rs->first->value
                });
            }
            if ($rws_rs && $rws_rs->first) {
                $lookup_rws = $rws_rs->first;
                $lookup_rws_type = 'peer';
            } else {
                push @log, sprintf "no caller peer rewrite rule sets with were found";
            }
        }

        if ($lookup_rws) {
            push @log, sprintf "using caller %s inbound rewrite rule set '%s' with id %d",
                $lookup_rws_type, $lookup_rws->name, $lookup_rws->id;
            $data->{caller_rewrite} = $lookup_rws;
        }
    }

    # apply inbound rewrite rules
    foreach my $type (qw(caller callee)) {
        $data->{$type.'_in'} = $data->{$type};
        next unless $data->{caller_rewrite};
        my $new;
        if ($data->{caller_subscriber_id}) {
            $new =
                NGCP::Panel::Utils::Subscriber::apply_rewrite(
                    c => $c, subscriber => $data->{caller_subscriber},
                    direction => $type.'_in',
                    number => $data->{$type},
                    rws_id => $data->{caller_rewrite}->id,
                );
        } elsif ($data->{caller_peer_id}) {
            $new =
                NGCP::Panel::Utils::Peering::apply_rewrite(
                    c => $c, peer_host => $data->{caller_peer_host},
                    direction => $type.'_in',
                    number => $data->{$type},
                    rws_id => $data->{caller_rewrite}->id,
                );
        }
        if ($new && $new ne $data->{$type}) {
            push @log, sprintf "%s %s is rewritten based on the inbound rules into %s",
                $type, $data->{$type}, $new;
        }
        $data->{$type.'_in'} = $new || $data->{$type};
    }

    # callee lookup
    if ($data->{callee_peer_id}) {
        my $rs = $c->model('DB')->resultset('voip_peer_groups')->search({
                id => $data->{callee_peer_id},
        });
        unless ($rs->first) {
            push @log, sprintf "no callee peer found with id %d",
                $data->{callee_peer_id};
            goto RESULT;
        }
        $data->{callee_peer} = $rs->first;

        unless ($data->{callee_peer}->voip_peer_hosts->first) {
            push @log, sprintf "callee peer with id %d does not contain any peer hosts",
                $rs->id;
        }
        $data->{callee_peer_host} = $data->{callee_peer}->voip_peer_hosts->first;
    } else {
        push @log, sprintf "callee subscriber lookup based on %s",
            $data->{callee};
        $data->{callee_subscriber} =
            NGCP::Panel::Utils::Subscriber::lookup(
                                    c => $c,
                                    lookup => $data->{callee},
                                 );
        if ($data->{callee_subscriber}) {
            $data->{callee_subscriber_id} = $data->{callee_subscriber}->id;
            my $sub = sprintf '%s@%s',
                        $data->{callee_subscriber}->username,
                        $data->{callee_subscriber}->domain->domain;
            push @log, sprintf "found callee subscriber '%s' with id %d",
                        $sub, $data->{callee_subscriber_id};
        } else {
            push @log,
                sprintf "no callee subscriber found, performing a peer lookup with caller %s and callee %s",
                    @{$data}{qw(caller_in callee_in)};
            $data->{callee_peers} =
                NGCP::Panel::Utils::Peering::lookup(
                                        c => $c,
                                        caller => $data->{caller_in},
                                        callee => $data->{callee_in},
                                    );
            unless ($data->{callee_peers} && scalar @{$data->{callee_peers}}) {
                push @log, sprintf "no callee peers found";
                goto RESULT;
            }
            # as we cannot check peer reply codes here, use first peer for now
            $data->{callee_peer} = $data->{callee_peers}->[0];
            $data->{callee_peer_id} = $data->{callee_peer}->id;

            push @log, sprintf "matched peer '%s' with id %d",
                    $data->{callee_peer}->name, $data->{callee_peer}->id;

            unless ($data->{callee_peer}->voip_peer_hosts->first) {
                push @log, sprintf "callee peer with id %d does not contain any peer hosts",
                    $data->{callee_peer}->id;
            }
            $data->{callee_peer_host} = $data->{callee_peer}->voip_peer_hosts->first;
        }
    }

    # callee sum up
    push @log, sprintf "call to %s", $data->{callee};
    if ($data->{callee_subscriber}) {
        $log[-1] .= $data->{callee_subscriber}
                        ? sprintf ", subscriber '%s\@%s' with id %d",
                            $data->{callee_subscriber}->username,
                            $data->{callee_subscriber}->domain->domain,
                            $data->{callee_subscriber}->id
                        : sprintf ", peer %s id %s",
                            $data->{callee_peer}->name,
                            $data->{callee_peer}->id;
    } elsif ($data->{callee_peer_host}) {
        $log[-1] .= sprintf " and peer host '%s' (ip: %s) with id %d",
                        $data->{callee_peer_host}->name,
                        $data->{callee_peer_host}->ip,
                        $data->{callee_peer_host}->id;
    } else {
        push @log, "this call does not have any termination point";
    }

    # callee outbound rewrite rules lookup
    if ($data->{callee_rewrite_id}) {
        my $rs = $c->model('DB')->resultset('voip_rewrite_rule_sets')->search({
            id => $data->{callee_rewrite_id},
        });
        if ($rs->first) {
            push @log, sprintf "using callee rewrite rule set '%s' with id %d",
                $rs->first->name, $rs->first->id;
            $data->{callee_rewrite} = $rs->first;
        }
    } else {
        my ($lookup_rws, $lookup_rws_type, $rws_rs);
        if ($data->{'callee_subscriber_id'}) {
            my $rs = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                c => $c, attribute => "rewrite_callee_out_dpid",
                prov_subscriber =>
                    $data->{callee_subscriber}->provisioning_voip_subscriber,
            );
            if ($rs->first) {
                $rws_rs = $c->model('DB')->resultset('voip_rewrite_rule_sets')->search({
                    callee_out_dpid => $rs->first->value
                });
            }
            if ($rws_rs && $rws_rs->first) {
                $lookup_rws = $rws_rs->first;
                $lookup_rws_type = 'subscriber';
            } else {
                $rs = NGCP::Panel::Utils::Preferences::get_dom_preference_rs(
                    c => $c, attribute => "rewrite_callee_out_dpid",
                    prov_domain =>
                        $data->{callee_subscriber}->provisioning_voip_subscriber->domain,
                );
                if ($rs->first) {
                    $rws_rs = $c->model('DB')->resultset('voip_rewrite_rule_sets')->search({
                        callee_out_dpid => $rs->first->value
                    });
                }
                if ($rws_rs && $rws_rs->first) {
                    $lookup_rws = $rws_rs->first;
                    $lookup_rws_type = 'domain';
                } else {
                    push @log, sprintf "no callee subscriber/domain rewrite rule sets were found";
                }
            }
        } elsif ($data->{callee_peer_id}) {
            my $rs = NGCP::Panel::Utils::Preferences::get_peer_preference_rs(
                c => $c, attribute => "rewrite_callee_out_dpid",
                peer_host => $data->{callee_peer_host},
            );
            if ($rs->first) {
                $rws_rs = $c->model('DB')->resultset('voip_rewrite_rule_sets')->search({
                    callee_out_dpid => $rs->first->value
                });
            }
            if ($rws_rs && $rws_rs->first) {
                $lookup_rws = $rws_rs->first;
                $lookup_rws_type = 'peer';
            } else {
                push @log, sprintf "no callee peer rewrite rule sets with were found";
            }
        }

        if ($lookup_rws) {
            push @log, sprintf "using callee %s outbound rewrite rule set '%s' with id %d",
                $lookup_rws_type, $lookup_rws->name, $lookup_rws->id;
            $data->{callee_rewrite} = $lookup_rws;
        }
    }

    # apply outbound rewrite rules
    foreach my $type (qw(caller callee)) {
        $data->{$type.'_out'} = $data->{$type};
        next unless $data->{callee_rewrite};
        my $new;
        if ($data->{callee_subscriber_id}) {
            $new =
                NGCP::Panel::Utils::Subscriber::apply_rewrite(
                    c => $c, subscriber => $data->{callee_subscriber},
                    direction => $type.'_out',
                    number => $data->{$type.'_in'},
                    rws_id => $data->{callee_rewrite}->id,
                );
        } elsif ($data->{callee_peer_id}) {
            $new =
                NGCP::Panel::Utils::Peering::apply_rewrite(
                    c => $c, peer_host => $data->{callee_peer_host},
                    direction => $type.'_out',
                    number => $data->{$type.'_in'},
                    rws_id => $data->{callee_rewrite}->id,
                );
        }
        if ($new && $new ne $data->{$type.'_in'}) {
            push @log, sprintf "%s %s is rewritten based on the outbound rules into %s",
                $type, $data->{$type.'_in'}, $new;
        }
        $data->{$type.'_out'} = $new || $data->{$type.'_in'};
    }


RESULT:
    foreach my $type (qw(caller callee)) {
        $data->{$type.'_type'} =
            $data->{$type.'_subscriber'}
                ? 'subscriber'
                : $data->{$type.'_peer'} ? 'peer' : 'unknown';
        #foreach my $dir (qw(in out)) {
            #$data->{$type.'_'.$dir} ||= $data->{$type.'_type'} ne 'unknown'
            #                                ? $data->{$type}
            #                                : '';
            # fill in a value even if caller/callee is not identified
        #}
    }

    $c->stash(
        template => 'callrouting/result.tt',
        close_target => '/callroutingverify',
        caller => $data->{caller},
        callee => $data->{callee},
        caller_in => $data->{caller_in},
        callee_in => $data->{callee_in},
        caller_out => $data->{caller_out},
        callee_out => $data->{callee_out},
        caller_type => $data->{caller_type},
        callee_type => $data->{callee_type},
        log => \@log,
        form => undef,
    );

    return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 AUTHOR

Kirill Solomko <ksolomko@sipwise.com>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
