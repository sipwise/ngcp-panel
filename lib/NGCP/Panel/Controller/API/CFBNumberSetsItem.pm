package NGCP::Panel::Controller::API::CFBNumberSetsItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::CFBNumberSets/;

use HTTP::Headers qw();
use HTTP::Status qw(:constants);

__PACKAGE__->set_config({
    allowed_roles => {
        Default => [qw/admin reseller subscriberadmin subscriber/],
        Journal => [qw/admin reseller/],
    },
    PATCH => { ops => [qw/add replace remove copy/] },
});

sub allowed_methods{
    return [qw/GET OPTIONS HEAD PATCH PUT DELETE/];
}

sub get_journal_methods{
    return [qw/handle_item_base_journal handle_journals_get handle_journalsitem_get handle_journals_options handle_journalsitem_options handle_journals_head handle_journalsitem_head/];
}

sub update_item_model {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    delete $resource->{id};
    my $subscriber = $c->stash->{checked}->{subscriber};

    try {
        $item->update({
                name => $resource->{name},
                mode => $resource->{mode},
                (defined $resource->{is_regex} ? (is_regex => $resource->{is_regex}) : ()),
                subscriber_id => $subscriber->id,
            })->discard_changes;
        $item->voip_cf_bnumbers->delete;
        for my $s ( @{$resource->{bnumbers}} ) {
            $item->create_related("voip_cf_bnumbers", {
                    bnumber => $s->{bnumber},
                });
        }
    } catch($e) {
        $c->log->error("failed to update cfbnumberset: $e");
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create cfbnumberset.");
        return;
    };

    return $item;
}


1;

# vim: set tabstop=4 expandtab:
