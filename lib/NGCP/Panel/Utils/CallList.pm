package NGCP::Panel::Utils::CallList;

use strict;
use warnings;

use JSON qw();
use POSIX qw(ceil);
use NGCP::Panel::Utils::DateTime;

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
#     * start_time
#     * status
#     * type
sub process_cdr_item {
    my ($c, $item, $owner) = @_;

    my $sub = $owner->{subscriber};
    my $cust = $owner->{customer};
    my $resource = {};

    $resource->{call_id} = $item->call_id;

    my $intra = 0;
    if($item->source_user_id && $item->source_account_id == $item->destination_account_id) {
        $resource->{intra_customer} = JSON::true;
        $intra = 1;
    } else {
        $resource->{intra_customer} = JSON::false;
        $intra = 0;
    }
    # out by default
    if(defined $sub && $sub->uuid eq $item->destination_user_id) {
        $resource->{direction} = "in";
    } elsif (defined $cust && $item->destination_account_id == $cust->id
        && ( $item->source_account_id != $cust->id || $item->destination_user_id ) ) {
        $resource->{direction} = "in";
    } else {
        $resource->{direction} = "out";
    }

    my ($src_sub, $dst_sub);
    my $billing_src_sub = $item->source_subscriber;
    my $billing_dst_sub = $item->destination_subscriber;
    if($billing_src_sub && $billing_src_sub->provisioning_voip_subscriber) {
        $src_sub = $billing_src_sub->provisioning_voip_subscriber;
    }
    if($billing_dst_sub && $billing_dst_sub->provisioning_voip_subscriber) {
        $dst_sub = $billing_dst_sub->provisioning_voip_subscriber;
    }
    my ($own_normalize, $other_normalize, $own_domain, $other_domain);
    my $other_skip_domain = 0;

    if($resource->{direction} eq "out") {
        # for pbx out calls, use extension as own cli
        if($src_sub && $src_sub->pbx_extension) {
            $resource->{own_cli} = $src_sub->pbx_extension;
        # for termianted subscribers if there is an alias field (e.g. gpp0), use this
        } elsif($item->source_account_id && $c->req->param('intra_alias_field')) {
            my $alias = $item->get_column('source_'.$c->req->param('intra_alias_field'));
            $resource->{own_cli} = $alias // $item->source_cli;
            $own_normalize = 0;
        # if there is an alias field (e.g. gpp0), use this
        } elsif($item->source_account_id && $c->req->param('alias_field')) {
            my $alias = $item->get_column('source_'.$c->req->param('alias_field'));
            $resource->{own_cli} = $alias // $item->source_cli;
            $own_normalize = 1;
        } else {
            $resource->{own_cli} = $item->source_cli;
            $own_normalize = 1;
        }
        $own_domain = $item->source_domain;

        # for intra pbx out calls, use extension as other cli
        if($intra && $dst_sub && $dst_sub->pbx_extension) {
            $resource->{other_cli} = $dst_sub->pbx_extension;
        # for termianted subscribers if there is an alias field (e.g. gpp0), use this
        } elsif($intra && $item->destination_account_id && $c->req->param('intra_alias_field')) {
            my $alias = $item->get_column('destination_'.$c->req->param('intra_alias_field'));
            $resource->{other_cli} = $alias // $item->destination_user_in;
            $other_normalize = 0;
        # if there is an alias field (e.g. gpp0), use this
        } elsif($item->destination_account_id && $c->req->param('alias_field')) {
            my $alias = $item->get_column('destination_'.$c->req->param('alias_field'));
            $resource->{other_cli} = $alias // $item->destination_user_in;
            $other_normalize = 1;
        } else {
            $resource->{other_cli} = $item->destination_user_in;
            $other_normalize = 1;
        }
        $other_domain = $item->destination_domain;
    } else {
        # for pbx in calls, use extension as own cli
        if($dst_sub && $dst_sub->pbx_extension) {
            $resource->{own_cli} = $dst_sub->pbx_extension;
        # for termianted subscribers if there is an alias field (e.g. gpp0), use this
        } elsif($item->destination_account_id && $c->req->param('intra_alias_field')) {
            my $alias = $item->get_column('destination_'.$c->req->param('intra_alias_field'));
            $resource->{own_cli} = $alias // $item->destination_user_in;
            $own_normalize = 0;
        # if there is an alias field (e.g. gpp0), use this
        } elsif($item->destination_account_id && $c->req->param('alias_field')) {
            my $alias = $item->get_column('destination_'.$c->req->param('alias_field'));
            $resource->{own_cli} = $alias // $item->destination_user_in;
            $own_normalize = 1;
        } else {
            $resource->{own_cli} = $item->destination_user_in;
            $own_normalize = 1;
        }
        $own_domain = $item->destination_domain;

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
        # for intra pbx in calls, use extension as other cli
        } elsif($intra && $src_sub && $src_sub->pbx_extension) {
            $resource->{other_cli} = $src_sub->pbx_extension;
        # for termianted subscribers if there is an alias field (e.g. gpp0), use this
        } elsif($intra && $item->source_account_id && $c->req->param('intra_alias_field')) {
            my $alias = $item->get_column('source_'.$c->req->param('intra_alias_field'));
            $resource->{other_cli} = $alias // $item->source_cli;
            $other_normalize = 0;
        # if there is an alias field (e.g. gpp0), use this
        } elsif($item->source_account_id && $c->req->param('alias_field')) {
            my $alias = $item->get_column('source_'.$c->req->param('alias_field'));
            $resource->{other_cli} = $alias // $item->source_cli;
            $other_normalize = 1;
        } else {
            $resource->{other_cli} = $item->source_cli;
            $other_normalize = 1;
        }
        $other_domain = $item->source_domain;
    }


    # for inbound calls, always show type call, even if it's
    # a call forward
    if($resource->{direction} eq "in") {
        $resource->{type} = "call";
    }

    # strip any _b2b-1 and _pbx-1 to allow grouping of calls
    $resource->{call_id} =~ s/(_b2b-1|_pbx-1)+$//g;

    my $own_sub = ($resource->{direction} eq "out")
        ? $billing_src_sub
        : $billing_dst_sub;
    if($resource->{own_cli} !~ /^\d+$/) {
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
    } elsif(!$other_skip_domain && $resource->{other_cli} !~ /^\d+$/) {
        $resource->{other_cli} .= '@'.$other_domain;
    } elsif($other_normalize) {
        if (my $normalized_cli = NGCP::Panel::Utils::Subscriber::apply_rewrite(
                c => $c, subscriber => $sub // $own_sub,
                number => $resource->{other_cli}, direction => "caller_out")) {
            $resource->{other_cli} = $normalized_cli;
        }
    }
    if ( (!($sub // $own_sub)) || (($sub // $own_sub)->status eq "terminated") ) {
        $resource->{own_cli} .= " (terminated)";
    }
    $resource->{status} = $item->call_status;
    $resource->{rating_status} = $item->rating_status;
    $resource->{type} = $item->call_type;

    $resource->{start_time} = $item->start_time;
    $resource->{duration} = NGCP::Panel::Utils::DateTime::sec_to_hms(ceil($item->duration));
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



1;

# vim: set tabstop=4 expandtab:
