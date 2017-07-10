package NGCP::Panel::Controller::API::RewriteRulesItem;

use parent qw/NGCP::Panel::Role::EntitiesItem  NGCP::Panel::Role::API::RewriteRules/;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);
use HTTP::Status qw(:constants);

__PACKAGE__->set_config();

sub _set_config{
    my ($self, $method) = @_;
    return {
        own_transaction_control => {all => 1},
    };
}

sub allowed_methods{
    return [qw/GET OPTIONS HEAD PATCH PUT DELETE/];
}

sub PATCH :Allow {
    my ($self, $c, $id) = @_;
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $preference = $self->require_preference($c);
        last unless $preference;

        my $json = $self->get_valid_patch_data(
            c => $c,
            id => $id,
            media_type => 'application/json-patch+json',
            ops => [qw/add replace remove copy/],
        );
        last unless $json;

        my $rule = $self->item_by_id($c, $id, "rules");
        last unless $self->resource_exists($c, rule => $rule);
        my $old_resource = { $rule->get_inflated_columns };
        my $resource = $self->apply_patch($c, $old_resource, $json);
        last unless $resource;

        my $form = $self->get_form($c);
        $rule = $self->update_item($c, $rule, $old_resource, $resource, $form);
        last unless $rule;

        $guard->commit; 
        NGCP::Panel::Utils::Rewrite::sip_dialplan_reload($c);

        if ('minimal' eq $preference) {
            $c->response->status(HTTP_NO_CONTENT);
            $c->response->header(Preference_Applied => 'return=minimal');
            $c->response->body(q());
        } else {
            my $hal = $self->hal_from_item($c, $rule, "rewriterules");
            my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
                $hal->http_headers,
            ), $hal->as_json);
            $c->response->headers($response->headers);
            $c->response->header(Preference_Applied => 'return=representation');
            $c->response->body($response->content);
        }
    }
    return;
}

sub PUT :Allow {
    my ($self, $c, $id) = @_;
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $preference = $self->require_preference($c);
        last unless $preference;

        my $rule = $self->item_by_id($c, $id, "rules");
        last unless $self->resource_exists($c, rule => $rule);
        my $resource = $self->get_valid_put_data(
            c => $c,
            id => $id,
            media_type => 'application/json',
        );
        last unless $resource;
        my $old_resource = { $rule->get_inflated_columns };

        my $form = $self->get_form($c);
        $rule = $self->update_item($c, $rule, $old_resource, $resource, $form);
        last unless $rule;

        $guard->commit;
        NGCP::Panel::Utils::Rewrite::sip_dialplan_reload($c);

        if ('minimal' eq $preference) {
            $c->response->status(HTTP_NO_CONTENT);
            $c->response->header(Preference_Applied => 'return=minimal');
            $c->response->body(q());
        } else {
            my $hal = $self->hal_from_item($c, $rule, "rewriterules");
            my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
                $hal->http_headers,
            ), $hal->as_json);
            $c->response->headers($response->headers);
            $c->response->header(Preference_Applied => 'return=representation');
            $c->response->body($response->content);
        }
    }
    return;
}

sub DELETE :Allow {
    my ($self, $c, $id) = @_;
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $rule = $self->item_by_id($c, $id, "rules");
        last unless $self->resource_exists($c, rule => $rule);
        try {
            $rule->delete;
        } catch($e) {
            $c->log->error("Failed to delete rewriterule with id '$id': $e");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error");
            last;
        }
        $guard->commit;
        NGCP::Panel::Utils::Rewrite::sip_dialplan_reload($c);

        $c->response->status(HTTP_NO_CONTENT);
        $c->response->body(q());
    }
    return;
}

sub post_process_hal_resource {
    my($self, $c, $item, $resource, $form) = @_;
    $resource->{match_pattern} = $form->inflate_match_pattern($resource->{match_pattern});
    $resource->{replace_pattern} = $form->inflate_replace_pattern($resource->{replace_pattern});
    return $resource;
}
1;

# vim: set tabstop=4 expandtab:
