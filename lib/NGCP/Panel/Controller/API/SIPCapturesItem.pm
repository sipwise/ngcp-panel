package NGCP::Panel::Controller::API::SIPCapturesItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::ValidateJSON qw();
use File::Basename;
use File::Type;
use DateTime;
use DateTime::TimeZone;
use NGCP::Panel::Utils::Callflow;

require Catalyst::ActionRole::ACL;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::SIPCaptures/;

sub resource_name{
    return 'sipcaptures';
}

sub dispatch_path{
    return '/api/sipcaptures/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-sipcaptures';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller subscriberadmin subscriber/],
});

sub GET :Allow {
    my ($self, $c, $id) = @_;
    {
        if($c->req->param('tz') && !DateTime::TimeZone->is_valid_name($c->req->param('tz'))) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Query parameter 'tz' value is not a valid time zone");
            return;
        }

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

sub end : Private {
    my ($self, $c) = @_;

    #$self->log_response($c);
}

1;

# vim: set tabstop=4 expandtab:
