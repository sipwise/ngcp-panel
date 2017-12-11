#!/usr/bin/perl

use strict;
use warnings;
use Data::Dumper;

use NGCP::API::Client;
use JSON;

#use Parallel::ForkManager;
#use Config::Tiny;
use threads;

use Net::Ifconfig::Wrapper;#libnet-ifconfig-wrapper-perl
use Net::Address::IP::Local;#libnet-address-ip-local-perl
use NetAddr::IP;
use Net::SIP::Simple;
use Net::SIP::Simple::Call;

use AnyEvent;
use AnyEvent::XMPP::Client;

my $REGS = {};
my( $TYPE, $ITEM_AMOUNT,$ITEM_SERVER,$PORT,$FILE);
( $TYPE, $ITEM_AMOUNT, $ITEM_SERVER, $PORT,
    @{$REGS->{caller}}{qw/ip domain username password/},
    @{$REGS->{callee}}{qw/ip domain username password/},
    $FILE) = @ARGV;

print Dumper \@ARGV;

my $api_client = new NGCP::API::Client;


$ITEM_AMOUNT //= 1;
$PORT //= 5060;
$REGS->{callee}->{domain} //= $REGS->{caller}->{domain};
$FILE //= '';
('voicemail' eq $TYPE) 
    and ($FILE ||= '/root/VMHost/ngcp-panel/sandbox/conversations_data/work/female.wav');

get_items_amount();
my ($thread_uas, $thread_uac);
if( 'call' eq $TYPE || 'voicemail' eq $TYPE ){
    register_ips();
    $thread_uas = threads->create(\&sip_uas, $ITEM_SERVER, $PORT, @{$REGS->{callee}}{qw/ip domain username password/}, $FILE );
    $thread_uac = threads->create(\&sip_uac, $ITEM_AMOUNT, $ITEM_SERVER, $PORT, @{$REGS->{caller}}{qw/ip domain username password/}, join('@', @{$REGS->{callee}}{qw/username domain/}), $FILE );
}elsif( 'xmpp' eq $TYPE ){
    $thread_uac = threads->create(\&xmpp_uac, $ITEM_AMOUNT, $ITEM_SERVER, $PORT, @{$REGS->{caller}}{qw/domain username password/}, @{$REGS->{callee}}{qw/domain username password/}, );
}
while ((
        $REGS->{caller}->{items_amount} < ($ITEM_AMOUNT + $REGS->{caller}->{items_amount_initial})
    ) && (
        $REGS->{callee}->{items_amount} < ($ITEM_AMOUNT + $REGS->{callee}->{items_amount_initial})
    )
){
    sleep 3;
    get_items_amount();
}
$thread_uas and $thread_uas->kill('KILL')->detach();
$thread_uac and $thread_uac->kill('KILL')->detach();



##########--------------------- aux
sub get_items_amount{
    foreach my $type(qw/caller callee/){
        #print Dumper ['/api/subscribers/?username='.$REGS->{$type}->{username}];
        my $res;
        if(!$REGS->{$type}->{subscriber_id} ){
            $res = $api_client->request('GET','/api/subscribers/?username='.$REGS->{$type}->{username});
        $REGS->{$type}->{subscriber_id} //= $res->as_hash()->{_embedded}->{'ngcp:subscribers'}->[0]->{id};
        }
        #print Dumper ['/api/conversations/?type='.$TYPE.'&subscriber_id='.$REGS->{$type}->{subscriber_id}];
        $res = $api_client->request('GET','/api/conversations/?type='.$TYPE.'&subscriber_id='.$REGS->{$type}->{subscriber_id});
        #print Dumper [$res->content()];
        my $json = JSON->new->allow_nonref;
        my $res_hash = $json->decode($res->content());
        $REGS->{$type}->{items_amount} = $res_hash->{total_count};
        $REGS->{$type}->{items_amount_initial} //= $REGS->{$type}->{items_amount};
        print Dumper $REGS;
    }
}

sub xmpp_uac{
    my($amount,$server,$port,$caller_domain,$caller_username,$caller_password,$callee_domain,$callee_username) = @_;
    $SIG{'KILL'} = sub { threads->exit(); };
    $port //= 5222;
    $caller_domain //= $server;
    $callee_domain //= $server;
    my $j = AnyEvent->condvar;
    my $cl = AnyEvent::XMPP::Client->new ();#debug => 1
    $cl->add_account ($caller_username.'@'.$caller_domain, $caller_password );
    $cl->reg_cb (
        session_ready => sub {
            my ($cl, $acc) = @_;
            print "xmpp: session ready\n";
            for(my $i=0; $i < $amount; $i++){
                $cl->send_message (
                    "Test message created at ".time() => $caller_username.'@'.$caller_domain, 
                    undef, 'chat'
                );
            }
        },
        disconnect => sub {
            my ($cl, $acc, $h, $p, $reas) = @_;
            print "xmpp: disconnect ($h:$p): $reas\n";
            $j->broadcast;
        },
        error => sub {
            my ($cl, $acc, $err) = @_;
            print "ERROR: xmpp: " . $err->string . "\n";
        },
    );
    $cl->start;
    $j->wait;
}


sub sip_uas{
    my ($sip_server,$port,$ip,$domain,$username,$password,$file) = @_;
    $SIG{'KILL'} = sub { threads->exit(); };
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
        #my $buf = shift;
        #push @received,$buf;
        #warn substr( $buf,0,10)."\n";
    };
    my %listen_params = (
        cb_cleanup => sub { print "call_ended;\n"; $call_ended = 1; },
        $file ? (init_media => $uas->rtp( 'recv_echo', $save_rtp )) : (),
    );
    print Dumper ['sip_uas', \%listen_params];
    $uas->listen( %listen_params );
    $uas->loop($call_ended);
}

sub sip_uac{
    my ($items_amount,$sip_server,$port,$ip,$domain,$username,$password,$callee,$file) = @_;

    $SIG{'KILL'} = sub { threads->exit(); };

    $port ||= 5060;
    sleep 3;
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
        %params
    );

    # Register agent
    $uac->register;
    for(my $i=0; $i < $items_amount; $i++){
        my $rtp_done;
        my $call_done;
        # Invite other party, send anncouncement once connected
        my %call_params = (
            $file ? (
                'init_media' => $uac->rtp( 'send_recv', $file),
                'cb_rtp_done' => sub { print "rtp_done;\n"; $rtp_done = 1; },,
                'asymetric_rtp' => 0,
                'rtp_param' => [8, 160, 160/8000, 'PCMA/8000'],
            ) : ()
        );
        if($callee !~/^sip:/){
            $callee = 'sip:'.$callee;
        }
        print Dumper ['sip_uac', $callee, \%call_params];
        my $call = $uac->invite( 
            $callee, %call_params
        );

        # Mainloop
        if($file){
            $call->loop( \$rtp_done, 120 );
        }
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

