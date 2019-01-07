package NGCP::Panel::Role::API::HeaderRules;

use parent qw/NGCP::Panel::Role::API/;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);
use NGCP::Panel::Utils::API;
use NGCP::Panel::Utils::HeaderManipulations;
use HTTP::Status qw(:constants);

sub item_name {
    return 'headerrule';
}

sub resource_name {
    return 'headerrules';
}

sub config_allowed_roles {
    return [qw/admin reseller/];
}

sub _item_rs {
    my ($self, $c, $type) = @_;
    my $item_rs;

    if ($c->user->roles eq "admin") {
        $item_rs = $c->model('DB')->resultset('voip_header_rules');
    } elsif ($c->user->roles eq "reseller") {
        $item_rs = $c->model('DB')->resultset('voip_header_rules')->search_rs({
                'ruleset.reseller_id' => $c->user->reseller_id,
            },{
                join => 'ruleset'
            });
    }
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return ( NGCP::Panel::Form::get("NGCP::Panel::Form::Header::RuleAPI", $c) );
}

sub hal_links {
    my ($self, $c, $item, $resource, $form) = @_;
    return [
        Data::HAL::Link->new(relation => "ngcp:headerrulesets", href => sprintf("/api/headerrulesets/%d", $item->set_id)),
    ];
}

sub check_resource {
    my ($self, $c, $item, $old_resource, $resource, $form, $process_extras) = @_;
    my $schema = $c->model('DB');

    unless (defined $resource->{set_id}) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Required: 'set_id'");
        return;
    }

    my $reseller_id;
    if ($c->user->roles eq "reseller") {
        $reseller_id = $c->user->reseller_id;
    }

    my $ruleset = $schema->resultset('voip_header_rule_sets')->find({
        id => $resource->{set_id},
        ($reseller_id ? (reseller_id => $reseller_id) : ()),
    });
    unless ($ruleset) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'set_id'.");
        return;
    }

    $c->stash->{checked}->{ruleset} = $ruleset;

    return 1;
}

sub update_item_model {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    $item = $self->SUPER::update_item_model($c, $item, $old_resource, $resource, $form);

    NGCP::Panel::Utils::HeaderManipulations::invalidate_ruleset(
        c => $c, set_id => $item->ruleset->id
    );

    return $item;
}

1;
# vim: set tabstop=4 expandtab:
