#!/usr/bin/perl

use strict;
use warnings;

use Net::Ifconfig::Wrapper;#libnet-ifconfig-wrapper-perl
use Net::Address::IP::Local;#libnet-address-ip-local-perl
use NetAddr::IP;
use Config::Tiny;
use NGCP::API::Client;
use Data::Dumper;



my $regs = {};
my( $calls_amount,$sip_server,$port,$file);
( $calls_amount, $sip_server, $port,
    @{$regs->{caller}}{qw/ip domain username password/},
    @{$regs->{callee}}{qw/ip domain username password/},
    $file) = @ARGV;

print Dumper \@ARGV;



$calls_amount //= 1;
$port //= 5060;
$file //= '/root/VMHost/ngcp-panel/sandbox/conversations_data/work/female.wav';
$regs->{callee}->{domain} //= $regs->{caller}->{domain};

{
    #register two ip's as for the real phones here subscribers are registered.
    #according to the https://lists.sipwise.com/pipermail/spce-user/2016-October/010902.html

    my $ip_base = {};
    $ip_base->{address} = Net::Address::IP::Local->public_ipv4();
    my $ip_existent = Net::Ifconfig::Wrapper::Ifconfig('list', '', '', '');
    my $ip_existent_by_addr = { map { 
        my $device = $_; 
        map { 
                $_ => { 
                    ip     => $_, 
                    device => $device, 
                    mask   => $ip_existent->{$device}->{inet}->{$_},
                    status => $ip_existent->{$device}->{status},
                } 
        } %{$ip_existent->{$device}->{inet}} 
    }  keys %$ip_existent };
    #print Dumper $ip_existent;
    #print Dumper $ip_existent_by_addr;
    #print Dumper $ip_base;
    sub register_ip{
        my($type) = @_;
        my $ip_base_obj;
        if(!defined $regs->{$type}->{ip}){
            #print Dumper [$ip_base->{address},$ip_existent_by_addr->{$ip_base->{address}}];
            #print Dumper [@{$ip_existent_by_addr->{$ip_base->{address}}}{qw/ip mask/}];
            $ip_base_obj = NetAddr::IP->new(@{$ip_existent_by_addr->{$ip_base->{address}}}{qw/ip mask/});
            $ip_base_obj++;
            if($type eq 'callee'){
                $ip_base_obj++;
            }
            $regs->{$type}->{ip} = $ip_base_obj->addr();
        }
        #print Dumper [$regs->{$type}->{ip},$ip_existent_by_addr->{$regs->{$type}->{ip}}];
        if(!exists $ip_existent_by_addr->{$regs->{$type}->{ip}}){
            #print Dumper ['+alias', 
            #    $ip_existent_by_addr->{$ip_base->{address}}->{device}, $regs->{$type}->{ip}, $ip_existent_by_addr->{$ip_base->{address}}->{mask} ];
            Net::Ifconfig::Wrapper::Ifconfig('+alias', 
                $ip_existent_by_addr->{$ip_base->{address}}->{device}, $regs->{$type}->{ip}, $ip_existent_by_addr->{$ip_base->{address}}->{mask} );
        }
    }

    register_ip('caller');
    register_ip('callee');
}


my $client = new NGCP::API::Client;
foreach my $type(qw/caller callee/){
    print Dumper ['/api/subscribers/?username='.$regs->{$type}->{username}];
    $regs->{$type}->{subscriber_id} = $client->request('GET','/api/subscribers/?username='.$regs->{$type}->{username});
    $regs->{$type}->{calls_amount} = $client->request('GET','/api/conversations/?type=call&subscriber_id='.$regs->{$type}->{subscriber_id});
    print Dumper $regs->{$type}->{subscriber_id};
    #print Dumper $regs->{$type}->{calls_amount};
    
}


