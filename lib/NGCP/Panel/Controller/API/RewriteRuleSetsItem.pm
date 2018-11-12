package NGCP::Panel::Controller::API::RewriteRuleSetsItem;

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::RewriteRuleSets/;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::Rewrite;

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
            $item->voip_rewrite_rules->delete;
            $item->delete;
        } catch($e) {
            $c->log->error("Failed to delete rewriteruleset with id '".$item->id."': $e");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error");
            last;
        }
        $guard->commit;
        NGCP::Panel::Utils::Rewrite::sip_dialplan_reload($c);
    }
    return 1;
}

sub update_item_model {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    my $id = delete $resource->{id};

    my $guard = $c->model('DB')->txn_scope_guard;
    {
        try {
            my $rewriterules = delete $resource->{rewriterules};
            $item->update($resource);
            if ($rewriterules) {
                $self->update_rewriterules( $c, $item, $form, $rewriterules );
            }
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
