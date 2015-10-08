package NGCP::Panel::Controller::API::Faxes;
use Sipwise::Base;
use namespace::sweep;
use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use MooseX::ClassAttribute qw(class_has);
use NGCP::Panel::Utils::DateTime;
use Path::Tiny qw(path);
use Safe::Isa qw($_isa);
use NGCP::Panel::Utils::API::Subscribers;
use Encode qw( encode_utf8 );
BEGIN { extends 'Catalyst::Controller::ActionRole'; }
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require Catalyst::ActionRole::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

class_has 'api_description' => (
    is => 'ro',
    isa => 'Str',
    default =>
        'Defines the meta information like duration, sender etc for fax recordings. The actual recordings can be fetched via the <a href="#faxrecordings">FaxRecordings</a> relation. NOTE: There is no Location header in the POST method response, as creation is asynchronous.',
);

class_has 'query_params' => (
    is => 'ro',
    isa => 'ArrayRef',
    default => sub {[
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
    ]},
);

with 'NGCP::Panel::Role::API::Faxes';

class_has('resource_name', is => 'ro', default => 'faxes');
class_has('dispatch_path', is => 'ro', default => '/api/faxes/');
class_has('relation', is => 'ro', default => 'http://purl.org/sipwise/ngcp-api/#rel-faxes');

__PACKAGE__->config(
    action => {
        map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin reseller/],
            Args => 0,
            Does => [qw(ACL CheckTrailingSlash RequireSSL)],
            Method => $_,
            Path => __PACKAGE__->dispatch_path,
        } } @{ __PACKAGE__->allowed_methods }
    },
    action_roles => [qw(HTTPMethods)],
);

sub auto :Private {
    my ($self, $c) = @_;

    $self->set_body($c);
    $self->log_request($c);
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
            Data::HAL::Link->new(relation => 'self', href => sprintf('/%s?page=%s&rows=%s', $c->request->path, $page, $rows));
        if(($total_count / $rows) > $page ) {
            push @links, Data::HAL::Link->new(relation => 'next', href => sprintf('/%s?page=%d&rows=%d', $c->request->path, $page + 1, $rows));
        }
        if($page > 1) {
            push @links, Data::HAL::Link->new(relation => 'prev', href => sprintf('/%s?page=%d&rows=%d', $c->request->path, $page - 1, $rows));
        }

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

sub HEAD :Allow {
    my ($self, $c) = @_;
    $c->forward(qw(GET));
    $c->response->body(q());
    return;
}

sub OPTIONS :Allow {
    my ($self, $c) = @_;
    my $allowed_methods = $self->allowed_methods_filtered($c);
    $c->response->headers(HTTP::Headers->new(
        Allow => $allowed_methods->join(', '),
        Accept_Post => 'application/hal+json; profile=http://purl.org/sipwise/ngcp-api/#rel-'.$self->resource_name,
    ));
    $c->response->content_type('application/json');
    $c->response->body(JSON::to_json({ methods => $allowed_methods })."\n");
    return;
}

sub POST :Allow {
    my ($self, $c) = @_;
    {
        last unless $self->forbid_link_header($c);
        last unless $self->valid_media_type($c, 'multipart/form-data');
        my $json_utf8 = encode_utf8($c->req->param('json'));
        last unless $self->require_wellformed_json($c, 'application/json', $json_utf8 );
        my $resource = JSON::from_json($json_utf8, { utf8 => 0 });
        $resource->{faxfile} = $self->get_upload($c, 'faxfile');

        my $form = $self->get_form($c);
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
            exceptions => [qw/subscriber_id/],
        );
        my $billing_subscriber = NGCP::Panel::Utils::API::Subscribers::get_active_subscriber($self, $c, $resource->{subscriber_id});
        my $prov_subscriber = $billing_subscriber->provisioning_voip_subscriber;
        last unless $prov_subscriber;
        my $faxpref = $prov_subscriber->voip_fax_preference;
        unless ($faxpref && $faxpref->active && $faxpref->password){
            $c->log->error("invalid subscriber fax preferences");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid  subscriber fax preferences");
            last;
        }
        try {
            my $output = NGCP::Panel::Utils::Hylafax::send_fax(
                c => $c,
                subscriber => $billing_subscriber,
                destination => $form->values->{destination},
                (defined $form->values->{faxfile})
                    ?
                    ( upload => $form->values->{faxfile} ) :
                    ( data => $form->values->{data} ),
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


sub end : Private {
    my ($self, $c) = @_;

    $self->log_response($c);
}

# vim: set tabstop=4 expandtab:
