#!/opt/perl/bin/perl
use strict;
use utf8;
use AnyEvent;
use AnyEvent::XMPP::Client;

my $j = AnyEvent->condvar;
my $cl = AnyEvent::XMPP::Client->new ();#debug => 1
$cl->add_account ('sipsub2_1001@192.168.1.118', 'sipsub2_pwd_1001');
$cl->reg_cb (
    session_ready => sub {
        my ($cl, $acc) = @_;
        print "session ready\n";
        $cl->send_message (
           "Hi! I'm too lazy to adjust examples!" => 'sipsub1_1003@192.168.1.118', undef, 'chat'
        );
        #$j->send;
        #$cl->disconnect;
   },
   disconnect => sub {
        my ($cl, $acc, $h, $p, $reas) = @_;
        print "disconnect ($h:$p): $reas\n";
        $j->broadcast;
   },
   error => sub {
        my ($cl, $acc, $err) = @_;
        print "ERROR: " . $err->string . "\n";
   },
   message => sub {
        my ($cl, $acc, $msg) = @_;
        print "message from: " . $msg->from . ": " . $msg->any_body . "\n";
   }
);
$cl->start;
$j->wait;