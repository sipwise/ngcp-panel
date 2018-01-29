package NGCP::Panel::Controller::API::FaxRecordingsItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::ValidateJSON qw();
use NGCP::Panel::Utils::Fax;
use File::Basename;
use File::Type;
require Catalyst::ActionRole::ACL;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::FaxRecordings/;

sub resource_name{
    return 'faxrecordings';
}
sub dispatch_path{
    return '/api/faxrecordings/';
}
sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-faxrecordings';
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
);

sub gather_default_action_roles {
    my ($self, %args) = @_; my @roles = ();
    push @roles, 'NGCP::Panel::Role::HTTPMethods' if $args{attributes}->{Method};
    return @roles;
}



sub GET :Allow {
    my ($self, $c, $id) = @_;
    my $rc = 1;
    {
        last unless $self->valid_id($c, $id);
        my $item = $self->item_by_id($c, $id);
        unless ($self->resource_exists($c, faxrecording => $item)) {
            $self->error($c, HTTP_NOT_FOUND,
                sprintf "Fax recording %d was not found.", $id);
            $rc = 0;
            last;
        }
        last unless $item && $item->status && $item->filename;

        my $format = $c->request->param('format') || '';
        if ($format && $format !~ /^(ps|pdf|pdf14)$/) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY,
                sprintf "Unknown fax recording format");
            $rc = 0;
            last;
        }

        my ($content, $ext) = NGCP::Panel::Utils::Fax::get_fax(
                                c => $c,
                                item => $item,
                                format => $format,
                              );
        last unless $content && $ext;

        my $filename = sprintf "%s.%s", (fileparse($item->filename))[0], $ext;
        my $ft = File::Type->new();
        $c->response->header ('Content-Disposition' => 'attachment; filename="' . $item->id . '-' . $filename);
        $c->response->content_type($ft->mime_type($content));
        $c->response->body($content);
        $rc = 0;
    }
    if ($rc) {
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR,
            sprintf "Error processing fax recording %d", $id);

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

    #$self->log_response($c);
}

1;

# vim: set tabstop=4 expandtab:
