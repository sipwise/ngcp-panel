package NGCP::Panel::Role::API::RewriteRules;

use parent qw/NGCP::Panel::Role::API/;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);
use HTTP::Status qw(:constants);


sub item_name{
    return 'rewriterule';
}

sub resource_name{
    return 'rewriterules';
}

sub dispatch_path{
    return '/api/rewriterules/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-rewriterules';
}

sub config_allowed_roles {
    return [qw/admin reseller/];
}

sub _item_rs {
    my ($self, $c, $type) = @_;
    my $item_rs;

    if($c->user->roles eq "admin") {
        $item_rs = $c->model('DB')->resultset('voip_rewrite_rules');
    } elsif ($c->user->roles eq "reseller") {
        $item_rs = $c->model('DB')->resultset('voip_rewrite_rules')->search_rs({
                'ruleset.reseller_id' => $c->user->reseller_id,
            },{
                join => 'ruleset'
            });
    }
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return ( NGCP::Panel::Form::get("NGCP::Panel::Form::RewriteRule::RuleAPI", $c) );
}

sub hal_links{
    my($self, $c, $item, $resource, $form) = @_;
    return [
        NGCP::Panel::Utils::DataHalLink->new(relation => "ngcp:rewriterulesets", href => sprintf("/api/rewriterulesets/%d", $item->set_id)),
    ];
}

sub post_process_hal_resource {
    my($self, $c, $item, $resource, $form) = @_;
    $resource->{match_pattern} = $form->inflate_match_pattern($resource->{match_pattern});
    $resource->{replace_pattern} = $form->inflate_replace_pattern($resource->{replace_pattern});
    return $resource;
}

sub process_form_resource{
    my($self,$c, $item, $old_resource, $resource, $form, $process_extras) = @_;
    $resource->{match_pattern} = $form->values->{match_pattern};
    $resource->{replace_pattern} = $form->values->{replace_pattern};
    return $resource;
}

sub check_resource{
    my($self, $c, $item, $old_resource, $resource, $form, $process_extras) = @_;
    my $schema = $c->model('DB');

    unless(defined $resource->{set_id}) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Required: 'set_id'");
        return;
    }

    my $reseller_id;
    if($c->user->roles eq "reseller") {
        $reseller_id = $c->user->reseller_id;
    }

    my $ruleset = $schema->resultset('voip_rewrite_rule_sets')->find({
        id => $resource->{set_id},
        ($reseller_id ? (reseller_id => $reseller_id) : ()),
    });
    unless($ruleset) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'set_id'.");
        return;
    }

    $c->stash->{checked}->{ruleset} = $ruleset;

    return 1;
}


1;
# vim: set tabstop=4 expandtab:
