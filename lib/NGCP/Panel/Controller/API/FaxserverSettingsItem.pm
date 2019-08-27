package NGCP::Panel::Controller::API::FaxserverSettingsItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::API::Subscribers;

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::FaxserverSettings/;

__PACKAGE__->set_config({
    allowed_roles => {
        Default => [qw/admin reseller ccareadmin ccare subscriber subscriberadmin/],
        Journal => [qw/admin reseller ccareadmin ccare subscriber subscriberadmin/],
    },
    PATCH => { ops => [qw/add replace remove copy/] },
});

sub allowed_methods{
    return [qw/GET OPTIONS HEAD PATCH PUT/];
}

sub journal_query_params {
    my($self,$query_params) = @_;
    return $self->get_journal_query_params($query_params);
}

sub get_journal_methods{
    return [qw/handle_item_base_journal handle_journals_get handle_journalsitem_get handle_journals_options handle_journalsitem_options handle_journals_head handle_journalsitem_head/];
}


sub update_item_model {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    my $billing_subscriber = NGCP::Panel::Utils::API::Subscribers::get_active_subscriber($self, $c, $item->id);
    unless($billing_subscriber) {
        $c->log->error("invalid subscriber id $item->id for fax send");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Fax subscriber not found.");
        return;
    }
    delete $resource->{id};
    my $prov_subs = $item->provisioning_voip_subscriber;
    die "need provisioning_voip_subscriber" unless $prov_subs;
    my $prov_subscriber_id = $prov_subs->id;
    my $destinations_rs = $prov_subs->voip_fax_destinations;

    if (! exists $resource->{destinations} ) {
        $resource->{destinations} = [];
    }
    if (ref $resource->{destinations} ne "ARRAY") {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid field 'destinations'. Must be an array.");
        return;
    }

    my %update_fields = %{ $resource };
    delete $update_fields{destinations};

    try {
        $prov_subs->delete_related('voip_fax_preference');
        $destinations_rs->delete;
        $prov_subs->create_related('voip_fax_preference', \%update_fields);
        $prov_subs->discard_changes; #reload

        for my $dest (@{ $resource->{destinations} }) {
            $destinations_rs->create($dest);
        }
    } catch($e) {
        $c->log->error("Error Updating faxserversettings: $e");
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "faxserversettings could not be updated.");
        return;
    };

    return $item;
}


1;

# vim: set tabstop=4 expandtab:
