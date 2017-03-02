package NGCP::Panel::Utils::Fax;

use English;
use File::Temp qw/tempfile/;
use File::Slurp;
use TryCatch;
use IPC::System::Simple qw/capture/;
use Data::Dumper;
use Net::Ping;

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
        my $ping = new Net::Ping('tcp', 1);
        $ping->port_number($port);
        do {
            my $host = $hosts[rand @hosts];
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
    }
    if($args{data}){
        $sendfax_args{input} = [\$args{data}];
    }
    my $client = new NGCP::Fax;
    $client->send_fax(\%sendfax_args);
    $c->log->debug("webfax: res=$res;");
}

sub get_fax {
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

    my ($filename, $format) = @{args}{qw(filename format)};
    return unless $filename;
    my $spool = $c->config->{faxserver}{spool_dir} || return;
    my $filepath;
    foreach my $dir (qw(completed failed)) {
        my $check_path = sprintf "%s/%s/%s", $spool, $dir, $filename;
        if (-e $check_path) {
            $filepath = $check_path;
            last;
        }
    }
    return unless $filepath;


    my $content;
    my $ext = 'tif';

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
    # (a) if src and dest belong to same contract:
    if ($src_sub && $dst_sub && $src_sub->contract_id == $dst_sub->contract_id) {
        if ($prov_src_sub) {
            # if there's an extension, use that.
            if ($prov_src_sub->pbx_extension) {
                $resource->{caller} = $prov_src_sub->pbx_extension;
                $src_rewrite = 0;
            # otherwise if the fax_journal field is the subscriber username, take the primary_number:
            } elsif ($result->caller eq $prov_src_sub->username && my $primary_number = $src_sub->primary_number) {
                $resource->{caller} = $primary_number->cc . ($primary_number->ac // '') . $primary_number->sn;
                $src_rewrite = 0;
            }
        }
        if ($prov_dst_sub) {
            # if there's an extension, use that.
            if ($prov_dst_sub->pbx_extension) {
                $resource->{callee} = $prov_dst_sub->pbx_extension;
                $dst_rewrite = 0;
            # otherwise if the fax_journal field is the subscriber username, take the primary_number:
            } elsif ($result->callee eq $prov_dst_sub->username && my $primary_number = $dst_sub->primary_number) {
                $resource->{callee} = $primary_number->cc . ($primary_number->ac // '') . $primary_number->sn;
                $dst_rewrite = 0;
            }
        }
    } else {
        # src and dst do not belong to same contract:
        # if there is an extension, use it no matter what:
        if ($prov_sub->pbx_extension) {
            if ($dir eq 'out') {
                $resource->{caller} = $prov_sub->pbx_extension;
                $src_rewrite = 0;
            } else {
                $resource->{callee} = $prov_sub->pbx_extension;
                $dst_rewrite = 0;
            }
        #use primary number otherwise, if we fax_journal field is the subscriber username:
        } else {
            if ($dir eq 'out') {
                if ($result->caller eq $prov_sub->username && my $primary_number = $prov_sub->primary_number) {
                    $resource->{caller} = $primary_number->cc . ($primary_number->ac // '') . $primary_number->sn;
                    $src_rewrite = 0;
                }
            } else {
                if ($result->callee eq $prov_sub->username && my $primary_number = $prov_sub->primary_number) {
                    $resource->{callee} = $primary_number->cc . ($primary_number->ac // '') . $primary_number->sn;
                    $src_rewrite = 0;
                }
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

1;

# vim: set tabstop=4 expandtab:
