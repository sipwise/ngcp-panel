package NGCP::Panel::Utils::BillingNetworks;
use strict;
use warnings;

#use Sipwise::Base;
#use DBIx::Class::Exception;

use NetAddr::IP;
use Data::Validate::IP qw(is_ipv4 is_ipv6);
use NGCP::Panel::Utils::IntervalTree::Simple;

use constant _CHECK_BLOCK_OVERLAPS => 1;

sub check_network_update_item {
    my ($c,$new_resource,$old_item,$err_code) = @_;

    return 1 unless $old_item;

    if (!defined $err_code || ref $err_code ne 'CODE') {
        $err_code = sub { return 0; };
    }

    if ($old_item->status eq 'terminated') {
        return 0 unless &{$err_code}("Billing network is already terminated and cannot be changed.",'status');
    }

    #my $contract_cnt = $old_item->get_column('contract_cnt');
    #my $package_cnt = $old_item->get_column('package_cnt');

    return 1;

}

sub set_blocks_from_to {
    my ($blocks,$err_code) = @_;
    my $intersecter = (_CHECK_BLOCK_OVERLAPS ? NGCP::Panel::Utils::IntervalTree::Simple->new() : undef);
    my $version;
    if (!defined $err_code || ref $err_code ne 'CODE') {
        $err_code = sub { return 0; };
    }
    if ((scalar @$blocks) == 0) {
        return &{$err_code}('At least one block definition is required');
    }
    foreach my $block (@$blocks) {
        if (my $err = _set_ip_net_from_to($block)) {
            return 0 unless &{$err_code}($err);
        } else {
            if ((defined $version && $version == 4 && $block->{_version} != 4) ||
                (defined $version && $version == 6 && $block->{_version} != 6)) {
                return &{$err_code}('Ipv4 and ipv6 must not be mixed in block definitions');
            }
            $version //= $block->{_version};
            if (defined $intersecter) {
                my $to = $block->{_to}->copy->badd(1); #right open intervals
                my $overlaps_with = $intersecter->find($block->{_from},$to);
                if ((scalar @$overlaps_with) > 0) {
                    return 0 unless &{$err_code}("Block '$block->{_label}' overlaps with block(s) '" . join("', '",@$overlaps_with) . "'");
                } else {
                    $intersecter->insert($block->{_from},$to,$block->{_label});
                }
            }
            delete $block->{_from};
            delete $block->{_to};
            delete $block->{_version};
            delete $block->{_label};
        }
    }
    return 1;
}

sub _set_ip_net_from_to {
    my ($resource) = @_;
    return "Invalid IP address '$resource->{ip}'" unless _validate_ip($resource->{ip});
    my $net = NetAddr::IP->new($resource->{ip} . (defined $resource->{mask} ? '/' . $resource->{mask} : ''));
    if (!defined $net || (defined $resource->{mask} && $net->masklen != $resource->{mask})) {
      return "Invalid mask '$resource->{mask}'";
    }
    $resource->{_label} = $net->cidr;
    #force scalar context:
    my $from = $net->network->bigint; #first->bigint;
    my $to = $net->broadcast->bigint; #last->bigint;
    #if (NetAddr::IP::Util::hasbits($net->{mask} ^ _CIDR127)) { #other than point-to-point
    #  $from->bsub(1); #include network addr
    #  $to->badd(1); #include broadcast addr
    #}
    ($resource->{_from},$resource->{_to},$resource->{_version}) = ($from,$to,$net->version);
    #whatever format we want to save:
    if ($resource->{_version} == 4) {
        $resource->{_ipv4_net_from} = $from;
        $resource->{_ipv4_net_to} = $to;
        $resource->{_ipv6_net_from} = undef;
        $resource->{_ipv6_net_to} = undef;
    } elsif ($resource->{_version} == 6) {
        $resource->{_ipv4_net_from} = undef;
        $resource->{_ipv4_net_to} = undef;
        $resource->{_ipv6_net_from} = $from;
        $resource->{_ipv6_net_to} = $to;
    }
    return;
}

#deflate column values for search parameters doesn't work, so we need this sub
#(http://search.cpan.org/~ribasushi/DBIx-Class-0.082820/lib/DBIx/Class/Manual/FAQ.pod#Searching)
sub _ip_to_bytes {
    my ($ip) = @_;
    if (_validate_ip($ip) && (my $net = NetAddr::IP->new($ip))) {
        my $bigint = $net->bigint; #force scalar context
        return (_bigint_to_bytes($bigint,$net->version == 6 ? 16 : 4),$net->version);
    }
    return (undef,undef);
}

sub prepare_query_param_value {
    my ($q) = @_;
    return _prepare_query_param_value($q);
}

sub _prepare_query_param_value {
    my ($q,$v) = @_;
    my ($bytes,$version) = _ip_to_bytes($q);
    if (defined $v) {
        # really complex interaction
        ## no critic (ProhibitExplicitReturnUndef)
        return undef if (!defined $bytes || $v != $version);
        return $bytes;
    } else {
        return {} unless defined $bytes;
        return {
            'billing_network_blocks._ipv4_net_from' => { '<=', $bytes },
            'billing_network_blocks._ipv4_net_to'  => { '>=', $bytes },
        } if $version == 4;
        return {
            'billing_network_blocks._ipv6_net_from' => { '<=', $bytes },
            'billing_network_blocks._ipv6_net_to'  => { '>=', $bytes },
        } if $version == 6;
    }
}

sub _bigint_to_bytes {
    my ($bigint,$size) = @_;
    #print '>'.sprintf('%0' . 2 * $size . 's',substr($bigint->as_hex(),2)) . "\n";
    return pack('C' x $size, map { hex($_) } (sprintf('%0' . 2 * $size . 's',substr($bigint->as_hex(),2)) =~ /(..)/g));
    #print '>' . join('',map { sprintf('%02x',$_) } unpack('C' x $size, $data)) . "\n";
    #return $data;
}

sub _validate_ip {
    my ($ip) = @_;
    return (is_ipv4($ip) || is_ipv6($ip));
}

sub get_contract_exists_stmt {

    return <<EOS;
select
  1
from billing.contracts_billing_profile_network_schedule cbpns
join billing.contracts_billing_profile_network cbpn on cbpns.profile_network_id = cbpn.id
join billing._v_actual_effective_start_time est on est.contract_id = cbpn.contract_id and cbpns.effective_start_time = est.effective_start_time
join billing.contracts as c on est.contract_id = c.id
where
cbpn.billing_network_id = me.id
and c.status != 'terminated'
limit 1
EOS

}

sub get_contract_count_stmt {

    my $count_limit = shift;
    if (defined $count_limit and $count_limit > 0) {
        $count_limit = $count_limit + 1;
    } else {
        $count_limit = -1;
    }
    
    return <<EOS;
billing.get_billing_network_contract_cnt(me.id,$count_limit)
EOS

}

sub get_package_count_stmt {

    return <<EOS;
select
  count(distinct pp.id)
from `billing`.`package_profile_sets` pps
join `billing`.`profile_packages` pp on pp.id = pps.package_id
where pps.`network_id` = `me`.`id`
EOS

# and pp.status != 'terminated'";
}

sub get_datatable_cols {

    my ($c) = @_;
    my $grp_stmt = "group_concat(if(`billing_network_blocks`.`mask` is null,`billing_network_blocks`.`ip`,concat(`billing_network_blocks`.`ip`,'/',`billing_network_blocks`.`mask`)) separator ', ')";
    my $grp_len = 30;
    return (
        { name => "contract_cnt", "search" => 0, "title" => $c->loc("Used (contracts)"),
          custom_renderer => 'function ( data, type, full, opt ) { if(full.contract_cnt > 1000){return \'1000+\'}return full.contract_cnt; }' },
        { name => "package_cnt", "search" => 0, "title" => $c->loc("Used (packages)"), },
        { name => 'blocks_grp', accessor => "blocks_grp", search => 0, title => $c->loc('Network Blocks'), literal_sql =>
          "if(length(".$grp_stmt.") > ".$grp_len.", concat(left(".$grp_stmt.", ".$grp_len."), '...'), ".$grp_stmt.")" },
        { name => "billing_network_blocks._ipv4_net_from", search_lower_column => 'ipv4', convert_code => sub {
            return _prepare_query_param_value(shift,4);
            } },
        { name => "billing_network_blocks._ipv4_net_to", search_upper_column => 'ipv4', convert_code => sub {
            return _prepare_query_param_value(shift,4);
            } },
        { name => "billing_network_blocks._ipv6_net_from", search_lower_column => 'ipv6', convert_code => sub {
            return _prepare_query_param_value(shift,6);
            } },
        { name => "billing_network_blocks._ipv6_net_to", search_upper_column => 'ipv6', convert_code => sub {
            return _prepare_query_param_value(shift,6);
            } },
    );

}

1;