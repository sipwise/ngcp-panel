package NGCP::Panel::Controller::API::Faxes;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;


use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::API::Subscribers;
use NGCP::Panel::Utils::Fax;
use Encode qw( encode_utf8 );

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::Faxes/;

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller subscriberadmin subscriber/],
    GET           => {
        ContentType => ['multipart/form-data'],
    }
});

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines the meta information like duration, sender etc for fax recordings. The actual recordings can be fetched via the <a href="#faxrecordings">FaxRecordings</a> relation. NOTE: There is no Location header in the POST method response, as creation is asynchronous.';
};

sub query_params {
    return [
        {
            param => 'subscriber_id',
            description => 'Filter for faxes belonging to a specific subscriber',
            query => {
                first => sub {
                    my $q = shift;
                    # join is already done in get_item_rs
                    { 'voip_subscriber.id' => $q };
                },
                second => sub { },
            },
        },

        {
            param => 'time_from',
            description => 'Filter for faxes performed after or at the given time stamp.',
            query => {
                first => sub {
                    my $q = shift;
                    my $dt = NGCP::Panel::Utils::DateTime::from_string($q);
                    return { 'me.time' => { '>=' => $dt->epoch  } };
                },
                second => sub { },
            },
        },

        {
            param => 'time_to',
            description => 'Filter for faxes performed before or at the given time stamp.',
            query => {
                first => sub {
                    my $q = shift;
                    my $dt = NGCP::Panel::Utils::DateTime::from_string($q);
                    return { 'me.time' => { '<=' => $dt->epoch  } };
                },
                second => sub { },
            },
        }, 

        {
            param => 'sid',
            description => 'Filter for a fax with the specific session id',
            query => {
                first => sub {
                    my $q = shift;
                    { 'me.sid' => $q };
                },
                second => sub { },
            },
        },

    ];
}

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $items = $self->item_rs($c);
        (my $total_count, $items) = $self->paginate_order_collection($c, $items);
        my (@embedded, @links);
        for my $item ($items->all) {
            push @embedded, $self->hal_from_item($c, $item);
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('/%s%d', $c->request->path, $item->id),
            );
        }
        push @links,
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            $self->collection_nav_links($c, $page, $rows, $total_count, $c->request->path, $c->request->query_params);

        my $hal = Data::HAL->new(
            embedded => [@embedded],
            links => [@links],
        );
        $hal->resource({
            total_count => $total_count,
        });
        my $response = HTTP::Response->new(HTTP_OK, undef,
            HTTP::Headers->new($hal->http_headers(skip_links => 1)), $hal->as_json);
        $c->response->headers($response->headers);
        $c->response->body($response->content);
        return;
    }
    return;
}

sub POST :Allow {
    my ($self, $c) = @_;
    {
        if (!$c->config->{features}->{faxserver}) {
            $c->log->error("faxserver feature is not active.");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Faxserver feature is not active.");
            return;
        }
        last unless $self->forbid_link_header($c);
        last unless $self->valid_media_type($c, 'multipart/form-data');
        my $json_utf8 = encode_utf8($c->req->param('json'));
        last unless $self->require_wellformed_json($c, 'application/json', $json_utf8 );
        my $resource = JSON::from_json($json_utf8, { utf8 => 0 });
        $resource->{faxfile} = $self->get_upload($c, 'faxfile');
        $c->log->debug("upload received");

        my $form = $self->get_form($c);
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
        );
        $c->log->debug("form validated");
        my $billing_subscriber = NGCP::Panel::Utils::API::Subscribers::get_active_subscriber($self, $c, $resource->{subscriber_id});
        unless($billing_subscriber) {
            $c->log->error("invalid subscriber id $$resource{subscriber_id} for fax send");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Fax subscriber not found.");
            last;
        }
        my $prov_subscriber = $billing_subscriber->provisioning_voip_subscriber;
        last unless $prov_subscriber;
        my $faxpref = $prov_subscriber->voip_fax_preference;
        unless ($faxpref && $faxpref->active){
            $c->log->error("invalid subscriber fax preferences");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid  subscriber fax preferences");
            last;
        }
        try {
            $c->log->debug("contacting fax server");
            my $output = NGCP::Panel::Utils::Fax::send_fax(
                c => $c,
                subscriber => $billing_subscriber,
                destination => $form->values->{destination},
                upload => $form->values->{faxfile},
                data => $form->values->{data},
            );
            $c->log->debug("faxserver output:\n");
            $c->log->debug($output);
        } catch($e) {
            $c->log->error("failed to send fax: $e");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error");
            return;
        };
        $c->response->status(HTTP_CREATED);
        $c->response->body(q());
    }
    return;
}

1;

# vim: set tabstop=4 expandtab:
