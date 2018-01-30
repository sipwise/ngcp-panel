package NGCP::Panel::Controller::API::PbxDeviceFirmwaresItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::ValidateJSON qw();
require Catalyst::ActionRole::ACL;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD PUT/];
}

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::PbxDeviceFirmwares/;

sub resource_name{
    return 'pbxdevicefirmwares';
}

sub dispatch_path{
    return '/api/pbxdevicefirmwares/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-pbxdevicefirmwares';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
});

sub GET :Allow {
    my ($self, $c, $id) = @_;
    {
        last unless $self->valid_id($c, $id);
        my $item = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, pbxdevicefirmware => $item);

        my $hal = $self->hal_from_item($c, $item);

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

sub PUT :Allow {
    my ($self, $c, $id) = @_;
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $preference = $self->require_preference($c);
        last unless $preference;

        my $item = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, pbxdevicefirmware => $item);
        my $binary = $self->get_valid_raw_put_data(
            c => $c,
            id => $id,
            media_type => 'application/octet-stream',
        );
        last unless $binary;
        my $resource = $c->req->query_params;
        my $form = $self->get_form($c);
        my $old_resource = $self->resource_from_item($c, $item, $form);

        $item = $self->update_item($c, $item, $old_resource, $resource, $form);
        last unless $item;

        if ($binary) {
            NGCP::Panel::Utils::DeviceFirmware::insert_firmware_data(
                c => $c, fw_id => $item->id, data_ref => \$binary
            );
        }

        $guard->commit;

        $self->return_representation($c, 'item' => $item, 'form' => $form, 'preference' => $preference );
    }
    return;
}

=pod
sub DELETE :Allow {
    my ($self, $c, $id) = @_;

    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $item = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, pbxdevicefirmware => $item);
        $item->delete;

        $guard->commit;

        $c->response->status(HTTP_NO_CONTENT);
        $c->response->body(q());
    }
    return;
}
=cut



1;

# vim: set tabstop=4 expandtab:
