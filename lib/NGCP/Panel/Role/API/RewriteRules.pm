package NGCP::Panel::Role::API::RewriteRules;

use parent qw/NGCP::Panel::Role::API/;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);

use HTTP::Status qw(:constants);
use NGCP::Panel::Form::RewriteRule::RuleAPI;

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
    return ( NGCP::Panel::Form::RewriteRule::RuleAPI->new, ['set_id'] );
}

sub hal_links{
    my($self, $c, $item, $resource, $form) = @_;
    return [
        NGCP::Panel::Utils::DataHalLink->new(relation => "ngcp:rewriterulesets", href => sprintf("/api/rewriterulesets/%d", $item->set_id)),
    ];
}


sub update_item_model {
    my($self, $c, $item, $old_resource, $resource, $form, $process_extras) = @_;

    delete $resource->{id};
    $resource->{match_pattern} = $form->values->{match_pattern};
    $resource->{replace_pattern} = $form->values->{replace_pattern};

    $item->update($resource);

    return $item;
}

sub post_process_commit{
    my($c, $action, $item, $old_resource, $resource, $form, $process_extras) = @_;
    NGCP::Panel::Utils::Rewrite::sip_dialplan_reload($c);
}

1;
# vim: set tabstop=4 expandtab:
