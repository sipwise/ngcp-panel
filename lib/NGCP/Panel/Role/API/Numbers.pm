package NGCP::Panel::Role::API::Numbers;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';

use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Status qw(:constants);
use JSON::Types;
use NGCP::Panel::Form;
use NGCP::Panel::Utils::XMLDispatcher;
use NGCP::Panel::Utils::Prosody;

sub get_form {
    my ($self, $c) = @_;
    if($c->user->roles eq "admin") {
        return NGCP::Panel::Form::get("NGCP::Panel::Form::Number::AdminAPI", $c);
    } elsif($c->user->roles eq "reseller") {
        #return NGCP::Panel::Form::get("NGCP::Panel::Form::Number::ResellerAPI", $c);
        # there is currently no difference in the form
        return NGCP::Panel::Form::get("NGCP::Panel::Form::Number::SubadminAPI", $c);
    } elsif($c->user->roles eq "subscriberadmin") {
        return NGCP::Panel::Form::get("NGCP::Panel::Form::Number::SubadminAPI", $c);
    }
    return;
}

sub hal_from_item {
    my ($self, $c, $item, $form) = @_;
    my %resource = $item->get_inflated_columns;

    my $hal = NGCP::Panel::Utils::DataHal->new(
        links => [
            NGCP::Panel::Utils::DataHalLink->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'collection', href => sprintf("/api/%s/", $self->resource_name)),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $item->id)),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'ngcp:subscribers', href => sprintf("/api/subscribers/%d", $item->subscriber_id)),
            $self->get_journal_relation_link($item->id),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $form //= $self->get_form($c);

    $self->validate_form(
        c => $c,
        resource => \%resource,
        form => $form,
        run => 0,
    );

    $resource{id} = int($item->id);
    if($c->user->roles eq "admin") {
        $resource{reseller_id} = int($item->reseller_id);
    }

    $hal->resource({%resource});
    return $hal;
}

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('voip_numbers')->search({
        'me.reseller_id' => { '!=' => undef },
        'me.subscriber_id' => { '!=' => undef },
        'subscriber.status' => { '!=' => 'terminated' },
    },{
        '+select' => [\'if(me.id=subscriber.primary_number_id,1,0)'],
        '+as' => ['is_primary'],
        join => 'subscriber'
    });
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({
            'me.reseller_id' => $c->user->reseller_id,
        });
    } elsif($c->user->roles eq "subscriberadmin") {
        $item_rs = $item_rs->search({
            'subscriber.contract_id' => $c->user->account_id,
        });
    }

    if($c->req->param('type') && $c->req->param('type') eq "primary") {
        $item_rs = $item_rs->search({
            'voip_subscribers.id' => { '!=' => undef },
        }, {
            join => ['subscriber', 'voip_subscribers'],
        });
    } elsif($c->req->param('type') && $c->req->param('type') eq "alias") {
        $item_rs = $item_rs->search({
            'voip_subscribers.id' => { '=' => undef },
        }, {
            join => ['subscriber', 'voip_subscribers'],
        });
    }
    return $item_rs;
}

sub item_by_id {
    my ($self, $c, $id) = @_;

    my $item_rs = $self->item_rs($c);
    return $item_rs->find($id);
}

sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;
    my $schema = $c->model('DB');

    # we maybe want to remove such checks to compare readonly fields:
    foreach my $field(qw/cc ac sn is_primary/) {
        $old_resource->{$field} //= '';
        $resource->{$field} //= '';
        unless($old_resource->{$field} eq $resource->{$field}) {
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

    my $sub = $schema->resultset('voip_subscribers')
        ->find($resource->{subscriber_id});
    unless($sub) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'subscriber_id', does not exist.");
        return;
    }
    if($c->user->roles eq "subscriberadmin" && $sub->contract_id != $c->user->account_id) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'subscriber_id', does not exist.");
        return;
    }
    my $old_sub = $schema->resultset('voip_subscribers')->find($old_resource->{subscriber_id});
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
                    { e164 => { cc => $_->cc, ac => $_->ac, sn => $_->sn } };
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
                    { e164 => { cc => $_->cc, ac => $_->ac, sn => $_->sn } };
                }
            }
        } @{ $newalias } ];
        push @{ $newalias }, { e164 => { cc => $item->cc, ac => $item->ac, sn => $item->sn } };

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
        $c->log->error("failed to update number: $e");
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to update number.");
        return;
    }

    # reload item, in case the id changed (which shouldn't happen)
    $item = $self->_item_rs($c)->find({
        cc => $item->cc, ac => $item->ac, sn => $item->sn
    });

    return $item;
}

1;
# vim: set tabstop=4 expandtab:
