package NGCP::Panel::Controller::API::FaxRecordingsItem;
use NGCP::Panel::Utils::Generic qw(:all);

use strict;
use warnings;

use TryCatch;

use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::ValidateJSON qw();
use NGCP::Panel::Utils::Fax;
use Path::Tiny qw(path);
use Safe::Isa qw($_isa);
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
            AllowedRole => [qw/admin reseller/],
            Args => 1,
            Does => [qw(ACL RequireSSL)],
            Method => $_,
            Path => __PACKAGE__->dispatch_path,
        } } @{ __PACKAGE__->allowed_methods }
    },
    action_roles => [qw(+NGCP::Panel::Role::HTTPMethods)],
);



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
                                filename => $item->filename,
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





sub end : Private {
    my ($self, $c) = @_;

    #$self->log_response($c);
}

1;

# vim: set tabstop=4 expandtab:
