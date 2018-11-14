package NGCP::Panel::Controller::API::CallRecordingsItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::CallRecordings/;

use NGCP::Panel::Utils::Subscriber;
use HTTP::Status qw(:constants);

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller subscriberadmin subscriber/],
});

sub allowed_methods{
    return [qw/GET OPTIONS HEAD DELETE/];
}

sub delete_item {
    my ($self, $c, $item) = @_;
    try {
        NGCP::Panel::Utils::Subscriber::delete_callrecording( 
            c => $c, 
            recording => $item,
            #TODO: Now we don't use any way to document such parameters, need to be created
            force_delete => $c->request->params->{force_delete},
        );
    } catch($e) {
        $c->log->error("failed to delete callrecording: $e");
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to delete callrecording.");
        return;
    }
    return 1;
}

1;

# vim: set tabstop=4 expandtab:
