package NGCP::Panel::Controller::API::FaxRecordingsItem;
use Sipwise::Base;
use namespace::sweep;
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use MooseX::ClassAttribute qw(class_has);
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::ValidateJSON qw();
use Path::Tiny qw(path);
use Safe::Isa qw($_isa);
use File::Type;
use File::Slurp;
BEGIN { extends 'Catalyst::Controller::ActionRole'; }
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

with 'NGCP::Panel::Role::API::FaxRecordings';

class_has('resource_name', is => 'ro', default => 'faxrecordings');
class_has('dispatch_path', is => 'ro', default => '/api/faxrecordings/');
class_has('relation', is => 'ro', default => 'http://purl.org/sipwise/ngcp-api/#rel-faxrecordings');

__PACKAGE__->config(
    action => {
        map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin reseller/],
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
        last unless $self->valid_id($c, $id);
        my $item = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, faxrecording => $item);
        my $content = '';
        if( -e $self->filename){
            my $ft = File::Type->new();
            $c->response->header ('Content-Disposition' => 'attachment; filename="' . $item->id . '-' . $self->filename);
            $content = read_file($self->filename, binmode => ':raw');
            $c->response->content_type($ft->mime_type($content));
            $c->response->body($content);
        }else{
            
        }
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
        Allow => $allowed_methods->join(', '),
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

# vim: set tabstop=4 expandtab:
