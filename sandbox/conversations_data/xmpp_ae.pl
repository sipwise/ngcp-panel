#!/usr/bin/perl
use utf8;
use AnyEvent;
use AnyEvent::XMPP::IM::Connection;
use AnyEvent::XMPP::IM::Presence;
use AnyEvent::XMPP::Util qw/split_jid/;
 
my $j = AnyEvent->condvar;
 
# Enter your credentials here
my  $cl = AnyEvent::XMPP::IM::Connection->new (
      jid              => 'sipsub2_1001@192.168.1.118',
      password         => 'sipsub2_pwd_1001',
   );
 
 # Callback functions. Their are plenty more but here I have only included some as an example
 # Also, remember that the Connection object ($con in my case), is
 # always the first argument in the call backs. This is according to the documentation.
$cl->reg_cb (
   session_ready => sub {
      my ($con, $acc) = @_;
      print "session ready\n";
 
      # Sends a message to the user specified when the session starts and is ready
      my $immsg = AnyEvent::XMPP::IM::Message->new (to => 'sipsub1_1003@192.168.1.118', body => 'Hey man, I am a bot!');
      $immsg->send ($con);
   },
   connect => sub {
      print "Connected \n";
   },
   message => sub {
      my ($con, $msg) = @_;
      if ($msg->any_body ne ""){
         my ($user, $host, $res) = split_jid ($msg->from);
         my $username = join("", $user,'@',$host);
         print "Message from " . $username . ":\n";
         print "Message: " . $msg->any_body . "\n";
         print "\n";
      }
   },
   stream_pre_authentication => sub {
      print "Pre-authentication \n";
   },
   disconnect => sub {
      my ($con, $h, $p, $reason) = @_;
      warn "Disconnected from $h:$p: $reason\n";
      $j->broadcast;
   },
   error => sub {
      my ($cl, $err) = @_;
      print "ERROR: " . $err->string . "\n";
   },
   #roster_update => sub {
   #   my ($con, $roster, $contacts) = @_;
   #   for my $contact ($roster->get_contacts) {
   #      print "Roster Update: " . $contact->jid . "\n";
   #   }
   #},
   #presence_update => sub {
   #   my ($con, $roster, $contacts, $old_presence, $new_presence) = @_;
   #   for my $cont ($contacts) {
   #      if($pres = $cont->get_priority_presence ne undef){
   #         # When user is online
   #         print "contact: " . $cont->jid . "\n";
   #         print "Presence: " . $pres . "\n";
   #         print "Status: " . $new_presence->show . "\n";
   #         print "Status Message: " . $new_presence->status . "\n";
   #
   #         if ($cont->is_on_roster ne undef){
   #            print "Is On Roster: " . $cont->is_on_roster() . "\n";
   #         }
   #      } else {
   #         # When user has logged off
   #         print $cont->jid . "\n";
   #         print "Status offline \n";
   #      }
   #   }
   #},
   message_error => sub {
      print "error";
   }
);
$cl->connect();
$j->wait;