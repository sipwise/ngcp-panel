use Net::SIP;
#use Net::SIP::Debug '50';
use Net::SIP::Simple;

my ($sip_server,$port,$ip,$domain,$username,$password) = @_;

$port ||= 5060;

my $uas = Net::SIP::Simple->new(
    outgoing_proxy => $sip_server.':'.$port,
    registrar => $sip_server.':'.$port,
    domain => $domain,
    contact => 'sip:'.$username.'@'.$ip.':50002',
    from => '<sip:'.$username.'@'.$domain.'>',
    auth => [ $username.'@'.$domain,$password ],
);
#$uas->register;
my $call_ended;
$uas->listen( 
    cb_cleanup => sub { print "call_ended;\n";$call_ended = 1; },
);
$uas->loop($call_ended);
}else {
    # create new agent
    sleep 5;
    my $ua1 = Net::SIP::Simple->new(
        outgoing_proxy => '192.168.1.118:5060',
        registrar => '192.168.1.118:5060',
        domain => '192.168.1.118',
        contact => 'sip:sipsub2_1001@192.168.1.221:50001',
        from => '<sip:sipsub2_1001@192.168.1.118>',
        auth => [ 'sipsub2_1001@192.168.1.118','sipsub2_pwd_1001' ],
    );
    # Register agent
    $ua1->register;
    
    my $file='/root/VMHost/ngcp-panel/sandbox/conversations_data/work/female.wav';
    my $rtp_done;
    my $call_done;
    # Invite other party, send anncouncement once connected
    my $call = $ua1->invite( 'sip:sipsub1_1003@192.168.1.118',
        'init_media' => $ua1->rtp( 'send_recv', $file),
        'cb_rtp_done' => sub { print "rtp_done;\n"; $rtp_done = 1; },,
        'asymetric_rtp' => 0,
        'rtp_param' => [8, 160, 160/8000, 'PCMA/8000'],

    );
    
    # Mainloop
    $call->loop( \$rtp_done, 120 );
    $call->bye( cb_final => \$call_done );
    $call->loop( \$call_done, 120 );
    
    # Bye.
    $call->bye;
    1 while waitpid(-1, WNOHANG) > 0;
}


