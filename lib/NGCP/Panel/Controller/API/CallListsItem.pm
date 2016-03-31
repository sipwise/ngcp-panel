package NGCP::Panel::Controller::API::CallListsItem;
use NGCP::Panel::Utils::Generic qw(:all);
no Moose;
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use TryCatch;
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::ValidateJSON qw();
use DateTime::TimeZone;
use Path::Tiny qw(path);
use Safe::Isa qw($_isa);
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

use parent qw/Catalyst::Controller NGCP::Panel::Role::API::CallLists/;

sub resource_name{
    return 'calllists';
}
sub dispatch_path{
    return '/api/calllists/';
}
sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-calllists';
}

__PACKAGE__->config(
    action => {
        map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin reseller subscriberadmin subscriber/],
            Args => 1,
            Does => [qw(ACL RequireSSL)],
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
    my ($self, $c, $id) = @_;
    {
        if($c->req->param('tz') && !DateTime::TimeZone->is_valid_name($c->req->param('tz'))) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Query parameter 'tz' value is not a valid time zone");
            return;
        }

        my $schema = $c->model('DB');
        last unless $self->valid_id($c, $id);

        my $owner = $self->get_owner_data($c, $schema);
        last unless $owner;
        my $href_data = $owner->{subscriber} ? 
            "subscriber_id=".$owner->{subscriber}->id :
            "customer_id=".$owner->{customer}->id;

        my $item = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, calllist => $item);

        my $hal = $self->hal_from_item($c, $item, $owner, undef, $href_data);

        my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
            (map { # XXX Data::HAL must be able to generate links with multiple relations
                s|rel="(http://purl.org/sipwise/ngcp-api/#rel-resellers)"|rel="item $1"|;
                s/rel=self/rel="item self"/;
                $_
            } $hal->http_headers),
        ), $hal->as_json);
        $c->response->headers($response->headers);
        $c->response->body($response->content);
        return;
    }
    return;
}

sub HEAD :Allow {
    my ($self, $c, $id) = @_;
    $c->forward(qw(GET));
    $c->response->body(q());
    return;
}

sub OPTIONS :Allow {
    my ($self, $c, $id) = @_;
    my $allowed_methods = $self->allowed_methods_filtered($c);
    $c->response->headers(HTTP::Headers->new(
        Allow => join(', ', @{ $allowed_methods }),
        Accept_Patch => 'application/json-patch+json',
    ));
    $c->response->content_type('application/json');
    $c->response->body(JSON::to_json({ methods => $allowed_methods })."\n");
    return;
}

sub end : Private {
    my ($self, $c) = @_;

    $self->log_response($c);
}

no Moose;
1;

# vim: set tabstop=4 expandtab:
