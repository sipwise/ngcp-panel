package NGCP::Panel::Utils::Fax;

use warnings;
use strict;

use English;
use File::Temp qw/tempfile/;
use File::Slurp;
use TryCatch;
use IPC::System::Simple qw/capture/;
use Data::Dumper;
use Net::Ping;
use URI::Escape qw(uri_unescape);

sub send_fax {
    my (%args) = @_;
    my $c = $args{c};

    #moved here due to CE, as it doesn't carry NGCP::fax
    eval { require NGCP::Fax; };
    if ($@) {
        if ($@ =~ m#Can't locate NGCP/Fax.pm#) {
            $c->log->debug("Fax features are not supported in the Community Edition");
            return;
        } else {
            die $@;
        }
    }
    my $subscriber = $args{subscriber};
    my $prov_subscriber = $subscriber->provisioning_voip_subscriber;

    my %sendfax_args = ();

    if ($c->config->{faxserver}{hosts}) {
        my @hosts = split(/,\s*/, $c->config->{faxserver}{hosts});
        my $port = $c->config->{faxserver}{port};
        $c->log->debug("faxserver port $port hosts: " . join(',',@hosts));
        my $ping = new Net::Ping('tcp', 1);
        $ping->port_number($port);
        do {
            my $host = $hosts[rand @hosts];
            $c->log->debug("pinging $host:$port");
            if ($ping->ping($host)) {
                $sendfax_args{host} = $host;
                $sendfax_args{port} = $port;
            }
            @hosts = grep { $_ ne $host } @hosts;
        } while (!$sendfax_args{host} && @hosts);
        die "No alive proxy hosts to queue the send fax to"
            unless $sendfax_args{host} && $sendfax_args{port};
    }

    my $sender = 'webfax';
    my $number;
    if($subscriber->primary_number) {
        $number = $subscriber->primary_number->cc .
            ($subscriber->primary_number->ac // '').
            $subscriber->primary_number->sn;
    } else {
        $number = $sender;
    }
    {
        my ($user, $domain) = split(/\@/, $args{destination});
        $user =~ s/^sips?://;
        $user = uri_unescape(NGCP::Panel::Utils::Subscriber::apply_rewrite(
            c => $c, subscriber => $subscriber, number => $user, direction => 'callee_in'
        ));

        if ($user) {
            if($domain && $domain ne $subscriber->domain->domain) {
                $user = $user . '@' . $domain;
            }
            $c->log->debug('number normalization: caller_in apply_rewrite result for '.$args{destination}.', billing subscriber id '.$subscriber->id.': user='.$user.'.');

            $args{destination} = $user;

        } else {
            $c->log->debug('number normalization: caller_in apply_rewrite result is empty for '.$args{destination}.', billing subscriber id '.$subscriber->id.'.');    
        }
    }

    $sendfax_args{caller} = $number;
    $sendfax_args{callee} = $args{destination};

    if($args{quality}) {#low|medium|extended
        $sendfax_args{quality} = $args{quality};
    }
    if($args{pageheader}) {
        $sendfax_args{header} = $args{pageheader};
    }

    $sendfax_args{files} = [];
    if($args{upload}){
        push @{$sendfax_args{files}}, eval { $args{upload}->tempname };
        $c->log->debug('error to retrieve tempfile of upload: ' . @_) if @_;
    }
    if($args{data}){
        $sendfax_args{input} = [\$args{data}];
    }
    my $client = new NGCP::Fax;
    use Data::Dumper;
    $c->log->debug('invoke send_fax with args: ' . Dumper(\%sendfax_args));
    my $res = $client->send_fax(\%sendfax_args);
    $c->log->debug("webfax: res=$res;");
}

sub get_fax {
    my (%args) = @_;
    my $c = $args{c};
    # mandatory is $item or $filename
    # $item - get a stored fax from the db
    # $filename - get a stored fax from the spool

    #moved here due to CE, as it doesn't carry NGCP::fax
    eval { require NGCP::Fax; };
    if ($@) {
        if ($@ =~ m#Can't locate NGCP/Fax.pm#) {
            $c->log->debug("Fax features are not supported in the Community Edition");
            return;
        } else {
            die $@;
        }
    }

    my $filepath;
    my $content;
    my $ext = 'tif';

    my ($filename, $format, $item) = @{args}{qw(filename format item)};
    return unless $filename || $item;
    return unless $item && $item->voip_fax_data->data;

    my $tmp_fh;

    if ($filename) {
        my $spool = $c->config->{faxserver}{spool_dir} || return;
        foreach my $dir (qw(completed failed)) {
            my $check_path = sprintf "%s/%s/%s", $spool, $dir, $filename;
            if (-e $check_path) {
                $filepath = $check_path;
                last;
            }
        }
        return unless $filepath;
    } else {
        if ($format) {
            unless ( ($tmp_fh, $filepath) = File::Temp::tempfile( DIR => $c->config->{faxserver}{spool_dir}."/tmp") ) {
                $c->log->error("Cannot create temp file: $ERRNO");
                return;
            }
            binmode $tmp_fh;
            print $tmp_fh $item->voip_fax_data->data;
            close $tmp_fh;
        } else {
            return ($item->voip_fax_data->data, $ext);
        }
    }

    if ($format) {
        my $client = new NGCP::Fax;
        my $fh = $client->convert_file({}, $filepath, $format);
        my $rs_old = $RS;
        local $RS = undef;
        $content = <$fh>;
        local $RS = $rs_old;
        close $fh;
        $ext = $client->formats->{$format}->{extension};
    } else {
        eval { $content = read_file($filepath, binmode => ':raw'); };
        return if $@;
    }

    return ($content, $ext);
}

sub process_fax_journal_item {
    my ($c, $result, $subscriber) = @_;
    my $resource = { caller => $result->caller,
                     callee => $result->callee };
    my $dir      = $result->direction;
    my $prov_sub = $subscriber->provisioning_voip_subscriber;
    my $src_sub  = $result->caller_subscriber // undef;
    my $dst_sub  = $result->callee_subscriber // undef;
    my $prov_src_sub = $src_sub
                            ? $src_sub->provisioning_voip_subscriber
                            : $subscriber;
    my $prov_dst_sub = $dst_sub
                            ? $dst_sub->provisioning_voip_subscriber
                            : $subscriber;
    my $src_rewrite = 1;
    my $dst_rewrite = 1;
    if ($src_sub && $dst_sub && $src_sub->contract_id == $dst_sub->contract_id) {
        if ($prov_src_sub && $prov_src_sub->pbx_extension) {
            $resource->{caller} = $prov_src_sub->pbx_extension;
            $src_rewrite = 0;
        }
        if ($prov_dst_sub && $prov_dst_sub->pbx_extension) {
            $resource->{callee} = $prov_dst_sub->pbx_extension;
            $dst_rewrite = 0;
        }
    } else {
        if ($prov_sub->pbx_extension) {
            if ($dir eq 'out') {
                $resource->{caller} = $prov_sub->pbx_extension;
                $src_rewrite = 0;
            } else {
                $resource->{callee} = $prov_sub->pbx_extension;
                $dst_rewrite = 0;
            }
        }
    }
    if ($src_rewrite) {
        if (my $rt_caller = NGCP::Panel::Utils::Subscriber::apply_rewrite(
                                c => $c,
                                number => $resource->{caller},
                                subscriber => $src_sub // $subscriber,
                                direction => 'caller_out'
                            )) {
            $resource->{caller} = $rt_caller;
        }
    }
    if ($dst_rewrite) {
        if (my $rt_callee = NGCP::Panel::Utils::Subscriber::apply_rewrite(
                                c => $c,
                                number => $resource->{callee},
                                subscriber => $dst_sub // $subscriber,
                                direction => 'caller_out'
                            )) {
            $resource->{callee} = $rt_callee;
        }
    }
    return $resource;
}

sub process_extended_fax_journal_item {
    my ($c, $result, $subscriber) = @_;
    my $resource = { caller => $result->caller,
                     callee => $result->callee };
    my $dir      = $result->direction;
    my $prov_sub = $subscriber->provisioning_voip_subscriber;
    my $src_sub  = $result->caller_subscriber // undef; #undef, if not local, or if caller is username
    #try finding it:
    unless ($src_sub) {
        my $prov_src_sub = $c->model('DB')->resultset('provisioning_voip_subscribers')->search({
            'username' => $result->caller,
        })->first();
        if ($prov_src_sub) {
            $src_sub = $prov_src_sub->voip_subscriber;
        }
    }
    my $dst_sub  = $result->callee_subscriber // undef; #undef, if not local, or if callee is username
    #try finding it:
    unless ($dst_sub) {
        my $prov_dst_sub = $c->model('DB')->resultset('provisioning_voip_subscribers')->search({
            'username' => $result->callee,
        })->first();
        if ($prov_dst_sub) {
            $dst_sub = $prov_dst_sub->voip_subscriber;
        }
    }
    # either src or dst must be local.
    my $prov_src_sub = $src_sub
                            ? $src_sub->provisioning_voip_subscriber
                            : undef;
                            #: $prov_sub;
    my $prov_dst_sub = $dst_sub
                            ? $dst_sub->provisioning_voip_subscriber
                            : undef;
                            #: $prov_sub;
    my $src_rewrite = 1;
    my $dst_rewrite = 1;

    my $label = 'fax_journal id ' . $result->id . ' (sid = ' . $result->sid . ') ' . $dir;
    $c->log->debug($label . ' number normalization: fax_journal sub username = ' . $prov_sub->username .
        ', caller = ' . $resource->{caller} . ', callee = ' . $resource->{callee} .
        ', prov_src_sub username = ' . ($prov_src_sub ? $prov_src_sub->username : '') . ', prov_dst_sub username = ' . ($prov_dst_sub ? $prov_dst_sub->username : ''));

    if ($dir eq 'out') {
        # outgoing fax_journal record: fax_journal item subscriber is the callER

        if ($src_sub and not $dst_sub) {
            $prov_dst_sub = $c->model('DB')->resultset('provisioning_voip_subscribers')->search({
                'account_id' => $src_sub->contract_id,
                'pbx_extension' => $resource->{callee},
            })->first();
            if ($prov_dst_sub) {
                $dst_sub = $prov_dst_sub->voip_subscriber;
                $c->log->debug($label . ' no destination, but found extension ' . $resource->{callee});
            } else {
                #try harder:
                my $callee = $resource->{callee};
                if (my $rt_callee = NGCP::Panel::Utils::Subscriber::apply_rewrite(
                    c => $c,
                    number => $callee,
                    subscriber => $src_sub // $subscriber,
                    direction => 'callee_in'
                )) {
                    $callee = $rt_callee; #e164
                    $c->log->debug($label . ' no destination, normalized ' . $resource->{callee} . ' to ' . $callee);
                    my $prov_dst_alias = $c->model('DB')->resultset('voip_dbaliases')->search({
                                    'username' => $callee,
                                })->first();
                    if ($prov_dst_alias) {
                        $c->log->debug($label . ' no destination, alias found');
                        $prov_dst_sub = $prov_dst_alias->subscriber;
                        if ($prov_dst_sub) {
                            $dst_sub = $prov_dst_sub->voip_subscriber;
                        }
                    } else {
                        $c->log->debug($label . ' no destination, no alias found');
                    }
                } else {
                    $c->log->debug($label . ' no destination, rewrite not matched');
                }
            }
        }

        # caller field:
        if ($prov_sub->pbx_extension) {
            # always set the caller to the extension, if available (pbx)
            $resource->{caller} = $prov_sub->pbx_extension;
            $src_rewrite = 0;
            $c->log->debug($label . ' CALLER number normalization: subscriber has pbx_extension' .
                ', applying ' . $resource->{caller});
        } elsif ($prov_sub->is_pbx_pilot) {
            # if no extension, it can be the pbx pilot.
            if ($resource->{caller} eq $prov_sub->username) {
                # use its primary number, if the caller field shows a username.
                $resource->{caller} = _get_alias_or_primary_number($c,$subscriber);
                $src_rewrite = 0;
                $c->log->debug($label . ' CALLER number normalization: subscriber is pbx pilot' .
                    ' and caller shows the username, applying primary number ' . $resource->{caller});
            } else {
                $c->log->debug($label . ' CALLER number normalization: subscriber is pbx pilot' .
                    ' but caller does not show the username, no override');
            }
        } else {
            # otherwise its some other local subscriber.
            if ($resource->{caller} eq $prov_sub->username) {
                # use its primary number, if the caller field shows a username.
                $resource->{caller} = _get_alias_or_primary_number($c,$subscriber);
                $src_rewrite = 0;
                $c->log->debug($label . ' CALLER number normalization: subscriber is other local susbcriber' .
                    ' and caller shows the username, applying primary number ' . $resource->{caller});
            } else {
                $c->log->debug($label . ' CALLER number normalization: subscriber is other local susbcriber' .
                    ' but caller does not show the username, no override');
            }
        }

        # callee field:
        if ($src_sub && $dst_sub && $src_sub->contract_id == $dst_sub->contract_id) {
            # for pbx, src and dst are local and belong to same contract

            if ($prov_dst_sub->pbx_extension) {
                # always set the callee to the extension, if available
                $resource->{callee} = $prov_dst_sub->pbx_extension;
                $dst_rewrite = 0;
                $c->log->debug($label . ' CALLEE number normalization: intra customer and destination has pbx_extension' .
                    ', applying ' . $resource->{callee});
            } elsif ($prov_dst_sub->is_pbx_pilot) {
                # if no extension, it can be the pbx pilot.
                if ($resource->{callee} eq $prov_dst_sub->username) {
                    # use its primary number, if the callee field shows a username.
                    $resource->{callee} = _get_alias_or_primary_number($c,$dst_sub);
                    $dst_rewrite = 0;
                    $c->log->debug($label . ' CALLEE number normalization: intra customer and destination is pbx pilot' .
                        ' and callee shows the username, applying primary number ' . $resource->{callee});
                } else {
                    $c->log->debug($label . ' CALLEE number normalization: intra customer and destination is pbx pilot' .
                        ' but callee does not show the username, no override');
                }
            } else {
                # otherwise its a non-pbx intra customer fax.
                if ($resource->{callee} eq $prov_dst_sub->username) {
                    # use its primary number, if the callee field shows a username.
                    $resource->{callee} = _get_alias_or_primary_number($c,$dst_sub);
                    $dst_rewrite = 0;
                    $c->log->debug($label . ' CALLEE number normalization: non-pbx intra customer destination' .
                        ' and callee shows the username, applying primary number ' . $resource->{callee});
                } else {
                    $c->log->debug($label . ' CALLEE number normalization: non-pbx intra customer destination' .
                        ' but callee does not show the username, no override');
                }
            }
        } else {
            # fax to other subscriber, maybe not local.
            if ($dst_sub && $prov_dst_sub && $resource->{callee} eq $prov_dst_sub->username) {
                # use its primary number, if the callee field shows a username.
                $resource->{callee} = _get_alias_or_primary_number($c,$dst_sub);
                $dst_rewrite = 0;
                $c->log->debug($label . ' CALLEE number normalization: destination is other local susbcriber ' .
                   ' and callee shows the username, applying primary number ' . $resource->{callee});
            } else {
                $c->log->debug($label . ' CALLEE number normalization: destination is other susbcriber ' .
                   ' and callee does not show the username, no override');
            }
        }

        if ($dst_rewrite) {
            if (my $rt_callee = NGCP::Panel::Utils::Subscriber::apply_rewrite(
                                    c => $c,
                                    number => $resource->{callee},
                                    subscriber => $src_sub // $subscriber,
                                    direction => 'callee_in'
                                )) {
                $resource->{callee} = $rt_callee;
                $c->log->debug($label . ' number normalization: callee rewrite applied - ' .  $resource->{callee});
                #now we should have strict e164.
                if ($rt_callee = NGCP::Panel::Utils::Subscriber::apply_rewrite(
                                    c => $c,
                                    number => $resource->{callee},
                                    subscriber => $src_sub // $subscriber,
                                    #avp_caller_subscriber => $dst_sub,
                                    direction => 'caller_out'
                                )) {
                    $resource->{callee} = $rt_callee;
                    $c->log->debug($label . ' 2nd number normalization: caller rewrite applied to callee - ' .  $resource->{callee});
                } else {
                    $c->log->debug($label . ' 2nd number normalization: caller rewrite ignored to callee');
                }
            } else {
                $c->log->debug($label . ' number normalization: callee rewrite ignored');
            }
        } else {
            $c->log->debug($label . ' number normalization: callee rewrite skipped');
        }

    } else {
        # incoming fax_journal record: fax_journal item subscriber is the callEE

        # callee field:
        if ($prov_sub->pbx_extension) {
            # always set the callee to the extension, if available (pbx)
            $resource->{callee} = $prov_sub->pbx_extension;
            $dst_rewrite = 0;
            $c->log->debug($label . ' CALLEE number normalization: subscriber has pbx_extension' .
                ', applying ' . $resource->{callee});
        } elsif ($prov_sub->is_pbx_pilot) {
            # if no extension, it can be the pbx pilot.
            if ($resource->{callee} eq $prov_sub->username) {
                # use its primary number, if the callee field shows a username.
                $resource->{callee} = _get_alias_or_primary_number($c,$subscriber);
                $dst_rewrite = 0;
                $c->log->debug($label . ' CALLEE number normalization: subscriber is pbx pilot' .
                    ' and callee shows the username, applying primary number ' . $resource->{callee});
            } else {
                $c->log->debug($label . ' CALLEE number normalization: subscriber is pbx pilot' .
                    ' but callee does not show the username, no override');
            }
        } else {
            # otherwise its some other local subscriber.
            if ($resource->{callee} eq $prov_sub->username) {
                # use its primary number, if the caller field shows a username.
                $resource->{callee} = _get_alias_or_primary_number($c,$subscriber);
                $dst_rewrite = 0;
                $c->log->debug($label . ' CALLEE number normalization: subscriber is other local susbcriber' .
                    ' and callee shows the username, applying primary number ' . $resource->{callee});
            } else {
                $c->log->debug($label . ' CALLEE number normalization: subscriber is other local susbcriber' .
                    ' but callee does not show the username, no override');
            }
        }

        # caller field:
        if ($src_sub && $dst_sub && $src_sub->contract_id == $dst_sub->contract_id) {
            # for pbx, src and dst are local and belong to same contract

            if ($prov_src_sub->pbx_extension) {
                # always set the caller to the extension, if available
                $resource->{caller} = $prov_src_sub->pbx_extension;
                $src_rewrite = 0;
                $c->log->debug($label . ' CALLER number normalization: intra customer and source has pbx_extension' .
                    ', applying ' . $resource->{caller});
            } elsif ($prov_src_sub->is_pbx_pilot) {
                # if no extension, it can be the pbx pilot.
                if ($resource->{caller} eq $prov_src_sub->username) {
                    # use its primary number, if the caller field shows a username.
                    $resource->{caller} = _get_alias_or_primary_number($c,$src_sub);
                    $src_rewrite = 0;
                    $c->log->debug($label . ' CALLER number normalization: intra customer and source is pbx pilot' .
                        ' and caller shows the username, applying primary number ' . $resource->{caller});
                } else {
                    $c->log->debug($label . ' CALLER number normalization: intra customer and source is pbx pilot' .
                        ' but caller does not show the username, no override');
                }
                #if ($src_rewrite) {
                    _apply_in_caller_rewrite($c,$resource,$dst_sub,$dst_sub,$label);
                #}
            } else {
                # otherwise its a non-pbx intra customer fax.
                if ($resource->{caller} eq $prov_src_sub->username) {
                    # use its primary number, if the caller field shows a username.
                    $resource->{caller} = _get_alias_or_primary_number($c,$src_sub);
                    $src_rewrite = 0;
                    $c->log->debug($label . ' CALLER number normalization: non-pbx intra customer source' .
                        ' and caller shows the username, applying primary number ' . $resource->{caller});
                } else {
                    $c->log->debug($label . ' CALLER number normalization: non-pbx intra customer source' .
                        ' but caller does not show the username, no override');
                }
                #if ($src_rewrite) {
                    _apply_in_caller_rewrite($c,$resource,$dst_sub,$dst_sub,$label);
                #}
            }
        } else {
            # fax from other subscriber, maybe not local.
            if ($src_sub && $prov_src_sub && $resource->{caller} eq $prov_src_sub->username) {
                # use its primary number, if the caller field shows a username.
                $resource->{caller} = _get_alias_or_primary_number($c,$src_sub);
                $src_rewrite = 0;
                $c->log->debug($label . ' CALLER number normalization: source is other local susbcriber ' .
                   ' and caller shows the username, applying primary number ' . $resource->{caller});
            } else {
                $c->log->debug($label . ' CALLER number normalization: source is other susbcriber ' .
                   ' and caller does not show the username, no override');
            }
            if ($dst_sub) {
                _apply_in_caller_rewrite($c,$resource,$dst_sub,$dst_sub,$label);
            }
        }

    }

    return $resource;
}

sub _apply_in_caller_rewrite {

    my ($c,$resource,$src_sub,$dst_sub,$label) = @_;
    if (my $rt_caller = NGCP::Panel::Utils::Subscriber::apply_rewrite(
                            c => $c,
                            number => $resource->{caller},
                            subscriber => $src_sub,
                            avp_callee_subscriber => $dst_sub,
                            direction => 'caller_out'
                        )) {
        $resource->{caller} = $rt_caller;
        $c->log->debug($label . ' number normalization: caller rewrite applied - ' .  $resource->{caller});
        return 1;
    } else {
        $c->log->debug($label . ' number normalization: caller rewrite ignored');
        return 0;
    }

}

sub _get_alias_or_primary_number {

    my ($c,$subscriber) = @_;
    my $prov_subs = $subscriber->provisioning_voip_subscriber;
    if ($prov_subs) {
        my $pref = $c->model('DB')->resultset('voip_usr_preferences')->search({
            'attribute.attribute' => 'gpp0',
            'subscriber_id' => $prov_subs->id,
        },{
            'join' => 'attribute',
        })->first();
        if ($pref and $pref->value) {
            return $pref->value;
        }
    }
    my $primary_number = $subscriber->primary_number;
    return $primary_number->cc . ($primary_number->ac // '') . $primary_number->sn;

}

1;

# vim: set tabstop=4 expandtab:
