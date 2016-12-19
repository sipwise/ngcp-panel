package NGCP::Panel::Utils::Events;

use Sipwise::Base;

use NGCP::Panel::Utils::DateTime qw();

sub insert {
    my %params = @_;
    my $c = $params{c};
    my $schema = $params{schema} // $c->model('DB');
    my $type = $params{type};
    my $subscriber = $params{subscriber};
    my $old = $params{old};
    my $new = $params{new};

    my $now_hires = NGCP::Panel::Utils::DateTime::current_local_hires;
    my $customer = $subscriber->contract;

    my $event = $schema->resultset('events')->create({
        type => $type,
        subscriber_id => $subscriber->id,
        reseller_id => $customer->contact->reseller_id,
        old_status => $old // '',
        new_status => $new // '',
        timestamp => $now_hires,
        export_status => 'unexported',
        exported_at => undef,
    });

    save_e164(
        schema => $schema,
        event => $event,
        number => $subscriber->primary_number,
        types_prefix => 'primary_number_',
        now_hires => $now_hires
    );

    my $bm_actual = get_actual_billing_mapping(c => $c,schema => $schema, contract => $customer, now => $now_hires);
    if ($bm_actual->billing_mappings->first->product->product_class eq 'pbxaccount') {
        my $pilot = $customer->voip_subscribers->search({
            'provisioning_voip_subscriber.is_pbx_pilot' => 1,
        },{
            join => 'provisioning_voip_subscriber',
        })->first;

        if ($pilot) {
            save_e164(
                schema => $schema,
                event => $event,
                number => $pilot->primary_number,
                types_prefix => 'pilot_primary_number_',
                now_hires => $now_hires
            );
        }
    }


}

sub save_e164 {
    my %params = @_;
    my ($schema,$event,$number,$types_prefix,$now_hires) = @params{qw/schema event number types_prefix now_hires/};
    if ($number) {
        my $tags_rs = $schema->resultset('events_tag');
        my $relations_rs = $schema->resultset('events_relation');
        $event->create_related("relation_data", {
            relation_id => $relations_rs->find({ type => $types_prefix.'_id' })->id,
            val => $number->id,
            event_timestamp => $now_hires,
        });
        if (length(my $cc = $number->cc) > 0) {
            $event->create_related("tag_data", {
                tag_id => $tags_rs->find({ type => $types_prefix.'cc' })->id,
                val => $cc,
                event_timestamp => $now_hires,
            });
        }
        if (length(my $ac = $number->ac) > 0) {
            $event->create_related("tag_data", {
                tag_id => $tags_rs->find({ type => $types_prefix.'ac' })->id,
                val => $ac,
                event_timestamp => $now_hires,
            });
        }
        if (length(my $sn = $number->sn) > 0) {
            $event->create_related("tag_data", {
                tag_id => $tags_rs->find({ type => $types_prefix.'sn' })->id,
                val => $sn,
                event_timestamp => $now_hires,
            });
        }
    }
}

sub get_actual_billing_mapping {
    my %params = @_;
    my ($c,$schema,$contract,$now) = @params{qw/c schema contract now/};
    $schema //= $c->model('DB');
    $now //= NGCP::Panel::Utils::DateTime::current_local;
    my $contract_create = NGCP::Panel::Utils::DateTime::set_local_tz($contract->create_timestamp // $contract->modify_timestamp);
    my $dtf = $schema->storage->datetime_parser;
    $now = $contract_create if $now < $contract_create; #if there is no mapping starting with or before $now, it would returns the mapping with max(id):
    return $schema->resultset('billing_mappings_actual')->search({ contract_id => $contract->id },{bind => [ ( $dtf->format_datetime($now) ) x 2, ($contract->id) x 2 ],})->first;
}

1;

# vim: set tabstop=4 expandtab:
