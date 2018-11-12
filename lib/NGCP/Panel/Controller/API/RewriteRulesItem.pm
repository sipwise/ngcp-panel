package NGCP::Panel::Controller::API::RewriteRulesItem;

use parent qw/NGCP::Panel::Role::EntitiesItem  NGCP::Panel::Role::API::RewriteRules/;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);
use HTTP::Status qw(:constants);

__PACKAGE__->set_config({
    own_transaction_control => { POST => 1 },
});

sub allowed_methods{
    return [qw/GET OPTIONS HEAD PATCH PUT DELETE/];
}

sub delete_item {
    my ($self, $c, $item) = @_;
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        try {
            $item->delete;
        } catch($e) {
            $c->log->error("Failed to delete rewriterule with id '".$item->id."': $e");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error");
            return;
        }
        $guard->commit;
        NGCP::Panel::Utils::Rewrite::sip_dialplan_reload($c);
    }
    return 1;
}

sub update_item_model {
    my($self, $c, $item, $old_resource, $resource, $form, $process_extras) = @_;

    my $id = delete $resource->{id};

    my $guard = $c->model('DB')->txn_scope_guard;
    {
        try {
            $item->update($resource);
        } catch($e) {
            $c->log->error("Failed to update rewriterule with id '$id': $e");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error");
            die;
        }
        $guard->commit;
        NGCP::Panel::Utils::Rewrite::sip_dialplan_reload($c);
    }
    return $item;
}
1;

# vim: set tabstop=4 expandtab:
