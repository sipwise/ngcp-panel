package NGCP::Panel::Role::API::HeaderRuleSets;

use parent qw/NGCP::Panel::Role::API/;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);
use NGCP::Panel::Utils::API;
use NGCP::Panel::Utils::HeaderManipulations;
use NGCP::Panel::Utils::Subscriber;
use HTTP::Status qw(:constants);

sub item_name {
    return 'headerruleset';
}

sub resource_name {
    return 'headerrulesets';
}

sub get_form {
    my ($self, $c, $type) = @_;

    if ($c->user->roles eq "admin") {
        return (NGCP::Panel::Form::get("NGCP::Panel::Form::Header::AdminRuleSetAPI", $c));
    } else {
        return (NGCP::Panel::Form::get("NGCP::Panel::Form::Header::ResellerRuleSetAPI", $c));
    }
}

sub _item_rs {
    my ($self, $c, $type) = @_;
    my $item_rs;

    if ($c->user->roles eq "admin") {
        $item_rs = $c->model('DB')->resultset('voip_header_rule_sets');
    } elsif ($c->user->roles eq "reseller") {
        $item_rs = $c->model('DB')->resultset('voip_header_rule_sets')
            ->search_rs({reseller_id => $c->user->reseller_id});
    }
    if (my $subscriber_id = $c->req->param('subscriber_id')) {
        my $prov_subscriber_id = NGCP::Panel::Utils::Subscriber::billing_to_prov_subscriber_id(
            c => $c, subscriber_id => $subscriber_id
        );
        $item_rs = $item_rs->search_rs(
                    {subscriber_id => $prov_subscriber_id});
    }
    return $item_rs;
}

sub post_process_hal_resource {
    my ($self, $c, $item, $resource, $form) = @_;
    if ($resource->{subscriber_id}) {
        my $subscriber_id = NGCP::Panel::Utils::Subscriber::prov_to_billing_subscriber_id(
            c => $c, subscriber_id => $resource->{subscriber_id}
        );
        $resource->{subscriber_id} = $subscriber_id // 0;
    }
    return $resource;
}

sub process_form_resource {
    my ($self,$c, $item, $old_resource, $resource, $form, $process_extras) = @_;
    NGCP::Panel::Utils::API::apply_resource_reseller_id($c, $resource);
    if ($resource->{subscriber_id}) {
        my $prov_subscriber_id = NGCP::Panel::Utils::Subscriber::billing_to_prov_subscriber_id(
            c => $c, subscriber_id => $resource->{subscriber_id}
        );
        unless ($resource->{subscriber_id} = $prov_subscriber_id) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'subscriber_id'");
            return;
        }
    }
    return $resource;
}

sub check_resource {
    my ($self, $c, $item, $old_resource, $resource, $form, $process_extras) = @_;
    my $schema = $c->model('DB');
    if (!$old_resource || ( $old_resource->{reseller_id} != $resource->{reseller_id}) ) {
        my $reseller = $c->model('DB')->resultset('resellers')
            ->find($resource->{reseller_id});
        unless($reseller) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'reseller_id'");
            return;
        }
    }
    return 1;
}

sub check_duplicate {
    my ($self, $c, $item, $old_resource, $resource, $form, $process_extras) = @_;

    my $schema = $c->model('DB');
    my $existing_item = $schema->resultset('voip_header_rule_sets')->search_rs({
        name => $resource->{name}
    })->first;
    if ($existing_item && (!$item || $item->id != $existing_item->id)) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Header manipulation rule set with this 'name' already exists.");
        return;
    }
    if ($resource->{subscriber_id}) {
        $existing_item = $schema->resultset('voip_header_rule_sets')->search_rs({
            subscriber_id => $resource->{subscriber_id}
        })->first;
        if ($existing_item && (!$item || $item->id != $existing_item->id)) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Header manipulation rule set with this 'subscriber_id' already exists.");
            return;
        }
    }
    return 1;
}

sub update_item_model {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    $item = $self->SUPER::update_item_model($c, $item, $old_resource, $resource, $form);

    NGCP::Panel::Utils::HeaderManipulations::invalidate_ruleset(
        c => $c, set_id => $item->id
    );

    return $item;
}

1;
# vim: set tabstop=4 expandtab:
