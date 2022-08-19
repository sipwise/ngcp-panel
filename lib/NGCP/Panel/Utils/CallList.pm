package NGCP::Panel::Utils::CallList;

use strict;
use warnings;

use JSON qw();
use Scalar::Util;
use Text::CSV_XS;
use NGCP::Panel::Utils::MySQL;
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Subscriber;

use constant OWNER_VAT_SETTINGS => 1;

use constant SUPPRESS_OUT => 1;
use constant SUPPRESS_IN => 2;
use constant SUPPRESS_INOUT => 3;

use constant SOURCE_CLI_SUPPRESSION_ID_COLNAME => 'source_cli_suppression_id';
use constant DESTINATION_USER_IN_SUPPRESSION_ID_COLNAME => 'destination_user_in_suppression_id';

use constant ENABLE_SUPPRESSIONS => 1; #setting to 0 totally disables call list suppressions -> no discussion about performance difference.

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

    map { $resource->{$_} = $item->get_column($_); } qw/id call_id call_type/;
    if ($item->can('cdr_mos_data') and (my $mos_data = $item->cdr_mos_data)) {
        my %mos_data_res = $mos_data->get_inflated_columns;
        map { $resource->{$_} = $mos_data_res{$_}; } qw/mos_average mos_average_packetloss mos_average_jitter mos_average_roundtrip/;
    }

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

    my $anonymize;
    my $prefs;
    my $source_subscriber = $item->source_subscriber;
    my $source_prov_subscriber = undef;
    $source_prov_subscriber = $source_subscriber->provisioning_voip_subscriber if $source_subscriber;
    my $sub_pref;
    $sub_pref = $source_prov_subscriber->voip_usr_preferences->search({
        'attribute.attribute' => 'calllist_clir_scope',
    },{
        join => 'attribute',
    })->first if $source_prov_subscriber;
    if ($sub_pref) {
        $prefs = $sub_pref;
    } else {
        if ($source_subscriber) {
            my $ct_pref = $source_subscriber->contract->voip_contract_preferences->search({
                'attribute.attribute' => 'calllist_clir_scope',
            },{
                join => 'attribute',
            })->first;
            if ($ct_pref) {
                $prefs = $ct_pref;
            } else {
                my $dom_pref = $source_subscriber->domain->provisioning_voip_domain->voip_dom_preferences->search({
                    'attribute.attribute' => 'calllist_clir_scope',
                },{
                    join => 'attribute',
                })->first;
                if ($dom_pref) {
                    $prefs = $dom_pref;
                }
            }
        }
    }
    $anonymize = 1 if ($c->user->roles ne "admin" && !$intra && $item->source_clir);
    $anonymize = 1 if ($c->user->roles ne "admin" && $intra && $item->source_clir && $prefs && $prefs->value eq 'all');

    # try to use source_cli first and if it is "anonymous" fall-back to
    # source_user@source_domain + mask the domain for non-admins
    my $source_cli = $item->source_cli !~ /anonymous/i
                        ? $item->source_cli
                        : $item->source_user . '@' . $item->source_domain;
    $source_cli = $anonymize ? 'anonymous@anonymous.invalid' : $source_cli;
    $resource->{clir} = $item->source_clir;

    my ($source_cli_suppression,$destination_user_in_suppression) = _get_suppressions($c,$item);

    my ($src_sub, $dst_sub);
    my $billing_src_sub = $source_subscriber;
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
        # rewrite cf to fax2mail to "fax2mail"
        } elsif ($item->destination_user_in =~ /^fax=/ &&
           $item->destination_domain_in eq "fax2mail.local") {
            $resource->{other_cli} = "fax2mail";
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
        $c->log->debug('own suppression: id = ' . $own_suppression->id . ' direction = ' . $own_suppression->direction .
            ' mode = ' . $own_suppression->mode . ' domain = ' . $own_suppression->domain . ' pattern = ' . $own_suppression->pattern);
        if (_is_show_suppressions($c)) {
            push(@own_details,_localize_detail($c,'obfuscated',$own_suppression->label)) if 'obfuscate' eq $own_suppression->mode;
            push(@own_details,_localize_detail($c,'filtered',$own_suppression->label)) if 'filter' eq $own_suppression->mode;
        } else {
            $resource->{own_cli} = $own_suppression->label;
        }
    }
    if ( (!($sub // $own_sub)) || (($sub // $own_sub)->status eq "terminated") ) {
        push(@own_details,_localize_detail($c,'terminated'));
        #$resource->{own_cli} .= " (terminated)";
    }
    $resource->{own_cli} .= ' (' . join(', ',@own_details) . ')' if (scalar @own_details) > 0;
    my @other_details = ();
    if ($other_suppression) {
        $c->log->debug('other suppression: id = ' . $other_suppression->id . ' direction = ' . $other_suppression->direction .
            ' mode = ' . $other_suppression->mode . ' domain = ' . $other_suppression->domain . ' pattern = ' . $other_suppression->pattern);
        if (_is_show_suppressions($c)) {
            push(@other_details,_localize_detail($c,'obfuscated',$other_suppression->label)) if 'obfuscate' eq $other_suppression->mode;
            push(@other_details,_localize_detail($c,'filtered',$other_suppression->label)) if 'filter' eq $other_suppression->mode;
        } else {
            $resource->{other_cli} = $other_suppression->label;
        }
    }
    if ($other_sub && $other_sub->status eq "terminated" &&
            $own_sub && $own_sub->contract_id == $other_sub->contract_id) {
        push(@other_details,_localize_detail($c,'terminated'));
        #$resource->{other_cli} .= " (terminated)";
    }
    $resource->{other_cli} .= ' (' . join(', ',@other_details) . ')' if (scalar @other_details) > 0;

    $resource->{status} = $item->call_status;
    $resource->{rating_status} = $item->rating_status;

    $resource->{init_time} = $item->init_time;
    $resource->{start_time} = $item->start_time;
    $resource->{duration} = NGCP::Panel::Utils::DateTime::sec_to_hms($c,$item->duration,3);
    my $customer = $cust;
    if ($resource->{direction} eq "out") {
        $resource->{customer_cost} = $item->source_customer_cost;
        $resource->{customer_free_time} = $item->source_customer_free_time;
        $customer = $item->source_account unless OWNER_VAT_SETTINGS;
    } else {
        $resource->{customer_cost} = $item->destination_customer_cost;
        $resource->{customer_free_time} = 0;
        $customer = $item->destination_account unless OWNER_VAT_SETTINGS;
    }
    if (defined $customer && $customer->add_vat) {
        $resource->{total_customer_cost} = $resource->{customer_cost} * (1.0 + $customer->vat_rate / 100.0);
    } else {
        $resource->{total_customer_cost} = $resource->{customer_cost};
    }

    return $resource;

}

sub _get_suppressions {

    my ($c,$item) = @_;
    my ($source_cli_suppression,$destination_user_in_suppression);
    if (ENABLE_SUPPRESSIONS) {
        my $supressions_rs = $c->model('DB')->resultset('call_list_suppressions');
        $source_cli_suppression = $supressions_rs->find($item->get_column($c->stash->{source_cli_suppression_id_colname} || SOURCE_CLI_SUPPRESSION_ID_COLNAME))
            if defined $item->get_column($c->stash->{source_cli_suppression_id_colname} || SOURCE_CLI_SUPPRESSION_ID_COLNAME);
        $destination_user_in_suppression = $supressions_rs->find($item->get_column($c->stash->{destination_user_in_suppression_id_colname} || DESTINATION_USER_IN_SUPPRESSION_ID_COLNAME))
            if defined $item->get_column($c->stash->{destination_user_in_suppression_id_colname} || DESTINATION_USER_IN_SUPPRESSION_ID_COLNAME);
    }
    return ($source_cli_suppression,$destination_user_in_suppression);

}

sub _localize_detail {

    my ($c,@params) = @_;
    if (Scalar::Util::blessed($c) and $c->can('loc')) { #prepare for use with $c stub in generate_invoices.pl ...
        @params = map { $c->loc($_); } @params;
    }
    if ((scalar @params) == 2) {
        return sprintf('%s: %s',$params[0],$params[1]);
    } elsif ((scalar @params) == 1) {
        return sprintf('%s',$params[0]);
    }
    return '';

}

sub _is_show_suppressions {

    my $c = shift;
    return ($c->user->roles eq "admin" or $c->user->roles eq "reseller");

}

sub call_list_suppressions_rs {

    my ($c,$rs,$mode,
        $source_cli_suppression_id_colname,
        $destination_user_in_suppression_id_colname) = @_;
    return $rs unless ENABLE_SUPPRESSIONS;
    $source_cli_suppression_id_colname //= SOURCE_CLI_SUPPRESSION_ID_COLNAME;
    $destination_user_in_suppression_id_colname //= DESTINATION_USER_IN_SUPPRESSION_ID_COLNAME;
    $c->stash->{source_cli_suppression_id_colname} = $source_cli_suppression_id_colname;
    $c->stash->{destination_user_in_suppression_id_colname} = $destination_user_in_suppression_id_colname;
    my %search_cond = ();
    my %search_xtra = (order_by => '');
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
            $search_cond{'-and'} = [
                { '-not exists' => \[ '('._get_call_list_suppression_sq('incoming',qw(filter)).')' ] },
                { '-not exists' => \[ '('._get_call_list_suppression_sq('outgoing',qw(filter)).')' ] },
            ];
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

sub get_suppression_id_colnames {

    my @cols = ();
    return @cols unless ENABLE_SUPPRESSIONS;
    push(@cols,SOURCE_CLI_SUPPRESSION_ID_COLNAME);
    push(@cols,DESTINATION_USER_IN_SUPPRESSION_ID_COLNAME);
    return @cols;

}

sub suppress_cdr_fields {

    my ($c,$resource,$item) = @_;
    #use Data::Dumper;
    #$c->log->debug(Dumper($resource));
    return $resource unless ENABLE_SUPPRESSIONS;
    my ($source_cli_suppression,$destination_user_in_suppression) = _get_suppressions($c,$item);
    if (exists $resource->{source_cli} and defined $source_cli_suppression) {
        $c->log->debug('source_cli suppression: id = ' . $source_cli_suppression->id . ' direction = ' . $source_cli_suppression->direction .
            ' mode = ' . $source_cli_suppression->mode . ' domain = ' . $source_cli_suppression->domain . ' pattern = ' . $source_cli_suppression->pattern);
        my @source_cli_details = ();
        if (_is_show_suppressions($c)) {
            push(@source_cli_details,_localize_detail($c,'obfuscated',$source_cli_suppression->label)) if 'obfuscate' eq $source_cli_suppression->mode;
            push(@source_cli_details,_localize_detail($c,'filtered',$source_cli_suppression->label)) if 'filter' eq $source_cli_suppression->mode;
        } else {
            $resource->{source_cli} = $source_cli_suppression->label;
        }
        $resource->{source_cli} .= ' (' . join(', ',@source_cli_details) . ')' if (scalar @source_cli_details) > 0;
    }
    if (exists $resource->{destination_user_in} and defined $destination_user_in_suppression) {
        $c->log->debug('destination_user_in suppression: id = ' . $destination_user_in_suppression->id . ' direction = ' . $destination_user_in_suppression->direction .
            ' mode = ' . $destination_user_in_suppression->mode . ' domain = ' . $destination_user_in_suppression->domain . ' pattern = ' . $destination_user_in_suppression->pattern);
        my @destination_user_in_details = ();
        if (_is_show_suppressions($c)) {
            push(@destination_user_in_details,_localize_detail($c,'obfuscated',$destination_user_in_suppression->label)) if 'obfuscate' eq $destination_user_in_suppression->mode;
            push(@destination_user_in_details,_localize_detail($c,'filtered',$destination_user_in_suppression->label)) if 'filter' eq $destination_user_in_suppression->mode;
        } else {
            $resource->{destination_user_in} = $destination_user_in_suppression->label;
        }
        $resource->{destination_user_in} .= ' (' . join(', ',@destination_user_in_details) . ')' if (scalar @destination_user_in_details) > 0;
    }
    return $resource;

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

sub _insert_suppressions_csv_batch {

    my ($c, $schema, $records, $chunk_size) = @_;
    NGCP::Panel::Utils::MySQL::bulk_insert(
        c => $c,
        schema => $schema,
        do_transaction => 0,
        query => "INSERT INTO billing.call_list_suppressions(domain,direction,pattern,mode,label)",
        data => $records,
        chunk_size => $chunk_size
    );

}

sub upload_suppressions_csv {

    my(%params) = @_;
    my ($c,$data,$schema) = @params{qw/c data schema/};
    my ($start, $end);

    # csv bulk upload
    my $csv = Text::CSV_XS->new({ allow_whitespace => 1, binary => 1, keep_meta_info => 1 });
    #my @cols = @{ $c->config->{lnp_csv}->{element_order} };
    my @cols = qw/domain direction pattern mode label/;

    my @fields ;
    my @fails = ();
    my $linenum = 0;
    my @suppressions = ();
    open(my $fh, '<:encoding(utf8)', $data);
    $start = time;
    my $chunk_size = 2000;
    while ( my $line = $csv->getline($fh)) {
        ++$linenum;
        unless (scalar @{ $line } == scalar @cols) {
            push @fails, $linenum;
            next;
        }
        my $row = {};
        @{$row}{@cols} = @{ $line };

        push @suppressions, [ $row->{domain}, $row->{direction}, $row->{pattern}, $row->{mode}, $row->{label} ];

        if($linenum % $chunk_size == 0) {
            _insert_suppressions_csv_batch($c, $schema, \@suppressions, $chunk_size);
            @suppressions = ();
        }
    }
    if(@suppressions) {
        _insert_suppressions_csv_batch($c, $schema, \@suppressions, $chunk_size);
    }
    $end = time;
    close $fh;
    $c->log->debug("Parsing and uploading call list suppression CSV took " . ($end - $start) . "s");

    my $text = $c->loc('Call list suppressions successfully uploaded');
    if(@fails) {
        $text .= $c->loc(", but skipped the following line numbers: ") . (join ", ", @fails);
    }

    return ( \@fails, \$text );

}

sub create_suppressions_csv {

    my(%params) = @_;
    my($c, $rs) = @params{qw/c rs/};
    $rs //= $c->stash->{rs} // $c->model('DB')->resultset('call_list_suppressions');
    #my @cols = @{ $c->config->{lnp_csv}->{element_order} };
    my @cols = qw/domain direction pattern mode label/;

    my ($start, $end);
    $start = time;
    while(my $row = $rs->next) {
        my %cuppression = $row->get_inflated_columns;
        #delete $lnp{id};
        $c->res->write_fh->write(join (",", @cuppression{@cols}) );
        $c->res->write_fh->write("\n");
    }
    $c->res->write_fh->close;
    $end = time;
    $c->log->debug("Creating call list suppression CSV for download took " . ($end - $start) . "s");
    return 1;

}

1;

# vim: set tabstop=4 expandtab:
