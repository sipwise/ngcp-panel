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


    $schema->resultset('events')->create({
        type => $type,
        subscriber_id => $subscriber->id,
        reseller_id => $subscriber->contract->contact->reseller_id,
        old_status => $old // '',
        new_status => $new // '',
        timestamp => NGCP::Panel::Utils::DateTime::current_local_hires,
        export_status => 'unexported',
        exported_at => undef,
    });
}


1;

# vim: set tabstop=4 expandtab:
