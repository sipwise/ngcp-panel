package NGCP::Panel::Role::API::SMS;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';


use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::SMS;
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Form::SMSAPI;

sub item_name {
    return 'sms';
}

sub resource_name{
    return 'sms';
}

sub get_form {
    my ($self, $c) = @_;
    return (NGCP::Panel::Form::SMSAPI->new, ['subscriber_id']);
}

sub hal_links {
    my($self, $c, $item, $resource, $form) = @_;
    my $b_subs_id = $item->provisioning_voip_subscriber->voip_subscriber->id;
    return [
        Data::HAL::Link->new(relation => "ngcp:subscribers", href => sprintf("/api/subscribers/%d", $b_subs_id)),
    ];
}

sub process_hal_resource {
    my($self, $c, $item, $resource, $form) = @_;
    $resource->{time} = NGCP::Panel::Utils::DateTime::to_string($resource->{time});
    return $resource;
}

sub _item_rs {
    my ($self, $c) = @_;
    my $item_rs;

    if($c->user->roles eq "admin") {
        $item_rs = $c->model('DB')->resultset('sms_journal');
    } elsif ($c->user->roles eq "reseller") {
        my $reseller_id = $c->user->reseller_id;
        $item_rs = $c->model('DB')->resultset('sms_journal')
            ->search_rs({
                    'reseller_id' => $reseller_id,
                } , {
                    join => { provisioning_voip_subscriber => {'subscriber' => {'contract' => 'contact'} } },
                });
    } elsif ($c->user->roles eq 'subscriber' || $c->user->roles eq 'subscriberadmin') {
        my $subscriber_uuid = $c->user->uuid;
        $item_rs = $c->model('DB')->resultset('sms_journal')
            ->search_rs({
                    'provisioning_voip_subscriber.uuid' => $subscriber_uuid,
                } , {
                    join => 'provisioning_voip_subscriber',
                });
    }

    return $item_rs;
}

sub check_resource{
    my($self, $c, $item, $old_resource, $resource, $form) = @_;

    unless(defined $resource->{subscriber_id}) { # TODO: might check in form
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Missing mandatory field 'subscriber_id'");
        return;
    }

    my $b_subscriber = $c->model('DB')->resultset('voip_subscribers')->find({
            id => $resource->{subscriber_id},
        });
    unless($b_subscriber) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'subscriber_id'.");
        return;
    }
    my $subscriber = $b_subscriber->provisioning_voip_subscriber;
    unless($subscriber) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid subscriber.");
        return;
    }
    $resource->{subscriber_id} = $subscriber->id;

    if($c->user->roles eq "admin" || $c->user->roles eq "reseller") {
        if($c->req->params->{skip_checks} && $c->req->params->{skip_checks} eq "true") {
            $c->log->info("skipping number checks for sending sms");
            return 1;
        }
    }

    return unless NGCP::Panel::Utils::SMS::check_numbers($c, $resource, $subscriber, sub {
            my ($err) = @_;
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, $err);
        });

    return 1;
}

1;
# vim: set tabstop=4 expandtab:
