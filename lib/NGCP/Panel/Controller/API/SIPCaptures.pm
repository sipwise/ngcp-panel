package NGCP::Panel::Controller::API::SIPCaptures;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use DateTime::TimeZone;
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Callflow;


sub allowed_methods{
    return [qw/GET OPTIONS/];
}

sub api_description {
    return 'Defines SIP packet captures for a call. A GET on an item returns a pcap data as application/vnd.tcpdump.pcap. A valid call-id or start_le+start_ge is required as a query parameter.';
};

sub query_params {
    return [
		{
            param => 'call_id',
            description => 'Filter for a particular call_id',
            query => {
                first => sub {
                    my $q = shift;
                    {
                       'message.call_id' => $q,
                    };
                },
                second => sub {
					{
						 join => { message_packets => 'message' },
					};
				},
            },
		},
        {
            param => 'start_ge',
            description => 'Filter for data starting greater or equal the specified time stamp.',
            query => {
                first => sub {
                    my $q = shift;
                    my $dt = NGCP::Panel::Utils::DateTime::from_string($q);
					open(my $fh, ">>/tmp/x.out");
					print $fh "start_ge: ".$dt->epoch."\n";
					close $fh;
                    { 'me.timestamp' => { '>=' => $dt->epoch } };
                },
                second => sub {},
            },
        },
        {
            param => 'start_le',
            description => 'Filter for data starting lower or equal the specified time stamp.',
            query => {
                first => sub {
                    my $q = shift;
                    $q .= ' 23:59:59' if($q =~ /^\d{4}\-\d{2}\-\d{2}$/);
                    my $dt = NGCP::Panel::Utils::DateTime::from_string($q);
					open(my $fh, ">>/tmp/x.out");
					print $fh "start_ge: ".$dt->epoch."\n";
					close $fh;
                    { 'me.timestamp' => { '<=' => $dt->epoch } };
                },
                second => sub {},
            },
        },
		{
            param => 'subscriber_id',
            description => 'End time of the captured SIP data',
            query => {
                first => sub {
					my $q = shift;
                    {
						'voip_subscriber.id' => $q,
					};
                },
                second => sub {
					{
						join => { message_packets => { message => 'voip_subscriber' } },
					};
				},
            },
		},
        {
            # we handle that separately/manually in the role
            param => 'tz',
            description => 'Format start_time according to the optional time zone provided here, e.g. Europe/Berlin.',
        },
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::SIPCaptures/;

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
    my ($self, $c) = @_;
    {
        if($c->req->param('tz') && !DateTime::TimeZone->is_valid_name($c->req->param('tz'))) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Query parameter 'tz' value is not a valid time zone");
            return;
        }
        my $sipcaptures = $self->item_rs($c);

        my $call_id = $c->request->param('call_id') || '';
        my $start_ge = $c->request->param('start_ge') || '';
        my $start_le = $c->request->param('start_le') || '';
        unless ($call_id || ($start_ge && $start_le)) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY,
                sprintf "call_id or start_ge+start_le parameter is required");
            last;
        }

        my $pcap = NGCP::Panel::Utils::Callflow::generate_pcap([$sipcaptures->all]);
        last unless $pcap;

        my $filename = sprintf "%s.pcap",
			join("-", grep { /^\S+/ } ($call_id, $start_le, $start_ge));
        $c->response->header("Content-Disposition" => "attachment; filename=$filename");
        $c->response->content_type('application/vnd.tcpdump.pcap');
        $c->response->body($pcap);
    }
    return;


}

1;

# vim: set tabstop=4 expandtab:
