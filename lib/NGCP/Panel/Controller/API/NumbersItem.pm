package NGCP::Panel::Controller::API::NumbersItem;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::Numbers/;

use HTTP::Status qw(:constants);
use JSON::Types;

__PACKAGE__->set_config({
    allowed_roles => {
        Default => [qw/admin reseller subscriberadmin/],
        Journal => [qw/admin reseller/],
    },
    set_transaction_isolation => 'READ COMMITTED',
});

sub allowed_methods{
    return [qw/GET PUT PATCH OPTIONS HEAD/];
}

sub journal_query_params {
    my($self,$query_params) = @_;
    return $self->get_journal_query_params($query_params);
}

sub get_journal_methods{
    return [qw/handle_item_base_journal handle_journals_get handle_journalsitem_get handle_journals_options handle_journalsitem_options handle_journals_head handle_journalsitem_head handle_journalsitem_put handle_journalsitem_patch/];
}

sub pre_process_form_resource {
    my($self,$c, $item, $old_resource, $resource, $form, $process_extras) = @_;

    if (!exists $resource->{is_devid} && defined $item->voip_dbalias) {
        $resource->{is_devid} = $item->voip_dbalias->is_devid;
    }
    if (!exists $resource->{devid_alias} && defined $item->voip_dbalias) {
        $resource->{devid_alias} = $item->voip_dbalias->devid_alias;
    }
    return 1;
}

sub update_item_model {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;
    my $schema = $c->model('DB');

    # we maybe want to remove such checks to compare readonly fields:
    foreach my $field(qw/cc ac sn is_primary/) {
        unless(($old_resource->{$field} // '') eq ($resource->{$field} // '')
            or ('JSON::false' eq ref $resource->{$field} and $old_resource->{$field} == 0)
            or ('JSON::true' eq ref $resource->{$field} and $old_resource->{$field} == 1)) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Field '$field' is not allowed to be updated via this API endpoint, use /api/subscriber/\$id instead.");
            return;
        }
    }

    $form //= $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
    );
    my @sub_ids = ($resource->{subscriber_id}, $old_resource->{subscriber_id});
    my %subs = map {
        $_ => $schema->resultset('voip_subscribers')->find(
            {id => $_},{for => 'update'}
        )
    } sort {$a <=> $b } @sub_ids;
    my ($sub,$old_sub) = @subs{@sub_ids};

    unless($sub) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'subscriber_id', does not exist.");
        return;
    }
    if($c->user->roles eq "subscriberadmin" && $sub->contract_id != $c->user->account_id) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'subscriber_id', does not exist.");
        return;
    }
    if($old_sub->primary_number_id == $old_resource->{id}) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Cannot reassign primary number, already at subscriber ".$old_sub->id);
        return;
    }

    try {

        # capture old subscriber's aliases
        my $old_aliases_before = NGCP::Panel::Utils::Events::get_aliases_snapshot(
            c => $c,
            schema => $schema,
            subscriber => $old_sub,
        );

        # capture new subscriber's aliases
        my $aliases_before = NGCP::Panel::Utils::Events::get_aliases_snapshot(
            c => $c,
            schema => $schema,
            subscriber => $sub,
        );

        my $oldalias = [$old_sub->voip_numbers->all];
        $oldalias = [ map {
            if($_->id == $old_sub->primary_number_id) {
                # filter primary number
                ();
            } else {
                if($_->id == $item->id) {
                    # filter number we're about to remove
                    ();
                } else {
                    # otherwise keep number
                    if (!defined $_->voip_dbalias) {
                        $c->log->debug("+++ no oldsub dbalias for sn " . $_->sn);
                    } else {
                        $c->log->debug("+++ oldsub dbalias for sn " . $_->sn . " is " . ($_->voip_dbalias->devid_alias//"undef"));
                    }
                    { e164 => {
                            cc => $_->cc, ac => $_->ac, sn => $_->sn,
                            is_devid => (defined $_->voip_dbalias ? $_->voip_dbalias->is_devid : 0),
                            devid_alias => (defined $_->voip_dbalias ? $_->voip_dbalias->devid_alias : undef),
                        }
                    };
                }
            }
        } @{ $oldalias } ];

        NGCP::Panel::Utils::Subscriber::update_subscriber_numbers(
            c => $c,
            schema => $schema,
            alias_numbers => $oldalias,
            reseller_id => $old_sub->contract->contact->reseller_id,
            subscriber_id => $old_sub->id,
        );

        my $newalias = [ $sub->voip_numbers->all ];
        $newalias = [ map {
            if($_->id == $sub->primary_number_id) {
                # filter primary number
                ();
            } else {
                if($_->id == $item->id) {
                    # filter number we're about to remove
                    ();
                } else {
                    # otherwise keep number
                    if (!defined $_->voip_dbalias) {
                        $c->log->debug("+++ no newsub dbalias for sn " . $_->sn);
                    } else {
                        $c->log->debug("+++ newsub dbalias for sn " . $_->sn . " is " . ($_->voip_dbalias->devid_alias//"undef"));
                    }
                    { e164 => {
                            cc => $_->cc, ac => $_->ac, sn => $_->sn,
                            is_devid => (defined $_->voip_dbalias ? $_->voip_dbalias->is_devid : 0),
                            devid_alias => (defined $_->voip_dbalias ? $_->voip_dbalias->devid_alias : undef),
                        }
                    };
                }
            }
        } @{ $newalias } ];

        use Data::Dumper; $c->log->debug(Dumper $resource);
        push @{ $newalias }, { e164 => {
                cc => $item->cc, ac => $item->ac, sn => $item->sn,
                is_devid => $resource->{is_devid} // 0,
                devid_alias => $resource->{devid_alias},
            }
        };

        NGCP::Panel::Utils::Subscriber::update_subscriber_numbers(
            c => $c,
            schema => $schema,
            alias_numbers => $newalias,
            reseller_id => $sub->contract->contact->reseller_id,
            subscriber_id => $sub->id,
        );

        # edr events for old sub
        my $old_sub_profile = $old_sub->provisioning_voip_subscriber->profile_id;
        NGCP::Panel::Utils::Events::insert_profile_events(
            c => $c, schema => $schema, subscriber_id => $old_sub->id,
            old => $old_sub_profile, new => $old_sub_profile,
            %$old_aliases_before,
        );

        # edr events for new sub
        my $new_sub_profile = $sub->provisioning_voip_subscriber->profile_id;
        NGCP::Panel::Utils::Events::insert_profile_events(
            c => $c, schema => $schema, subscriber_id => $sub->id,
            old => $new_sub_profile, new => $new_sub_profile,
            %$aliases_before,
        );

    } catch($e) {
        $c->log->error("failed to update number: " . $c->qs($e));
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to update number.");
        return;
    }

    $item = $self->_item_rs($c)->find({
        cc => $item->cc, ac => $item->ac, sn => $item->sn,
    });

    return $item;
}


1;

# vim: set tabstop=4 expandtab:
