package NGCP::Panel::Role::API::RewriteRules;
use NGCP::Panel::Utils::Generic qw(:all);

use strict;
use warnings;

use TryCatch;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Status qw(:constants);
use JSON::Types;
use NGCP::Panel::Form::RewriteRule::AdminSet;
use NGCP::Panel::Form::RewriteRule::ResellerSet;
use NGCP::Panel::Form::RewriteRule::RuleAPI;

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::RewriteRule::RuleAPI->new;
}

sub hal_from_item {
    my ($self, $c, $item, $type) = @_;
    my $form;

    my %resource = $item->get_inflated_columns;

    my $hal = NGCP::Panel::Utils::DataHal->new(
        links => [
            NGCP::Panel::Utils::DataHalLink->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'collection', href => sprintf("%s", $self->dispatch_path)),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $item->id)),
            NGCP::Panel::Utils::DataHalLink->new(relation => "ngcp:$type", href => sprintf("/api/%s/%d", $type, $item->id)),
            NGCP::Panel::Utils::DataHalLink->new(relation => "ngcp:rewriterulesets", href => sprintf("/api/rewriterulesets/%d", $item->set_id)),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $form //= $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => \%resource,
        run => 0,
        exceptions => [qw/set_id/],
    );

    $resource{match_pattern} = $form->inflate_match_pattern($resource{match_pattern});
    $resource{replace_pattern} = $form->inflate_replace_pattern($resource{replace_pattern});

    $hal->resource(\%resource);
    return $hal;
}

sub _item_rs {
    my ($self, $c, $type) = @_;
    my $item_rs;

    if($type eq "rules") {
        if($c->user->roles eq "admin") {
            $item_rs = $c->model('DB')->resultset('voip_rewrite_rules');
        } elsif ($c->user->roles eq "reseller") {
            $item_rs = $c->model('DB')->resultset('voip_rewrite_rules')->search_rs({
                    'ruleset.reseller_id' => $c->user->reseller_id,
                },{
                    join => 'ruleset'
                });
        }
    } else {
        die "You should not reach this";
    }
    return $item_rs;
}

sub item_by_id {
    my ($self, $c, $id, $type) = @_;

    my $item_rs = $self->item_rs($c, $type);
    return $item_rs->find($id);
}

sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    delete $resource->{id};

    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
        exceptions => [qw/set_id/],
    );

    $resource->{match_pattern} = $form->values->{match_pattern};
    $resource->{replace_pattern} = $form->values->{replace_pattern};

    $item->update($resource);

    return $item;
}

1;
# vim: set tabstop=4 expandtab:
