package NGCP::Panel::Role::API::RewriteRuleSets;

use parent qw/NGCP::Panel::Role::API/;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);
use HTTP::Status qw(:constants);

use NGCP::Panel::Form::RewriteRule::AdminSetAPI;
use NGCP::Panel::Form::RewriteRule::ResellerSet;

sub item_name{
    return 'rewriteruleset';
}

sub resource_name{
    return 'rewriterulesets';
}

sub dispatch_path{
    return '/api/rewriterulesets/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-rewriterulesets';
}

sub get_form {
    my ($self, $c, $type) = @_;

    if ($type && $type eq "rules") {
        return (NGCP::Panel::Form::RewriteRule::RuleAPI->new);
    }
    if($c->user->roles eq "admin") {
        return (NGCP::Panel::Form::RewriteRule::AdminSetAPI->new( ctx => $c), [qw/reseller_id/]);
    } else {
        return (NGCP::Panel::Form::RewriteRule::ResellerSet->new( ctx => $c), [qw/reseller_id/]);
    }
}

sub post_process_hal_resource {
    my($self, $c, $item, $resource, $form) = @_;
    my $rwr_form = $self->get_form($c, "rules");
    my @rewriterules;
    for my $rule ( $item->voip_rewrite_rules->search_rs(undef, { order_by => { '-asc' => 'priority' } } )->all ) {
        my $rule_resource = { $rule->get_inflated_columns };
        return unless $self->validate_form(
            c => $c,
            form => $rwr_form,
            resource => $rule_resource,
            run => 0,
        );
        delete $rule_resource->{set_id};
        push @rewriterules, $rule_resource;
    }
    $resource->{rewriterules} = \@rewriterules;
    return $resource;
}

sub _item_rs {
    my ($self, $c, $type) = @_;
    my $item_rs;

    if($c->user->roles eq "admin") {
        $item_rs = $c->model('DB')->resultset('voip_rewrite_rule_sets');
    } elsif($c->user->roles eq "reseller") {
        $item_rs = $c->model('DB')->resultset('voip_rewrite_rule_sets')
            ->search_rs({reseller_id => $c->user->reseller_id});
    }
    return $item_rs;
}

sub process_form_resource{
    my($self,$c, $item, $old_resource, $resource, $form, $process_extras) = @_;
    my $reseller_id;
    if($c->user->roles eq "admin") {
        try {
            $reseller_id = $resource->{reseller_id}
                 || $c->user->contract->contact->reseller_id;
         }
    } elsif($c->user->roles eq "reseller") {
        $reseller_id = $c->user->reseller_id;
    }
    $resource->{reseller_id} = $reseller_id;
    return $resource;
}

sub check_resource{
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

sub check_duplicate{
    my($self, $c, $item, $old_resource, $resource, $form, $process_extras) = @_;

    my $schema = $c->model('DB');
    my $existing_item = $schema->resultset('voip_rewrite_rule_sets')->search_rs({
        name => $resource->{name}
    })->first;
    if ($existing_item && (!$item || $item->id != $existing_item->id)) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Ruleset with this 'name' already exists.");
        return;
    }
    return 1;
}

sub update_rewriterules{
    my($self, $c, $item, $rewriterules ) = @_; 

    my $schema = $c->model('DB');

    my $priority = 30;
    if (ref($rewriterules) ne "ARRAY") {
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "rewriterules must be an array.");
        die;
    }
    $item->voip_rewrite_rules->delete;
    for my $rule (@{ $rewriterules }) {
        try {
            $item->voip_rewrite_rules->create({
                priority => $priority++,
                %{ $rule },
            });
        } catch($e) {
            $c->log->error("failed to create rewriterules: $e"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create rewrite rules.");
            die;
        }
    }

}
1;
# vim: set tabstop=4 expandtab:
