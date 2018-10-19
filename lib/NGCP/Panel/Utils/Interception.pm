package NGCP::Panel::Utils::Interception;

use warnings;
use strict;

use Data::Dumper;
use LWP::UserAgent;
use TryCatch;
use JSON;

sub request {
    my ($c, $method, $uuid, $data) = @_;

    my $a = _init($c);
    return unless($a);

    return unless($method eq 'POST' || $method eq 'PUT' || $method eq 'DELETE');

    my @agents = @{ $a->{ua} };
    my @urls = @{ $a->{url} };
    for(my $i = 0; $i < scalar(@agents); ++$i) {
        my $ua = $agents[$i];
        my $url = $urls[$i];
        if($method eq 'PUT' or $method eq 'DELETE') {
            return unless($uuid);
            $url .= '/'.$uuid;
        }
        $c->log->debug("performing $method for interception at $url");
        try {
            _request($c, $ua, $url, $method, $data);
        } catch($e) {
            # skip errors
        }
    }
    return 1;
}

sub _request {
    my ($c, $ua, $url, $method, $data) = @_;

    my $req = HTTP::Request->new($method => $url);
    if($data) {
        $req->content_type('application/json');
        $req->content(encode_json($data));
    }
    my $res = $ua->request($req);
    if($res->is_success) {
        return 1;
    } else {
        $c->log->error("Failed to do $method on $url: " . $res->status_line);
        return;
    }
}

sub _init {
    my ($c) = @_;

    my @ua = ();
    my @url = ();
    my @cfgs = ();
    if(ref $c->config->{intercept}->{agent} eq 'HASH') {
        push @cfgs, $c->config->{intercept}->{agent};
    } elsif(ref $c->config->{intercept}->{agent} eq 'ARRAY') {
        @cfgs = @{ $c->config->{intercept}->{agent} };
    }
    unless(@cfgs) {
        $c->log->error("No intercept agents configured in ngcp_panel.conf, rejecting request");
        return;
    }
    foreach my $cfg(@cfgs) {
        my $agent = LWP::UserAgent->new();
        $agent->agent("Sipwise NGCP X1/0.2");
        $agent->timeout(2);
        if($cfg->{user} && $cfg->{pass}) {
            $agent->credentials(
                $cfg->{host}.":".$cfg->{port},
                $cfg->{realm},
                $cfg->{user},
                $cfg->{pass}
            );
        }
        push @ua, $agent;
        push @url, $cfg->{schema}.'://'.$cfg->{host}.':'.$cfg->{port}.$cfg->{url};
    }
    return { ua => \@ua, url => \@url };
}

sub username_to_regexp_pattern {

    my ($c,$voip_number,$username) = @_;

    # $c is intended to use $c->config vars here.
    # vsc.clir_code is not part of the panel conf, so
    # the global conf would be required to load to get it.
    # as this is not done elsewhere in panel code yet, we leave
    # that as todo for now, and capture any vsc codes.
    my $vsc_pattern = '(\*\d+\*)?';
    #my $vsc_pattern = '(\*31\*)?';

    my @pattern_elements = ();
    # longest to shortest:

    #1. the sip username itself:
    push(@pattern_elements,$vsc_pattern . quotemeta($username));
    #2. "international format": concat(concat('00',cc),ac,sn):
    push(@pattern_elements,$vsc_pattern . '00' . $voip_number->cc . $voip_number->ac . $voip_number->sn);
    #3. "e164 format": concat(cc,ac,sn):
    push(@pattern_elements,$vsc_pattern . $voip_number->cc . $voip_number->ac . $voip_number->sn);
    #4. "local format": concat(concat('0',ac),sn):
    push(@pattern_elements,$vsc_pattern . '0' . $voip_number->ac . $voip_number->sn);

    return '^(' . join('|',@pattern_elements) . ')$';

}

sub subresnum_from_number {
    my ($c, $number, $err_code) = @_;
    if (!defined $err_code || ref $err_code ne 'CODE') {
        $err_code = sub { return 0; };
    }
    my $num_rs = $c->model('DB')->resultset('voip_numbers')->search(
        \[ 'concat(cc,ac,sn) = ?', [ {} => $number ]]
    );
    unless($num_rs->first) {
        return 0 unless &{$err_code}("invalid number '$number'",'number',"Number does not exist");
    }
    my $sub = $num_rs->first->subscriber;
    unless($sub) {
        return 0 unless &{$err_code}("invalid number '$number', not assigned to any subscriber",'number',"Number is not active");
    }

    my $res = $num_rs->first->reseller;
    unless($res) {
        # with ossbss provisioning, reseller is not set on number,
        # so take the long way here
        $res = $sub->contract->contact->reseller;
        unless($res) {
            return 0 unless &{$err_code}("invalid number '$number', not assigned to any reseller",'number',"Number is not active");
        }
    }

    return ($sub, $res, $num_rs->first);
}

1;
