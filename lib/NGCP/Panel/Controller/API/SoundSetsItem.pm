package NGCP::Panel::Controller::API::SoundSetsItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;
use HTTP::Status qw(:constants);

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

sub get_journal_methods{
    return [qw/handle_item_base_journal handle_journals_get handle_journalsitem_get handle_journals_options handle_journalsitem_options handle_journals_head handle_journalsitem_head/];
}

sub update_item_model {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    my $copy_from_default_params =  { map {$_ => delete $resource->{$_}} (qw/copy_from_default loopplay override language/) };
    $item->update($resource);
    if ($copy_from_default_params->{copy_from_default}) {
        my $error;
        my $handles_rs = NGCP::Panel::Utils::Sounds::get_handles_rs(c => $c, set_rs => $item);
        NGCP::Panel::Utils::Sounds::apply_default_soundset_files(
            c          => $c,
            lang       => $copy_from_default_params->{language},
            set_id     => $item->id,
            handles_rs => $handles_rs,
            loopplay   => $copy_from_default_params->{loopplay},
            override   => $copy_from_default_params->{override},
            error_ref  => \$error,
        );
    }

    if($item->contract_id && $item->contract_default && !$old_resource->{contract_default}) {
        $c->model('DB')->resultset('voip_sound_sets')->search({
            reseller_id => $item->reseller_id,
            contract_id => $item->contract_id,
            contract_default => 1,
            id => { '!=' => $item->id },
        })->update({ contract_default => 0 });

        foreach my $bill_subscriber($item->contract->voip_subscribers->all) {
            my $prov_subscriber = $bill_subscriber->provisioning_voip_subscriber;
            if($prov_subscriber) {
                my $pref_rs = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                    c => $c, prov_subscriber => $prov_subscriber, attribute => 'contract_sound_set',
                );
                unless($pref_rs->first) {
                    $pref_rs->create({ value => $item->id });
                }
            }
        }
    }

    return $item;
}

sub delete_item {
    my ($self, $c, $item) = @_;

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

    return 1;
}

1;

# vim: set tabstop=4 expandtab:
