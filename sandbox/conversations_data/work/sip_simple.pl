use Net::SIP;
#use Net::SIP::Debug '50';
use Net::SIP::Simple;
use File::Slurp qw/write_file read_file/;
use Data::Dumper;
my $pid = fork;

if (!defined $pid) {
    die "Cannot fork: $!";
}elsif ($pid == 0) {
    my %params = (
        outgoing_proxy => '192.168.1.118:5060',
        registrar => '192.168.1.118:5060',
        domain => '192.168.1.118',
        contact => 'sip:sipsub1_1003@192.168.1.222:50002',
        #route => '<sip:192.168.1.118>',
        from => '<sip:sipsub1_1003@192.168.1.118>',
        auth => [ 'sipsub1_1003@192.168.1.118','sipsub1_pwd_1003' ],
    );
    print Dumper ['uas',\%params];
    my $ua2 = Net::SIP::Simple->new(
        %params
    );
    #$ua2->register;
    my $call_ended;
    my @received;
    my $save_rtp = sub {
        my $buf = shift;
        push @received,$buf;
        #warn substr( $buf,0,10)."\n";
    };
    $ua2->listen( 
        cb_cleanup => sub { print "call_ended;\n";$call_ended = 1; },
        init_media => $ua2->rtp( 'recv_echo', $save_rtp ),
    );
    $ua2->loop($call_ended);
    #$ua2->loop(40);
    write_file('/tmp/rtp.wav',join('',@received));
    exit(0);
}else {
    # create new agent
    sleep 5;
    my %params = (
        outgoing_proxy => '192.168.1.118:5060',
        registrar => '192.168.1.118:5060',
        domain => '192.168.1.118',
        contact => 'sip:sipsub2_1001@192.168.1.221:50001',
        from => '<sip:sipsub2_1001@192.168.1.118>',
        auth => [ 'sipsub2_1001@192.168.1.118','sipsub2_pwd_1001' ],
    );
    print Dumper ['uac',\%params];
    my $ua1 = Net::SIP::Simple->new(
        %params
    );
    # Register agent
    $ua1->register;
    
    my $file='/root/VMHost/ngcp-panel/sandbox/conversations_data/work/female.wav';
    my $rtp_done;
    my $call_done;
    # Invite other party, send anncouncement once connected
    my %call_params = (
        'init_media' => $ua1->rtp( 'send_recv', $file),
        'cb_rtp_done' => sub { print "rtp_done;\n"; $rtp_done = 1; },,
        'asymetric_rtp' => 0,
        'rtp_param' => [8, 160, 160/8000, 'PCMA/8000'],    
    );
    print Dumper ['uac call','sip:sipsub1_1003@192.168.1.118',\%call_params];
    my $call = $ua1->invite( 
        'sip:sipsub1_1003@192.168.1.118',
        %call_params
    );
    
    # Mainloop
    $call->loop( \$rtp_done, 120 );
    $call->bye( cb_final => \$call_done );
    $call->loop( \$call_done, 120 );
    
    # Bye.
    $call->bye;
    1 while waitpid(-1, WNOHANG) > 0;
}


