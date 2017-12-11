use Net::SIP;
use Net::SIP::Debug '100';
use Net::SIP::Simple;
use File::Slurp qw/write_file read_file/;



my $ua2 = Net::SIP::Simple->new(
    outgoing_proxy => '192.168.1.117:5060',
    registrar => '192.168.1.117:5060',
    domain => '127.0.0.1',
    contact => 'sip:sipsub1_1002@192.168.1.222:50002',
    route => '<sip:192.168.1.117>',
    from => '<sip:sipsub1_1002@127.0.0.1>',
    auth => [ 'sipsub1_1002@127.0.0.1','sipsub1_pwd_1002' ],
);
$ua2->register;
$ua2->listen();
$ua2->loop;


