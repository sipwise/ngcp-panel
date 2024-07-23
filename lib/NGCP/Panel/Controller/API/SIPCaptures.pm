package NGCP::Panel::Controller::API::SIPCaptures;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use NGCP::Panel::Utils::DateTime;

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::SIPCaptures/;

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller subscriberadmin subscriber/],
    required_licenses => [qw/voisniff-mysql_dump/],
});


sub allowed_methods{
    return [qw/GET OPTIONS/];
}

sub api_description {
    return 'Defines SIP packet captures for a call. A GET on item with call-id as the parameter returns pcap data as application/vnd.tcpdump.pcap.';
};

sub query_params {
    return [
        {
            param => 'call_id',
            description => 'Filter for a particular call_id',
            query_type => 'string_eq',
        },
        {
            param => 'start_ge',
            description => 'Filter for data starting greater or equal the specified time stamp.',
            query => {
                first => sub {
                    my $q = shift;
                    my $dt = NGCP::Panel::Utils::DateTime::from_string($q);
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
                    { 'me.timestamp' => { '<=' => $dt->epoch } };
                },
                second => sub {},
            },
        },
        {
            param => 'method',
            description => 'Filter for a particular SIP method',
            query_type => 'string_eq',
        },
        {
            param => 'subscriber_id',
            description => 'End time of the captured SIP data',
            new_rs => sub {
                my ($c, $q, $rs) = @_;
                if ($c->user->roles ne "subscriber") {
                    my $sub = $c->model('DB')->resultset('voip_subscribers')->find($q);
                    if ($sub) {
                        $rs = $rs->search_rs({
                            -or => [
                                    'me.caller_uuid' => $sub->uuid,
                                    'me.callee_uuid' => $sub->uuid
                                   ],
                        });
                    }
                }
                return $rs;
            }
        },
        {
            # we handle that separately/manually in the role
            param => 'tz',
            description => 'Format start_time according to the optional time zone provided here, e.g. Europe/Berlin.',
        },
    ];
}

1;

# vim: set tabstop=4 expandtab:
