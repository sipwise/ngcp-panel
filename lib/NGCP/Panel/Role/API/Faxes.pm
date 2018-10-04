package NGCP::Panel::Role::API::Faxes;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use DateTime::Format::Strptime;
use NGCP::Panel::Utils::Subscriber;
use NGCP::Panel::Utils::Fax;

sub resource_name{
    return 'faxes';
}

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('voip_fax_journal')->search({
        'voip_subscriber.id' => { '!=' => undef },
    },{
        join => { 'provisioning_voip_subscriber' => 'voip_subscriber' }
    });
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({
            'contact.reseller_id' => $c->user->reseller_id
        },{
            join => { provisioning_voip_subscriber => { voip_subscriber => { contract => 'contact' } } }
        });
    } elsif ($c->user->roles eq "subscriberadmin") {
        $item_rs = $item_rs->search_rs({
            'contract.id' => $c->user->account_id,
        },{
            join => { provisioning_voip_subscriber => { voip_subscriber => { contract => 'contact' } } }
        });
    } elsif ($c->user->roles eq "subscriber") {
        $item_rs = $item_rs->search_rs({
            'voip_subscriber.uuid' => $c->user->uuid,
        });
    }
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::get("NGCP::Panel::Form::Subscriber::WebfaxAPI", $c);
}

sub hal_links {
    my($self, $c, $item, $resource, $form) = @_;
    return [
        Data::HAL::Link->new(relation => 'ngcp:subscribers', href => sprintf("/api/subscribers/%d", $item->provisioning_voip_subscriber->voip_subscriber->id)),
        Data::HAL::Link->new(relation => 'ngcp:faxrecordings', href => sprintf("/api/faxrecordings/%d", $item->id)),
    ];
}

sub resource_from_item {
    my ($self, $c, $item, $form) = @_;

    $form //= $self->get_form($c);

    my $datetime_fmt = DateTime::Format::Strptime->new(
        pattern => '%F %T',
    );

    my $subscriber = $item->provisioning_voip_subscriber->voip_subscriber;

    my %resource = ();
    $resource{id} = int($item->id);
    $resource{time} = $datetime_fmt->format_datetime(
        NGCP::Panel::Utils::API::Calllist::apply_owner_timezone($self,$c,$item->time,
        NGCP::Panel::Utils::API::Calllist::get_owner_data($self,$c, undef, undef, 1)
    ));
    $resource{subscriber_id} = int($subscriber->id);
    foreach(qw/direction caller callee reason status quality filename/){
        $resource{$_} = $item->$_;
    }
    foreach(qw/duration pages signal_rate/){
        $resource{$_} = is_int($item->$_) ? $item->$_ : 0;
    }
    my $number_rewrite_mode = $c->request->query_params->{number_rewrite_mode} //
                              $c->config->{faxserver}->{number_rewrite_mode};
    my $data = $number_rewrite_mode eq 'extended'
               ? NGCP::Panel::Utils::Fax::process_extended_fax_journal_item(
                    $c, $item, $subscriber)
               : NGCP::Panel::Utils::Fax::process_fax_journal_item(
                    $c, $item, $subscriber);
    map { $resource{$_} = $data->{$_} } qw(caller callee);
    return \%resource;
}

1;
# vim: set tabstop=4 expandtab:
