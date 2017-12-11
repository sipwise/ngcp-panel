use Net::SIP;
use Net::SIP::Debug '100';

# create new agent
my $ua1 = Net::SIP::Simple->new(
    outgoing_proxy => '127.0.0.1:5060',
    registrar => '192.168.1.117:5060',
    domain => 'voip.sip',
    contact => 'sip:sipsub_1001@voip.sip:50001',
    #route => '192.168.1.117:5060',
    from => 'sipsub_1001',
    auth => [ 'sipsub_1001','sipsub_pwd_1001' ],
);
my $ua2 = Net::SIP::Simple->new(
    outgoing_proxy => '127.0.0.1:5060',
    registrar => '192.168.1.117:5060',
    domain => 'voip.sip',
    contact => 'sip:sipsub_1002@voip.sip:50002',
    #route => '192.168.1.117:5060',
    from => 'sipsub_1002',
    auth => [ 'sipsub_1002','sipsub_pwd_1002' ],
);
# Register agent
$ua1->register;
$ua2->register;

# Invite other party, send anncouncement once connected
$ua1->invite( 'sip:sipsub_1002@voip.sip:50002',
      init_media => $ua1->rtp( 
        'send_recv',
        'announcement.pcmu-8000' ),
      asymetric_rtp => 1,
);

# Mainloop
#$ua1->loop;
#$ua2->loop;
