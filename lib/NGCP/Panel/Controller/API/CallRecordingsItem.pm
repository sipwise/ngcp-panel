package NGCP::Panel::Controller::API::CallRecordingsItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD DELETE/];
}

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::CallRecordings/;

use NGCP::Panel::Utils::Subscriber;
use HTTP::Status qw(:constants);

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller subscriberadmin subscriber/],
    required_licenses => [qw/call_recording/],
});

sub DELETE :Allow {

    my ($self, $c, $id) = @_;
    $c->model('DB')->set_transaction_isolation('READ COMMITTED');
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $recording = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, callrecording => $recording);
        my $subs;
        $subs = $c->model('DB')->resultset('voip_subscribers')->search({
            id => $c->req->params->{subscriber_id}
        })->first if $c->req->params->{subscriber_id};
        try {
            NGCP::Panel::Utils::Subscriber::delete_callrecording(
                c => $c,
                recording => $recording,
                force_delete => $c->request->params->{force_delete},
                uuid => ($subs ? $subs->uuid : undef),
            );
        } catch($e) {
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to delete callrecording.", $e);
            last;
        }

        $guard->commit;

        $c->response->status(HTTP_NO_CONTENT);
        $c->response->body(q());
    }
    return;

}

1;

# vim: set tabstop=4 expandtab:
