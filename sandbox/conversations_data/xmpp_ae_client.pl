#!/usr/bin/perl
use utf8;
use AnyEvent::XMPP::Client;
use AnyEvent;
 
my $j = AnyEvent->condvar;
 
# Enter your credentials here
my  $cl = AnyEvent::XMPP::Client->new ( debug => 1 );
#$cl->add_account ($jid, $password, $host, $port, $connection_args)
$cl->add_account (
    'sipsub2_1001@192.168.1.118',
    'sipsub2_pwd_1001', 
    '192.168.1.118',
    #'5222'
);
$cl->start();
#$cl->send_message ($msg, $dest_jid, $src, $type);
$cl->send_message('qq', 'sipsub1_1003@192.168.1.118');
 $j->wait;
$cl->disconnect();