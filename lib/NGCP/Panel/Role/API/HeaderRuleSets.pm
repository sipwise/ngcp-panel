package NGCP::Panel::Role::API::HeaderRuleSets;

use parent qw/NGCP::Panel::Role::API/;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);
use NGCP::Panel::Utils::API;
use HTTP::Status qw(:constants);

sub item_name {
    return 'headerruleset';
}

sub resource_name {
    return 'headerrulesets';
}

sub dispatch_path {
    return '/api/headerrulesets/';
}

sub relation {
    return 'http://purl.org/sipwise/ngcp-api/#rel-headerrulesets';
}

sub get_form {
    my ($self, $c, $type) = @_;

    if($c->user->roles eq "admin") {
        return (NGCP::Panel::Form::get("NGCP::Panel::Form::Header::AdminRuleSetAPI", $c));
    } else {
        return (NGCP::Panel::Form::get("NGCP::Panel::Form::Header::ResellerRuleSetAPI", $c));
    }
}

sub _item_rs {
    my ($self, $c, $type) = @_;
    my $item_rs;

    if($c->user->roles eq "admin") {
        $item_rs = $c->model('DB')->resultset('voip_header_rule_sets');
    } elsif($c->user->roles eq "reseller") {
        $item_rs = $c->model('DB')->resultset('voip_header_rule_sets')
            ->search_rs({reseller_id => $c->user->reseller_id});
    }
    return $item_rs;
}

sub process_form_resource {
    my($self,$c, $item, $old_resource, $resource, $form, $process_extras) = @_;
    NGCP::Panel::Utils::API::apply_resource_reseller_id($c, $resource);
    return $resource;
}

sub check_resource {
    my($self, $c, $item, $old_resource, $resource, $form, $process_extras) = @_;
    my $schema = $c->model('DB');
    if(!$old_resource || ( $old_resource->{reseller_id} != $resource->{reseller_id}) ) {
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
    my($self, $c, $item, $old_resource, $resource, $form, $process_extras) = @_;

    my $schema = $c->model('DB');
    my $existing_item = $schema->resultset('voip_header_rule_sets')->search_rs({
        name => $resource->{name}
    })->first;
    if ($existing_item && (!$item || $item->id != $existing_item->id)) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Header manipulation rule set with this 'name' already exists.");
        return;
    }
    return 1;
}

1;
# vim: set tabstop=4 expandtab:
