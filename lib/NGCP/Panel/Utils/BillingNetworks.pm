package NGCP::Panel::Utils::BillingNetworks;
use strict;
use warnings;

#use Sipwise::Base;
#use DBIx::Class::Exception;

use NetAddr::IP;
use Data::Validate::IP qw(is_ipv4 is_ipv6);
use NGCP::Panel::Utils::IntervalTree::Simple;

use constant _CHECK_BLOCK_OVERLAPS => 1;

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
    return undef;
}

#deflate column values for search parameters doesn't work, so we need this sub
#(http://search.cpan.org/~ribasushi/DBIx-Class-0.082820/lib/DBIx/Class/Manual/FAQ.pod#Searching)
sub ip_to_bytes {
    my ($ip) = @_;
    if (_validate_ip($ip) && (my $net = NetAddr::IP->new($ip))) {
        my $bigint = $net->bigint; #force scalar context
        return (_bigint_to_bytes($bigint,$net->version == 6 ? 16 : 4),$net->version);
    }
    return (undef,undef);
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

1;