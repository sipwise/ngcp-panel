package NGCP::Panel::Role::API::SIPCaptures;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('Storage')->resultset('messages');

    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({
            'contact.reseller_id' => $c->user->reseller_id
        },{
            join => { voip_subscriber => { contract => 'contact' } }
        });
    } elsif ($c->user->roles eq "subscriberadmin") {
        $item_rs = $item_rs->search_rs({
            'contract.id' => $c->user->account_id,
        },{
            join => { voip_subscriber => { contract => 'contact' } }
        });
    } elsif ($c->user->roles eq "subscriber") {
        $item_rs = $item_rs->search_rs({
            'voip_subscriber.uuid' => $c->user->uuid,
        },{
            join => 'voip_subscriber'
        });
    }

    return $item_rs;
}

sub packets_by_callid {
    my ($self, $c, $id) = @_;
    my $item_rs = $c->model('Storage')->resultset('packets')->search({
        'message.call_id' => $id
    },{
        join => { message_packets => 'message' }
    });
    return $item_rs->first ? [$item_rs->all] : undef;
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::get("NGCP::Panel::Form::SIPCaptures", $c);
}

#
sub resource_from_item {
    my ($self, $c, $item, $form) = @_;

    my %resource = $item->get_inflated_columns;

    my $datetime_fmt = DateTime::Format::Strptime->new(
        pattern => '%F %T',
    );
    my $tz = $c->req->param('tz');
    unless($tz && DateTime::TimeZone->is_valid_name($tz)) {
        $tz = undef;
    }
    if($item->timestamp) {
        if($tz) {
            $item->timestamp->set_time_zone($tz);
        }
        $resource{timestamp} = $datetime_fmt->format_datetime($item->timestamp);
        if ($item->timestamp->millisecond > 0.0) {
            $resource{timestamp} .= '.'.$item->timestamp->millisecond;
        }
    }

    $resource{request_uri} = $item->request_uri;

    return \%resource;
}

sub hal_from_item {
    my ($self, $c, $item, $form) = @_;

    $form //= $self->get_form($c);
    my $resource = $self->resource_from_item($c, $item, $form);

    my $hal = Data::HAL->new(
        links => [
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'collection', href => sprintf("/api/%s/", $self->resource_name)),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            Data::HAL::Link->new(relation => 'self', href => sprintf("%s%s", $self->dispatch_path, $item->call_id)),
            Data::HAL::Link->new(relation => 'ngcp:sipcaptures', href => sprintf("/api/sipcaptures/%s", $item->call_id)),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $self->validate_form(
        c => $c,
        resource => $resource,
        form => $form,
        run => 0,
    );

    $hal->resource($resource);

    return $hal;
}

1;
# vim: set tabstop=4 expandtab:
