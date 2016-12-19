package NGCP::Panel::Utils::Events;

use Sipwise::Base;

sub insert {
    my %params = @_;
    my $c = $params{c};
    my $schema = $params{schema} // $c->model('DB');
    my $type = $params{type};
    my $subscriber = $params{subscriber};
    my $old = $params{old};
    my $new = $params{new};

    my $now_hires = NGCP::Panel::Utils::DateTime::current_local_hires;

    my $event = $schema->resultset('events')->create({
        type => $type,
        subscriber_id => $subscriber->id,
        reseller_id => $subscriber->contract->contact->reseller_id,
        old_status => $old // '',
        new_status => $new // '',
        timestamp => $now_hires,
        export_status => 'unexported',
        exported_at => undef,
    });

    my $tags_rs = $schema->resultset('events_tag');
    my $relations_rs = $schema->resultset('events_relation');

    my $primary_number = $subscriber->primary_number;
    if ($primary_number) {
        $event->create_related("tag_data", {
            tag_id => $tags_rs->find({ type => 'number_cc' })->id,
            val => $primary_number->cc,
            event_timestamp => $now_hires,
        });
        $event->create_related("tag_data", {
            tag_id => $tags_rs->find({ type => 'number_ac' })->id,
            val => $primary_number->ac,
            event_timestamp => $now_hires,
        });
        $event->create_related("tag_data", {
            tag_id => $tags_rs->find({ type => 'number_sn' })->id,
            val => $primary_number->sn,
            event_timestamp => $now_hires,
        });
    }
}


1;

# vim: set tabstop=4 expandtab:
