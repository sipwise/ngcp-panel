package NGCP::Panel::Utils::PartyCallControl;

use Sipwise::Base;
use LWP::UserAgent;
use URI;
use JSON;
use Encode qw/encode/;

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
    my $token = $args{token};

    my %url_ph_map = (
        caller => $from,
        callee => $to,
        callid => $id,
        token  => $token,
        prefix => $type,
        suffix => 'in',
    );

    # apply known placeholders to the url
    foreach my $v (qw(caller callee callid token prefix suffix)) {
        my $t = $url_ph_map{$v} // "";

        # only add trailing slash if not last param (suffix here)
        unless($v eq "suffix") { 
            $t .= $t ? "/" : "";
        }

        $url =~ s/(\$\{$v\})/$t/g;
    }

    # TODO: dispatch asynchronously!
    my $ua = LWP::UserAgent->new(
            #ssl_opts => { verify_hostname => 0, SSL_verify_mode => 0 },
            timeout => $timeout,
        );
    $c->log->info("sending pcc request for $type with id $id to $url");
    my $req = HTTP::Request->new(POST => $url);
    $req->header('Content-Type' => 'application/json;charset=utf-8');
    $req->content(encode('utf8', to_json({
        actualMsisdn => $to,
        callingMsisdn => $from,
        callid => $id,
        type => $type,
        token => $token,
        $type eq "sms" ? (text => $text) : (),
    })));
    my $res = $ua->request($req);
    $c->log->info("sending pcc request " . ($res->is_success ? "succeeded" : "failed"));
    if ($res->is_success) {
        return 1;
    }
    return;
}

1;
