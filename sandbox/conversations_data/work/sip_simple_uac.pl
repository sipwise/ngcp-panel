use Net::SIP;
#use Net::SIP::Debug '50';
use Net::SIP::Simple;

my ($sip_server,$port,$ip,$domain,$username,$password,$callee,$file) = @_;

$port ||= 5060;
$file ||='./female.wav';

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

my $rtp_done;
my $call_done;
# Invite other party, send anncouncement once connected
my $call = $uac->invite( $callee,
    'init_media' => $uac->rtp( 'send_recv', $file),
    'cb_rtp_done' => sub { print "rtp_done;\n"; $rtp_done = 1; },,
    'asymetric_rtp' => 0,
    'rtp_param' => [8, 160, 160/8000, 'PCMA/8000'],

);
# Mainloop
$call->loop( \$call_done, 120 );
# Bye.
$call->bye( cb_final => \$call_done );
