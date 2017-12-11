use Net::SIP;
use Net::SIP::Debug '100';
use Net::SIP::Simple;
use File::Slurp qw/write_file read_file/;



# create new agent
my $ua1 = Net::SIP::Simple->new(
    outgoing_proxy => '192.168.1.117:5060',
    registrar => '192.168.1.117:5060',
    domain => '192.168.1.117',
    contact => 'sip:sipsub2_1001@192.168.1.221:50001',
    #route => '<sip:192.168.1.117>',
    from => '<sip:sipsub2_1001@192.168.1.117>',
    auth => [ 'sipsub2_1001@192.168.1.117','sipsub2_pwd_1001' ],
);
# Register agent
$ua1->register;

#my $file=read_file('/root/VMHost/data/music_on_hold.wav');
my $file='/root/VMHost/data/music_on_hold.wav';
my $rtp_done;
# Invite other party, send anncouncement once connected
my $call = $ua1->invite( 'sip:sipsub1_1002@127.0.0.1',
#      init_media => $ua1->rtp( 
#        'send_recv',
#        'announcement.pcmu-8000' ),
#      asymetric_rtp => 1,
    'init_media' => $ua1->rtp('send_recv', $file),
    'cb_rtp_done' => \$rtp_done,
    'asymetric_rtp' => 0,
    'rtp_param' => [8, 160, 160/8000, 'PCMA/8000'],
);

# Mainloop
$ua1->loop(\$rtp_done);

# Bye.
$call->bye;



