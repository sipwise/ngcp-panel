package NGCP::Panel::Controller::API::SIPCapturesItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use File::Basename;
use File::Type;
use DateTime;
use DateTime::TimeZone;
use NGCP::Panel::Utils::Callflow;

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::SIPCaptures/;

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller subscriberadmin subscriber/],
    required_licenses => [qw/voisniff-mysql_dump/],
    log_response => 0,
});

sub allowed_methods {
    return [qw/GET OPTIONS HEAD/];
}

sub GET :Allow {
    my ($self, $c, $id) = @_;
    {
        my $packets = $self->packets_by_callid($c, $id);
        unless ($packets) {
            $self->error($c, HTTP_NOT_FOUND, "Non-existing call id");
            last;
        }
        my $pcap = NGCP::Panel::Utils::Callflow::generate_pcap($packets);
        last unless $pcap;

        my $dt = DateTime->now();
        my $file_dt = sprintf "%s_%s%s%s",
            $dt->ymd, $dt->hour, $dt->minute, $dt->second;
        my $filename = sprintf "%s_-%s.pcap", $file_dt, $id;

        $c->response->header("Content-Disposition" => "attachment; filename=$filename");
        $c->response->content_type('application/vnd.tcpdump.pcap');
        $c->response->body($pcap);
    }
    return;
}

1;

# vim: set tabstop=4 expandtab:
