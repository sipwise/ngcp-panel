package NGCP::Panel::Controller::InternalSms;
use NGCP::Panel::Utils::Generic qw(:all);
use Sipwise::Base;

use parent 'Catalyst::Controller';

use NGCP::Panel::Form;
use Time::Period;
use File::FnMatch qw(:fnmatch);
use Encode qw/decode/;
use UUID;

use NGCP::Panel::Utils::Preferences;
use NGCP::Panel::Utils::PartyCallControl;
use NGCP::Panel::Utils::SMS;

#sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) {
sub auto {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    #NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub list :Chained('/') :PathPart('internalsms') :CaptureArgs(0) {
    # my ($self, $c) = @_;
    return;
}

sub receive :Chained('list') :PathPart('receive') :Args(0) {
    my ($self, $c) = @_;

    my $from = $c->req->params->{from} // "";
    my $to = $c->req->params->{to} // "";
    my $text = $c->req->params->{text} // "";
    my $token = $c->req->params->{auth_token} // "";
    my $charset = $c->req->params->{charset} // "";
    my $coding = $c->req->params->{coding} // "";

    my $decoded_text = '';
    if ($charset && $charset =~ m/^utf-16/i) {
        $decoded_text = decode($charset, $text);
        $c->log->debug("decoded sms text using encoding $charset");
        $text = $decoded_text;
    }

    unless ($from && $to && $text && $token) {
        $c->log->error("Missing one param of: from (" . $c->qs($from) . "), to (" . $c->qs($to) . "), text ($text), auth_token ($token).");
        $c->detach('/denied_page');
    }

    unless ($c->config->{sms}{api_token} && $c->config->{sms}{api_token} eq $token) {
        $c->log->error("Token mismatch (sent: $token).");
        $c->detach('/denied_page');
    }

    $to =~ s/^\+//;
    $from =~ s/^\+//;
    my $now = time;

    try {
        my $schema = $c->model('DB');
        $schema->txn_do(sub {
            my $prov_dbalias = $c->model('DB')->resultset('voip_dbaliases')
                ->search_rs({
                        'me.username' => $to,
                    },{
                        join => { subscriber => 'voip_subscriber' }
                    })->first;

            unless ($prov_dbalias) {
                $c->log->warn("No corresponding subscriber for incoming number (" . $c->qs($to) . ") found.");
                $c->log->debug("from: $from, to: $to, text: $text");
                die "no_subscriber_found";
            }

            my ($pcc_uuid, $pcc_token);
            my $smsc_peer = 'default';
            UUID::generate($pcc_uuid);
            UUID::unparse($pcc_uuid, $pcc_token);

            my $smsc_peer_rs = NGCP::Panel::Utils::Preferences::get_dom_preference_rs(
                c => $c, attribute => 'smsc_peer',
                prov_domain => $prov_dbalias->domain,
            );
            if ($smsc_peer_rs && $smsc_peer_rs->first && $smsc_peer_rs->first->value) {
                $smsc_peer = $smsc_peer_rs->first->value;
            }

            my $created_item = NGCP::Panel::Utils::SMS::add_journal_record(
                c => $c,
                prov_subscriber => $prov_dbalias->subscriber,
                direction => "in",
                caller => $from,
                callee => $to,
                text => $text,
                pcc_status => "pending",
                pcc_token => $pcc_token,
                coding => $coding,
                smsc_peer => $smsc_peer,
                reason => "accepted",
                status => "received",
            );

            # check for cfs
            {

                my $cf_maps = $c->model('DB')->resultset('voip_cf_mappings')->search({
                    subscriber_id => $prov_dbalias->subscriber_id,
                    type => 'cfs'
                });
                unless($cf_maps->count) {
                    $c->log->info("No cfs for inbound sms from " . $c->qs($from) . " to " . $c->qs($to) . " found.");
                    last;
                }

                my $dset;
                foreach my $map($cf_maps->all) {
                    # check source set
                    my $source_pass = 1;
                    if($map->source_set) {
                        $source_pass = 0;
                        foreach my $source($map->source_set->voip_cf_sources->all) {
                            $c->log->debug(">>>> checking $from against ".$source->source);
                            if(fnmatch($source->source, $from)) {
                                $c->log->debug(">>>> matched $from against ".$source->source.", pass");
                                $source_pass = 1;
                                last;
                            }
                        }
                    }
                    if($source_pass) {
                        $c->log->debug(">>>> source check for $from passed, continue with time check");
                    } else {
                        $c->log->debug(">>>> source check for $from failed, trying next map entry");
                        next;
                    }

                    my $time_pass = 1;
                    if($map->time_set) {
                        $time_pass = 0;
                        foreach my $time($map->time_set->voip_cf_periods->all) {
                            my $timestring = join(' ',
                                $time->year // '',
                                $time->month // '',
                                $time->mday // '',
                                $time->wday // '',
                                $time->hour // '',
                                $time->minute // ''
                            );
                            $c->log->debug(">>>> checking $now against ".$timestring);
                            if(inPeriod($now, $timestring)) {
                                $c->log->debug(">>>> matched $now against ".$timestring.", pass");
                                $time_pass = 1;
                                last;
                            }
                        }
                    }
                    if($time_pass) {
                        $c->log->debug(">>>> time check for $now passed, use destination set");
                        $dset = $map->destination_set;
                        last;
                    } else {
                        $c->log->debug(">>>> time check for $now failed, trying next map entry");
                        next;
                    }
                }

                unless($dset) {
                    $c->log->debug(">>>> checks failed, bailing out without forwarding");
                    last;
                }

                $c->log->debug(">>>> proceed sms forwarding");

                unless($dset->voip_cf_destinations->first) {
                    $c->log->debug(">>>> detected cf mapping has no destinations in destination set");
                    last;
                }
                my $dst = $dset->voip_cf_destinations->first->destination;
                $dst =~ s/^sip:(.+)\@.+$/$1/;
                $c->log->debug(">>>> forward sms to $dst");

                my $pcc_status = "pending";
                my $fwd_item = NGCP::Panel::Utils::SMS::add_journal_record(
                    c => $c,
                    prov_subscriber => $prov_dbalias->subscriber,
                    direction => "forward",
                    caller => $to,
                    callee => $dst,
                    text => $text,
                    pcc_status => $pcc_status,
                    pcc_token => $pcc_token,
                    coding => $coding,
                    smsc_peer => $smsc_peer,
                    reason => "forwarded",
                    status => $pcc_status,
                );

                my $error_msg;
                NGCP::Panel::Utils::SMS::send_sms(
                    c => $c,
                    smsc_peer => $smsc_peer,
                    caller => $to, # use the original to as new from
                    callee => $dst,
                    text => $text,
                    coding => $coding,
                    err_code => sub {$error_msg = shift;},
                );

            }
        });
    } catch($e) {
        $c->log->error("Failed to handle received SMS message.");
        $c->log->debug($e);
    }

    $c->response->code(200);
    $c->response->body("");
    return;
}


1;

# vim: set tabstop=4 expandtab:
