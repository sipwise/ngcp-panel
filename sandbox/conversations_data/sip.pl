#!/usr/bin/perl

use strict;
use warnings;
use Data::Dumper;

use NGCP::API::Client;
use JSON;

use Net::Ifconfig::Wrapper;#libnet-ifconfig-wrapper-perl
use Net::Address::IP::Local;#libnet-address-ip-local-perl
use NetAddr::IP;

#use Parallel::ForkManager;
#use Config::Tiny;
use threads;
use Net::SIP::Simple;
use Net::SIP::Simple::Call;


my $REGS = {};
my( $CALLS_AMOUNT,$SIP_SERVER,$PORT,$FILE);
( $CALLS_AMOUNT, $SIP_SERVER, $PORT,
    @{$REGS->{caller}}{qw/ip domain username password/},
    @{$REGS->{callee}}{qw/ip domain username password/},
    $FILE) = @ARGV;

print Dumper \@ARGV;

my $api_client = new NGCP::API::Client;


$CALLS_AMOUNT //= 1;
$PORT //= 5060;
$FILE //= '/root/VMHost/ngcp-panel/sandbox/conversations_data/work/female.wav';
$REGS->{callee}->{domain} //= $REGS->{caller}->{domain};

register_ips();

get_calls_amount();

my $thread_uas = threads->create(\&sip_uas, $SIP_SERVER, $PORT, @{$REGS->{callee}}{qw/ip domain username password/} );
my $thread_uac = threads->create(\&sip_uac, $CALLS_AMOUNT, $SIP_SERVER, $PORT, @{$REGS->{caller}}{qw/ip domain username password/}, join('@', @{$REGS->{callee}}{qw/username domain/}), $FILE );

while ($REGS->{caller}->{calls_amount} < ($CALLS_AMOUNT + $REGS->{caller}->{calls_amount_initial})){
    sleep 5;
    get_calls_amount();
}

$thread_uas->join();
$thread_uac->join();


##########--------------------- aux
sub get_calls_amount{
    foreach my $type(qw/caller callee/){
        print Dumper ['/api/subscribers/?username='.$REGS->{$type}->{username}];
        my $res;
        if(!$REGS->{$type}->{subscriber_id} ){
            $res = $api_client->request('GET','/api/subscribers/?username='.$REGS->{$type}->{username});
        $REGS->{$type}->{subscriber_id} //= $res->as_hash()->{_embedded}->{'ngcp:subscribers'}->[0]->{id};
        }
        print Dumper ['/api/conversations/?type=call&subscriber_id='.$REGS->{$type}->{subscriber_id}];
        $res = $api_client->request('GET','/api/conversations/?type=call&subscriber_id='.$REGS->{$type}->{subscriber_id});
        #print Dumper [$res->content()];
        my $json = JSON->new->allow_nonref;
        my $res_hash = $json->decode($res->content());
        $REGS->{$type}->{calls_amount} = $res_hash->{total_count};
        $REGS->{$type}->{calls_amount_initial} //= $REGS->{$type}->{calls_amount};
        print Dumper $REGS;
    }
}
sub sip_uas{
    my ($sip_server,$port,$ip,$domain,$username,$password) = @_;

    $port ||= 5060;
    my %params = (
        outgoing_proxy => $sip_server.':'.$port,
        registrar => $sip_server.':'.$port,
        domain => $domain,
        contact => 'sip:'.$username.'@'.$ip.':50002',
        from => '<sip:'.$username.'@'.$domain.'>',
        auth => [ $username.'@'.$domain,$password ],
    );
    print Dumper ['sip_uas', \%params];
    my $uas = Net::SIP::Simple->new(%params);
    $uas->register;
    my(@received,$call_ended);
    my $save_rtp = sub {
        my $buf = shift;
        push @received,$buf;
        #warn substr( $buf,0,10)."\n";
    };
    $uas->listen( 
        cb_cleanup => sub { print "call_ended;\n"; $call_ended = 1; },
        init_media => $uas->rtp( 'recv_echo', $save_rtp ),
    );
    $uas->loop($call_ended);
}

sub sip_uac{
    my ($calls_amount,$sip_server,$port,$ip,$domain,$username,$password,$callee,$file) = @_;

    $port ||= 5060;
    $file ||='./female.wav';
    sleep 5;
    my %params = (
        outgoing_proxy => $sip_server.':'.$port,
        registrar => $sip_server.':'.$port,
        domain => $domain,
        contact => 'sip:'.$username.'@'.$ip.':50002',
        from => '<sip:'.$username.'@'.$domain.'>',
        auth => [ $username.'@'.$domain,$password ],
    );
    print Dumper ['sip_uac', \%params];
    my $uac = Net::SIP::Simple->new(
        outgoing_proxy => $sip_server.':'.$port,
        registrar => $sip_server.':'.$port,
        domain => $domain,
        contact => 'sip:'.$username.'@'.$ip.':50002',
        from => '<sip:'.$username.'@'.$domain.'>',
        auth => [ $username.'@'.$domain,$password ],
    );

    # Register agent
    $uac->register;
    for(my $i=0; $i < $calls_amount; $i++){
        my $rtp_done;
        my $call_done;
        # Invite other party, send anncouncement once connected
        my %call_params = (
            'init_media' => $uac->rtp( 'send_recv', $file),
            'cb_rtp_done' => sub { print "rtp_done;\n"; $rtp_done = 1; },,
            'asymetric_rtp' => 0,
            'rtp_param' => [8, 160, 160/8000, 'PCMA/8000'],
        );
        print Dumper ['sip_uac', $callee, \%call_params];
        my $call = $uac->invite( 
            $callee, %call_params
        );
        ## Mainloop
        #my $call = $uac->invite( 
        #    'sip:sipsub1_1003@192.168.1.118',
        #    %call_params
        #);
        
        # Mainloop
        $call->loop( \$rtp_done, 120 );
        $call->bye( cb_final => \$call_done );
        $call->loop( \$call_done, 120 );
        
        # Bye.
        $call->bye;
    }
}

sub register_ips{
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

    register_type_ip('caller',$ip_base,$ip_existent_by_addr);
    register_type_ip('callee',$ip_base,$ip_existent_by_addr);
}
sub register_type_ip{
    my($type,$ip_base,$ip_existent_by_addr) = @_;
    #print Dumper \@_;

    my $ip_base_obj;
    if(!$REGS->{$type}->{ip}){
        #print Dumper [$ip_base->{address},$ip_existent_by_addr->{$ip_base->{address}}];
        #print Dumper [@{$ip_existent_by_addr->{$ip_base->{address}}}{qw/ip mask/}];
        $ip_base_obj = NetAddr::IP->new(@{$ip_existent_by_addr->{$ip_base->{address}}}{qw/ip mask/});
        $ip_base_obj = $ip_base_obj+10;
        if($type eq 'callee'){
            $ip_base_obj = $ip_base_obj+10;
        }
        $REGS->{$type}->{ip} = $ip_base_obj->addr();
    }
    #print Dumper ['ip',$type,$REGS->{$type}->{ip},$ip_existent_by_addr->{$REGS->{$type}->{ip}}];
    if(!exists $ip_existent_by_addr->{$REGS->{$type}->{ip}}){
        #print Dumper ['+alias', 
        #    $ip_existent_by_addr->{$ip_base->{address}}->{device}, $REGS->{$type}->{ip}, $ip_existent_by_addr->{$ip_base->{address}}->{mask} ];
        Net::Ifconfig::Wrapper::Ifconfig('+alias', 
            $ip_existent_by_addr->{$ip_base->{address}}->{device}, $REGS->{$type}->{ip}, $ip_existent_by_addr->{$ip_base->{address}}->{mask} );
    }
}

