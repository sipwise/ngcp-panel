package NGCP::Panel::Controller::API::SoundSetsItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::SoundSets/;

__PACKAGE__->set_config({
    allowed_roles => {
        Default => [qw/admin reseller subscriberadmin/],
        Journal => [qw/admin reseller subscriberadmin/],
    }
});

sub allowed_methods{
    return [qw/GET OPTIONS HEAD PATCH PUT DELETE/];
}

sub journal_query_params {
    my($self,$query_params) = @_;
    return $self->get_journal_query_params($query_params);
}

sub DELETE :Allow {
    my ($self, $c, $id) = @_;

    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $item = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, soundset => $item);

        last unless $self->add_delete_journal_item_hal($c,sub {
            my $self = shift;
            my ($c) = @_;
            my $_form = $self->get_form($c);
            return $self->hal_from_item($c, $item, $_form); });        
        
        if($item->contract_id) {
            my $pref_rs = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                c => $c, attribute => 'contract_sound_set',
            );
            $pref_rs->search({ value => $item->id })->delete;
        }

        foreach my $p(qw/usr dom peer/) {
            $c->model('DB')->resultset("voip_".$p."_preferences")->search({
                'attribute.attribute' => 'sound_set',
                value => $item->id,
            },{
                join => 'attribute',
            })->delete_all; # explicit delete_all, otherwise query fails
        }
        
        $item->delete;

        $guard->commit;

        $c->response->status(HTTP_NO_CONTENT);
        $c->response->body(q());
    }
    return;
}

sub get_journal_methods{
    return [qw/handle_item_base_journal handle_journals_get handle_journalsitem_get handle_journals_options handle_journalsitem_options handle_journals_head handle_journalsitem_head/];
}

1;

# vim: set tabstop=4 expandtab:
