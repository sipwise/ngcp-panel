package NGCP::Panel::Controller::API::ResellersItem;
use Sipwise::Base;
use namespace::sweep;
use DateTime qw();
use DateTime::Format::HTTP qw();
use HTTP::Headers qw();
use HTTP::Status qw(
    HTTP_NOT_IMPLEMENTED
);
use MooseX::ClassAttribute qw(class_has);
BEGIN { extends 'Catalyst::Controller::ActionRole'; }
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require Catalyst::ActionRole::HTTPMethods;
require Catalyst::ActionRole::QueryParameter;
require Catalyst::ActionRole::RequireSSL;
require URI::QueryParam;

class_has('dispatch_path', is => 'ro', default => '/api/resellers/');

__PACKAGE__->config(
    action => {
        map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => 'api_admin',
            Args => 0,
            Does => [qw(ACL CheckTrailingSlash RequireSSL)],
            Method => $_,
            Path => __PACKAGE__->dispatch_path,
            QueryParam => 'id',
        } } @{ __PACKAGE__->allowed_methods }
    },
    action_roles => [qw(HTTPMethods QueryParameter)],
);

sub GET : Allow {
    my ($self, $c) = @_;
    $c->response->status(HTTP_NOT_IMPLEMENTED);
    $c->response->headers(HTTP::Headers->new(
        Content_Language => 'en',
        Retry_After => DateTime::Format::HTTP->format_datetime(DateTime->new(year => 2014, month => 1, day => 1)), # XXX
    ));
    $c->stash(template => 'api/not_implemented.tt', entity_name => 'resellers');
    return;
}

sub HEAD : Allow {
    my ($self, $c) = @_;
    $c->forward(qw(GET));
    $c->response->body(q());
    return;
}

sub OPTIONS : Allow {
    my ($self, $c) = @_;
    my $allowed_methods = $self->allowed_methods->join(q(, ));
    $c->response->headers(HTTP::Headers->new(
        Allow => $allowed_methods,
        Content_Language => 'en',
    ));
    $c->response->content_type('application/xhtml+xml');
    $c->stash(template => 'api/allowed_methods.tt', allowed_methods => $allowed_methods);
    return;
}


sub allowed_methods : Private {
    my ($self) = @_;
    my $meta = $self->meta;
    my @allow;
    for my $method ($meta->get_method_list) {
        push @allow, $meta->get_method($method)->name
            if $meta->get_method($method)->can('attributes') && 'Allow' ~~ $meta->get_method($method)->attributes;
    }
    return [sort @allow];
}
