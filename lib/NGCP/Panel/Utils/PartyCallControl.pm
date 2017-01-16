package NGCP::Panel::Utils::PartyCallControl;

use Sipwise::Base;
use LWP::UserAgent;
use URI;
use JSON;

sub dispatch {
    my (%args) = @_;
    my $c = $args{c};
    my $url = $args{url};
    my $timeout = $args{timeout};
    my $id = $args{id};
    my $type = $args{type};
    my $from = $args{from};
    my $to = $args{to};
    my $text = $args{text};

    # TODO: dispatch asynchronously!
    my $ua = LWP::UserAgent->new(
            #ssl_opts => { verify_hostname => 0, SSL_verify_mode => 0 },
            timeout => $timeout,
        );
    $c->log->info("sending pcc request for $type with id $id to $url");
    my $req = HTTP::Request->new(POST => $url);
    $req->header('Content-Type' => 'application/json');
    $req->content(to_json({
        actualMsisdn => $to,
        callingMsisdn => $from,
        callid => $id,
        type => $type,
        $type eq "sms" ? (text => $text) : (),
    }));
    my $res = $ua->request($req);
    $c->log->info("sending pcc request " . ($res->is_success ? "succeeded" : "failed"));
    if ($res->is_success) {
        return 1;
    }
    return;
}

1;
