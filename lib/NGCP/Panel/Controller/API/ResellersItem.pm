package NGCP::Panel::Controller::API::ResellersItem;
use Sipwise::Base;
use namespace::sweep;
use DateTime qw();
use DateTime::Format::HTTP qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use MooseX::ClassAttribute qw(class_has);
BEGIN { extends 'Catalyst::Controller::ActionRole'; }
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require Catalyst::ActionRole::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

with 'NGCP::Panel::Role::API';

class_has('dispatch_path', is => 'ro', default => '/api/resellers/');

__PACKAGE__->config(
    action => {
        map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => 'api_admin',
            Args => 1,
            Does => [qw(ACL RequireSSL)],
            Method => $_,
            Path => __PACKAGE__->dispatch_path,
        } } @{ __PACKAGE__->allowed_methods }
    },
    action_roles => [qw(HTTPMethods)],
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

sub end : Private {
    my ($self, $c) = @_;
    $c->forward(qw(Controller::Root render));
    $c->response->content_type('')
        if $c->response->content_type =~ qr'text/html'; # stupid RenderView getting in the way
    if (@{ $c->error }) {
        my $msg = join ', ', @{ $c->error };
        $c->log->error($msg);
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error");
        $c->clear_errors;
    }
}
