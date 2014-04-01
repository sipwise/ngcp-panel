package NGCP::Panel::Role::API::RewriteRuleSets;
use Moose::Role;
use Sipwise::Base;
with 'NGCP::Panel::Role::API' => {
    -alias       =>{ item_rs  => '_item_rs', },
    -excludes    => [ 'item_rs' ],
};

use boolean qw(true);
use TryCatch;
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use JSON::Types;
use NGCP::Panel::Form::RewriteRule::AdminSet;
use NGCP::Panel::Form::RewriteRule::ResellerSet;
use NGCP::Panel::Form::RewriteRule::Rule;

sub get_form {
    my ($self, $c, $type) = @_;

    if ($type && $type eq "rules") {
        return NGCP::Panel::Form::RewriteRule::Rule->new;
    }
    if($c->user->roles eq "admin") {
        return NGCP::Panel::Form::RewriteRule::AdminSet->new;
    } else {
        return NGCP::Panel::Form::RewriteRule::ResellerSet->new;
    }
}

sub hal_from_item {
    my ($self, $c, $item, $type) = @_;
    my $form;
    my $rwr_form = $self->get_form($c, "rules");
    
    my %resource = $item->get_inflated_columns;
    my @rewriterules;
    for my $rule ( $item->voip_rewrite_rules->all ) {
        my $rule_resource = { $rule->get_inflated_columns };
        return unless $self->validate_form(
            c => $c,
            form => $rwr_form,
            resource => $rule_resource,
            run => 0,
        );
        push @rewriterules, $rule_resource;
    }

    my $hal = Data::HAL->new(
        links => [
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'collection', href => sprintf("%s", $self->dispatch_path)),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            Data::HAL::Link->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $item->id)),
            Data::HAL::Link->new(relation => "ngcp:$type", href => sprintf("/api/%s/%d", $type, $item->id)),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $form //= $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => \%resource,
        run => 0,
    );
    $resource{rewriterules} = \@rewriterules;
    $hal->resource(\%resource);
    return $hal;
}

sub item_rs {
    my ($self, $c, $type) = @_;
    my $item_rs;

    if($type eq "rulesets") {
        if($c->user->roles eq "admin") {
            $item_rs = $c->model('DB')->resultset('voip_rewrite_rule_sets');
        } elsif($c->user->roles eq "reseller") {
            $item_rs = $c->model('DB')->resultset('voip_rewrite_rule_sets')
                ->search_rs({reseller_id => $c->user->reseller_id});
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

    if($c->user->roles eq "reseller") {
        $resource->{reseller_id} = $old_resource->{reseller_id}; # prohibit change
    }

    if($old_resource->{reseller_id} != $resource->{reseller_id}) {
        my $reseller = $c->model('DB')->resultset('resellers')
            ->find($resource->{reseller_id});
        unless($reseller) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'reseller_id'");
            return;
        }
    }

    if ($resource->{rewriterules}) {
        $item->voip_rewrite_rules->delete;
        my $i = 30;
        for my $rule (@{ $resource->{rewriterules} }) {
            $item->voip_rewrite_rules->create({
                %{ $rule },
                priority => $i++,
            });
        }
    }

    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
    );
    #TODO: priority not accessible here
    $item->update($resource);

    return $item;
}

1;
# vim: set tabstop=4 expandtab:
