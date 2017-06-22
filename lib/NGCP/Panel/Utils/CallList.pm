package NGCP::Panel::Utils::CallList;

use strict;
use warnings;

use JSON qw();
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Subscriber;

use constant SUPPRESS_OUT => 1;
use constant SUPPRESS_IN => 2;
use constant SUPPRESS_INOUT => 3;

my $source_cli_suppression_id_colname = 'source_cli_suppression_id';
my $destination_user_in_suppression_id_colname = 'destination_user_in_suppression_id';

# owner:
#     * subscriber (optional)
#     * customer
# provides:
#     * call_id
#     * customer_cost
#     * total_customer_cost
#     * customer_free_time
#     * direction
#     * duration
#     * id
#     * intra_customer
#     * other_cli
#     * own_cli
#     * clir
#     * start_time
#     * status
#     * rating_status
#     * type
sub process_cdr_item {
    my ($c, $item, $owner, $params) = @_;

    my $sub = $owner->{subscriber};
    my $cust = $owner->{customer};
    my $resource = {};

    $params //= $c->req->params;

    $resource->{call_id} = $item->call_id;

    my $intra = 0;
    if($item->source_user_id && $item->source_account_id == $item->destination_account_id) {
        $resource->{intra_customer} = JSON::true;
        $intra = 1;
    } else {
        $resource->{intra_customer} = JSON::false;
        $intra = 0;
    }
    # internal subscriber calls => out
    if(defined $sub && $sub->uuid eq $item->source_user_id &&
                       $sub->uuid eq $item->destination_user_id) {
        $resource->{direction} = "out";
    # subscriber incoming calls => in
    } elsif (defined $sub && $sub->uuid eq $item->destination_user_id) {
        $resource->{direction} = "in";
    # customer incoming calls => in
    } elsif (defined $cust && $item->destination_account_id == $cust->id
        && ( $item->source_account_id != $cust->id ) ) {
        $resource->{direction} = "in";
    # rest => out
    } else {
        $resource->{direction} = "out";
    }

    my $anonymize = $c->user->roles ne "admin" && !$intra && $item->source_clir;
    # try to use source_cli first and if it is "anonymous" fall-back to
    # source_user@source_domain + mask the domain for non-admins
    my $source_cli = $item->source_cli !~ /anonymous/i
                        ? $item->source_cli
                        : $item->source_user . '@' . $item->source_domain;
    $source_cli = $anonymize ? 'anonymous@anonymous.invalid' : $source_cli;
    $resource->{clir} = $item->source_clir;

    my ($source_cli_suppression,$destination_user_in_suppression);
    my $supressions_rs = $c->model('DB')->resultset('call_list_suppressions');
    $source_cli_suppression = $supressions_rs->find($item->get_column($source_cli_suppression_id_colname))
        if defined $item->get_column($source_cli_suppression_id_colname);
    $destination_user_in_suppression = $supressions_rs->find($item->get_column($destination_user_in_suppression_id_colname))
        if defined $item->get_column($destination_user_in_suppression_id_colname);

    my ($src_sub, $dst_sub);
    my $billing_src_sub = $item->source_subscriber;
    my $billing_dst_sub = $item->destination_subscriber;
    if($billing_src_sub && $billing_src_sub->provisioning_voip_subscriber) {
        $src_sub = $billing_src_sub->provisioning_voip_subscriber;
    }
    if($billing_dst_sub && $billing_dst_sub->provisioning_voip_subscriber) {
        $dst_sub = $billing_dst_sub->provisioning_voip_subscriber;
    }
    my ($own_normalize, $other_normalize, $own_domain, $other_domain, $own_suppression, $other_suppression);
    my $other_skip_domain = 0;

    if($resource->{direction} eq "out") {
        # for pbx out calls, use extension as own cli
        if($src_sub && $src_sub->pbx_extension) {
            $resource->{own_cli} = $src_sub->pbx_extension;
        # for termianted subscribers if there is an alias field (e.g. gpp0), use this
        } elsif($item->source_account_id && $params->{'intra_alias_field'}) {
            my $alias = $item->get_column('source_'.$params->{'intra_alias_field'});
            $resource->{own_cli} = $alias // $source_cli;
            $own_normalize = 0;
        # if there is an alias field (e.g. gpp0), use this
        } elsif($item->source_account_id && $params->{'alias_field'}) {
            my $alias = $item->get_column('source_'.$params->{'alias_field'});
            $resource->{own_cli} = $alias // $source_cli;
            $own_normalize = 1;
        } else {
            $resource->{own_cli} = $source_cli;
            $own_normalize = 1;
        }
        $own_domain = $item->source_domain;
        $own_suppression = $source_cli_suppression;

        # for intra pbx out calls, use extension as other cli
        if($intra && $dst_sub && $dst_sub->pbx_extension) {
            $resource->{other_cli} = $dst_sub->pbx_extension;
        # for termianted subscribers if there is an alias field (e.g. gpp0), use this
        } elsif($intra && $item->destination_account_id && $params->{'intra_alias_field'}) {
            my $alias = $item->get_column('destination_'.$params->{'intra_alias_field'});
            $resource->{other_cli} = $alias // $item->destination_user_in;
            $other_normalize = 0;
        # if there is an alias field (e.g. gpp0), use this
        } elsif($item->destination_account_id && $params->{'alias_field'}) {
            my $alias = $item->get_column('destination_'.$params->{'alias_field'});
            $resource->{other_cli} = $alias // $item->destination_user_in;
            $other_normalize = 1;
        } else {
            $resource->{other_cli} = $item->destination_user_in;
            $other_normalize = 1;
        }
        $other_domain = $item->destination_domain;
        $other_suppression = $destination_user_in_suppression;
    } else {
        # for pbx in calls, use extension as own cli
        if($dst_sub && $dst_sub->pbx_extension) {
            $resource->{own_cli} = $dst_sub->pbx_extension;
        # for termianted subscribers if there is an alias field (e.g. gpp0), use this
        } elsif($item->destination_account_id && $params->{'intra_alias_field'}) {
            my $alias = $item->get_column('destination_'.$params->{'intra_alias_field'});
            $resource->{own_cli} = $alias // $item->destination_user_in;
            $own_normalize = 0;
        # if there is an alias field (e.g. gpp0), use this
        } elsif($item->destination_account_id && $params->{'alias_field'}) {
            my $alias = $item->get_column('destination_'.$params->{'alias_field'});
            $resource->{own_cli} = $alias // $item->destination_user_in;
            $own_normalize = 1;
        } else {
            $resource->{own_cli} = $item->destination_user_in;
            $own_normalize = 1;
        }
        $own_domain = $item->destination_domain;
        $own_suppression = $destination_user_in_suppression;

        # rewrite cf to voicemail to "voicemail"
        if($item->destination_user_in =~ /^vm[ub]/ &&
           $item->destination_domain_in eq "voicebox.local") {
            $resource->{other_cli} = "voicemail";
            $other_normalize = 0;
            $other_skip_domain = 1;
            $resource->{direction} = "out";
        # rewrite cf to conference to "conference"
        } elsif($item->destination_user_in =~ /^conf=/ &&
           $item->destination_domain_in eq "conference.local") {
            $resource->{other_cli} = "conference";
            $other_normalize = 0;
            $other_skip_domain = 1;
            $resource->{direction} = "out";
        # rewrite cf to auto-attendant to "auto-attendant"
        } elsif($item->destination_user_in =~ /^auto-attendant$/ &&
           $item->destination_domain_in eq "app.local") {
            $resource->{other_cli} = "auto-attendant";
            $other_normalize = 0;
            $other_skip_domain = 1;
            $resource->{direction} = "out";
        } else {
            # for intra pbx in calls, use extension as other cli
            if($intra && $src_sub && $src_sub->pbx_extension) {
                $resource->{other_cli} = $src_sub->pbx_extension;
            # for termianted subscribers if there is an alias field (e.g. gpp0), use this
            } elsif($intra && $item->source_account_id && $params->{'intra_alias_field'}) {
                my $alias = $item->get_column('source_'.$params->{'intra_alias_field'});
                $resource->{other_cli} = $alias // $source_cli;
                $other_normalize = 0;
            # if there is an alias field (e.g. gpp0), use this
            } elsif($item->source_account_id && $params->{'alias_field'}) {
                my $alias = $item->get_column('source_'.$params->{'alias_field'});
                $resource->{other_cli} = $alias // $source_cli;
                $other_normalize = 1;
            } else {
                $resource->{other_cli} = $source_cli;
                $other_normalize = 1;
            }
            $other_suppression = $source_cli_suppression;
        }
        $other_domain = $item->source_domain;
    }


    # for inbound calls, always show type call, even if it's
    # a call forward
    if($resource->{direction} eq "in") {
        $resource->{type} = "call";
    } else {
        $resource->{type} = $item->call_type;
    }

    # strip any _b2b-1 and _pbx-1 to allow grouping of calls
    $resource->{call_id} =~ s/(_b2b-1|_pbx-1)+$//g;

    my $own_sub = ($resource->{direction} eq "out")
        ? $billing_src_sub
        : $billing_dst_sub;
    my $other_sub = ($resource->{direction} eq "out")
        ? $billing_dst_sub
        : $billing_src_sub;

    if($resource->{own_cli} !~ /(^\d+$|[\@])/) {
        $resource->{own_cli} .= '@'.$own_domain;
    } elsif($own_normalize) {
        if (my $normalized_cli = NGCP::Panel::Utils::Subscriber::apply_rewrite(
                c => $c, subscriber => $sub // $own_sub,
                number => $resource->{own_cli}, direction => "caller_out")) {
            $resource->{own_cli} = $normalized_cli;
        }
    }

    if($resource->{direction} eq "in" && $item->source_clir && $intra == 0) {
        $resource->{other_cli} = undef;
    } elsif(!$other_skip_domain && $resource->{other_cli} !~ /(^\d+$|[\@])/) {
        $resource->{other_cli} .= '@'.$other_domain;
    } elsif($other_normalize) {
        if (my $normalized_cli = NGCP::Panel::Utils::Subscriber::apply_rewrite(
                c => $c, subscriber => $sub // $own_sub,
                number => $resource->{other_cli}, direction => "caller_out")) {
            $resource->{other_cli} = $normalized_cli;
        }
    }

    my @own_details = ();
    if ($own_suppression) {
        if (_is_show_suppressions($c)) {
            push(@own_details,'obfuscated: ' . $own_suppression->label) if 'obfuscate' eq $own_suppression->mode;
            push(@own_details,'filtered: ' . $own_suppression->label) if 'filter' eq $own_suppression->mode;
        } else {
            $resource->{own_cli} = $own_suppression->label;
        }
    }
    if ( (!($sub // $own_sub)) || (($sub // $own_sub)->status eq "terminated") ) {
        push(@own_details,'terminated');
        #$resource->{own_cli} .= " (terminated)";
    }
    $resource->{own_cli} .= ' (' . join(', ',@own_details) . ')' if (scalar @own_details) > 0;
    my @other_details = ();
    if ($other_suppression) {
        if (_is_show_suppressions($c)) {
            push(@other_details,'obfuscated: ' . $other_suppression->label) if 'obfuscate' eq $other_suppression->mode;
            push(@other_details,'filtered: ' . $other_suppression->label) if 'filter' eq $other_suppression->mode;
        } else {
            $resource->{other_cli} = $other_suppression->label;
        }
    }
    if ($other_sub && $other_sub->status eq "terminated" &&
            $own_sub && $own_sub->contract_id == $other_sub->contract_id) {
        push(@other_details,'terminated');
        #$resource->{other_cli} .= " (terminated)";
    }
    $resource->{other_cli} .= ' (' . join(', ',@other_details) . ')' if (scalar @other_details) > 0;

    $resource->{status} = $item->call_status;
    $resource->{rating_status} = $item->rating_status;

    $resource->{start_time} = $item->start_time;
    $resource->{duration} = NGCP::Panel::Utils::DateTime::sec_to_hms($c,$item->duration,3);
    $resource->{customer_cost} = $resource->{direction} eq "out" ?
        $item->source_customer_cost : $item->destination_customer_cost;
    if ($cust->add_vat) {
        $resource->{total_customer_cost} = $resource->{customer_cost} * (1 + $cust->vat_rate / 100);
    } else {
        $resource->{total_customer_cost} = $resource->{customer_cost};
    }
    $resource->{customer_free_time} = $resource->{direction} eq "out" ?
        $item->source_customer_free_time : 0;

    return $resource;
}

sub _is_show_suppressions {
    my $c = shift;
    return ($c->user->roles eq "admin" or $c->user->roles eq "reseller");
}

sub call_list_suppressions_rs {
    my ($c,$rs,$mode) = @_;
    my %search_cond = ();
    my %search_xtra = ();
    if (_is_show_suppressions($c)) {
        if (defined $mode and SUPPRESS_OUT == $mode) {
            $search_xtra{'+select'} = [
                #{ '' => \[ 'me.source_cli' ] , -as => $source_cli_suppression_id_colname },
                { '' => \[ 'NULL' ] , -as => $source_cli_suppression_id_colname },
                { '' => \[ _get_call_list_suppression_sq('outgoing',qw(filter obfuscate)) ] , -as => $destination_user_in_suppression_id_colname },
            ];
        } elsif (defined $mode and SUPPRESS_IN == $mode) {
            $search_xtra{'+select'} = [
                { '' => \[ _get_call_list_suppression_sq('incoming',qw(filter obfuscate)) ] , -as => $source_cli_suppression_id_colname },
                #{ '' => \[ 'me.destination_user_in' ] , -as => $destination_user_in_suppression_id_colname },
                { '' => \[ 'NULL' ] , -as => $destination_user_in_suppression_id_colname },
            ];
        } elsif (defined $mode and SUPPRESS_INOUT == $mode) {
            $search_xtra{'+select'} = [
                { '' => \[ _get_call_list_suppression_sq('incoming',qw(filter obfuscate)) ] , -as => $source_cli_suppression_id_colname },
                { '' => \[ _get_call_list_suppression_sq('outgoing',qw(filter obfuscate)) ] , -as => $destination_user_in_suppression_id_colname },
            ];
        } else {
            $search_xtra{'+select'} = [
                #{ '' => \[ 'me.source_cli' ] , -as => $source_cli_suppression_id_colname },
                { '' => \[ 'NULL' ] , -as => $source_cli_suppression_id_colname },
                #{ '' => \[ 'me.destination_user_in' ] , -as => $destination_user_in_suppression_id_colname },
                { '' => \[ 'NULL' ] , -as => $destination_user_in_suppression_id_colname },
            ];
        }
    } else {
        if (defined $mode and SUPPRESS_OUT == $mode) {
            $search_xtra{'+select'} = [
                #{ '' => \[ 'me.source_cli' ] , -as => $source_cli_suppression_id_colname },
                { '' => \[ 'NULL' ] , -as => $source_cli_suppression_id_colname },
                { '' => \[ _get_call_list_suppression_sq('outgoing',qw(obfuscate)) ] , -as => $destination_user_in_suppression_id_colname },
            ];
            $search_cond{'-not exists'} = \[ '('._get_call_list_suppression_sq('outgoing',qw(filter)).')' ];
        } elsif (defined $mode and SUPPRESS_IN == $mode) {
            $search_xtra{'+select'} = [
                { '' => \[ _get_call_list_suppression_sq('incoming',qw(obfuscate)) ] , -as => $source_cli_suppression_id_colname },
                #{ '' => \[ 'me.destination_user_in' ] , -as => $destination_user_in_suppression_id_colname },
                { '' => \[ 'NULL' ] , -as => $destination_user_in_suppression_id_colname },
            ];
            $search_cond{'-not exists'} = \[ '('._get_call_list_suppression_sq('incoming',qw(filter)).')' ];
        } elsif (defined $mode and SUPPRESS_INOUT == $mode) {
            $search_xtra{'+select'} = [
                { '' => \[ _get_call_list_suppression_sq('incoming',qw(obfuscate)) ] , -as => $source_cli_suppression_id_colname },
                { '' => \[ _get_call_list_suppression_sq('outgoing',qw(obfuscate)) ] , -as => $destination_user_in_suppression_id_colname },
            ];
            $search_cond{'-not exists'} => \[ '('._get_call_list_suppression_sq('incoming',qw(filter)).')' ];
            $search_cond{'-not exists'} => \[ '('._get_call_list_suppression_sq('outgoing',qw(filter)).')' ];
        } else {
            $search_xtra{'+select'} = [
                #{ '' => \[ 'me.source_cli' ] , -as => $source_cli_suppression_id_colname },
                { '' => \[ 'NULL' ] , -as => $source_cli_suppression_id_colname },
                #{ '' => \[ 'me.destination_user_in' ] , -as => $destination_user_in_suppression_id_colname },
                { '' => \[ 'NULL' ] , -as => $destination_user_in_suppression_id_colname },
            ];
        }
    }
    return $rs->search_rs(\%search_cond,\%search_xtra);
}

sub _get_call_list_suppression_sq {
    my ($direction,@modes) = @_;
    my $domain_col;
    my $number_col;
    if ('incoming' eq $direction) {
        $domain_col = 'destination_domain';
        $number_col = 'source_cli';
    } else {
        $domain_col = 'source_domain';
        $number_col = 'destination_user_in';
    }
    return "select id from billing.call_list_suppressions where direction = \"$direction\" and mode in (".join(',',map { '"'.$_.'"'; } @modes).")".
        " and (domain = \"\" or domain = me.$domain_col) and me.$number_col regexp pattern limit 1";

}

#sub _get_call_list_suppressions_rs {
#    my ($c,$direction,@modes) = @_;
#    my $domain_col;
#    my $number_col;
#    if ('incoming' eq $direction) {
#        $domain_col = 'destination_domain';
#        $number_col = 'source_cli';
#    } else {
#        $domain_col = 'source_domain';
#        $number_col = 'destination_user_in';
#    }
#    return $c->model('DB')->resultset('call_list_suppressions')->search_rs({
#        direction => { '=' => $direction },
#        mode => { 'in' => \@modes },
#        '-or' => [{
#            domain => '',
#            },{
#            domain => \"me.$domain_col",
#        }],
#        "me.$number_col" => { 'regexp' => \'pattern' },
#    });
#
#}

1;

# vim: set tabstop=4 expandtab:
