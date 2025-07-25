package NGCP::Panel::Controller::API::SoundSetsItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;
use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::Sems;

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::SoundSets/;

__PACKAGE__->set_config({
    allowed_roles => {
        Default => [qw/admin reseller subscriberadmin/],
        Journal => [qw/admin reseller subscriberadmin/],
    },
    set_transaction_isolation => 'READ COMMITTED',
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

    my $old_parent_id = $old_resource->{parent_id};
    my $new_parent_id = $resource->{parent_id};
    if ((!defined $old_parent_id && defined $new_parent_id)
        || (defined $old_parent_id && !defined $new_parent_id)
        || (defined $old_parent_id && defined $new_parent_id && $old_parent_id != $new_parent_id)
    ) {
        $c->log->debug("Parent changed: clearing cache for set " . $item->id);
        NGCP::Panel::Utils::Sems::clear_audio_cache($c, $item->id);
    }

    my $copy_from_default_params =  { map {$_ => delete $resource->{$_}} (qw/copy_from_default loopplay replace_existing language/) };
    $item->update($resource);
    if ($copy_from_default_params->{copy_from_default}) {
        my $error;
        my $file_handles = NGCP::Panel::Utils::Sounds::get_file_handles(c => $c, set_id => $item->id);
        NGCP::Panel::Utils::Sounds::apply_default_soundset_files(
            c          => $c,
            lang       => $copy_from_default_params->{language},
            set_id     => $item->id,
            file_handles => $file_handles,
            loopplay   => $copy_from_default_params->{loopplay},
            override   => $copy_from_default_params->{replace_existing},
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

        NGCP::Panel::Utils::Sounds::contract_sound_set_propagate($c, $item->contract, $item->id);
    }

    return $item;
}

sub delete_item {
    my ($self, $c, $item) = @_;

    if ($c->user->roles eq 'subscriberadmin' &&
        (!$item->contract_id || $item->contract_id != $c->user->account_id)) {
            $self->error($c, HTTP_FORBIDDEN, "Cannot modify read-only sound set",
                         "does not belong to this subscriberadmin");
            return;
    }

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

    # clear audio cache of the current sound set and
    # and all potentially affected children sets
    NGCP::Panel::Utils::Sems::clear_audio_cache($c, $item->id);
    NGCP::Panel::Utils::Rtpengine::clear_audio_cache_set($c, $item->id);

    $item->delete;

    return 1;
}

1;

# vim: set tabstop=4 expandtab:
