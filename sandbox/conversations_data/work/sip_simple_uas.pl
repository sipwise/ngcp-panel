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



