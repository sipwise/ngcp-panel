package NGCP::Panel::Role::API::VoicemailGreetings;

use parent qw/NGCP::Panel::Role::API/;

use Sipwise::Base;
use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::Generic qw(:all);
use NGCP::Panel::Utils::Subscriber;

sub item_name {
    return 'voicemailgreetings';
}

sub resource_name{
    return 'voicemailgreetings';
}

sub dispatch_path{
    return '/api/voicemailgreetings/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-voicemailgreetings';
}

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('voicemail_spool')->search({
        'msgnum'   => '-1',
        '-or' => [
            'dir' => { like => '/var/spool/asterisk/voicemail/%/unavail' },
            'dir' => { like => '/var/spool/asterisk/voicemail/%/busy' },
            'dir' => { like => '/var/spool/asterisk/voicemail/%/greet' },
            'dir' => { like => '/var/spool/asterisk/voicemail/%/temp' },
        ],
        'voip_subscriber.id' => { '!=' => undef },
        'voip_subscriber.status' => { '!=' => 'terminated' }
    },{
        join => { 'mailboxuser' => { 'provisioning_voip_subscriber' => 'voip_subscriber' } },
        '+select' => [qw/voip_subscriber.id/],
        '+as' => [qw/subscriber_id/],
    });
    if ($c->user->roles eq "admin" || $c->user->roles eq "ccareadmin") {
    } elsif ($c->user->roles eq "reseller" || $c->user->roles eq "ccare") {
        $item_rs = $item_rs->search({
            'contact.reseller_id' => $c->user->reseller_id
        },{
            join => { mailboxuser => {
                provisioning_voip_subscriber => {
                    voip_subscriber => {
                        contract => 'contact'
                    }
                }
            } }
        });
    } elsif ($c->user->roles eq "subscriberadmin") {
        $item_rs = $item_rs->search_rs({
            'contract.id' => $c->user->account_id,
        },{
            join => { 'mailboxuser' => { 'provisioning_voip_subscriber' =>
                { 'voip_subscriber' => 'contract' } } },
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
    return (NGCP::Panel::Form::get("NGCP::Panel::Form::Voicemail::GreetingAPI", $c));
}

sub process_hal_resource{
    my $self = shift;
    my ($c, $item, $resource, $form) = @_;
    $resource->{dir} =  NGCP::Panel::Utils::Subscriber::get_subscriber_voicemail_type(c => $c, dir => $resource->{dir} );
    return $resource;
}

sub process_form_resource{
    my($self, $c, $item, $old_resource, $resource, $form, $process_extras) = @_;
    try{
        NGCP::Panel::Utils::Subscriber::convert_voicemailgreeting( 
            c => $c, 
            upload => $resource->{greetingfile},
            converted_data_ref => \$process_extras->{binary_ref},
        );
    } catch($e) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, $e);
        return;
    }
    return 1;
}

sub check_resource{
    my($self, $c, $item, $old_resource, $resource, $form, $process_extras) = @_;


    #TODO: Move subscriber checking to some checking collections
    my $subscriber_rs = $c->model('DB')->resultset('voip_subscribers')->search({
        'me.status' => { '!=' => 'terminated' },
        'me.id'     => $resource->{subscriber_id},
    });
    if ($c->user->roles eq 'reseller' || $c->user->roles eq "ccare") {
        $subscriber_rs = $subscriber_rs->search({
            'contact.reseller_id' => $c->user->reseller_id,
        },{
            join => { 'contract' => 'contact'},
        });
    } elsif($c->user->roles eq 'subscriberadmin') {
        $subscriber_rs = $subscriber_rs->search({
            'contract.id' => $c->user->account_id,
        },{
            join => { 'contract' => 'contact'},
        });
    } elsif ($c->user->roles eq 'subscriber') {
        $subscriber_rs = $subscriber_rs->search({
            'me.uuid' => $c->user->uuid,
        });
    }
    my $billing_subscriber = $subscriber_rs->first;
    unless($billing_subscriber) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'subscriber_id'.");
        return;
    }

    my $subscriber = $billing_subscriber->provisioning_voip_subscriber;
    unless($subscriber) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid subscriber.");
        return;
    }

    my $voicemail_subscriber =  $subscriber->voicemail_user;
    unless($voicemail_subscriber) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "No voicemail user found for subscriber uuid ".$subscriber->uuid);
        return;
    }

    $c->stash->{checked}->{subscriber} = $subscriber;
    $c->stash->{checked}->{voicemail_subscriber} = $voicemail_subscriber;

    return 1;
}

sub check_duplicate{
    my($self, $c, $item, $old_resource, $resource, $form, $process_extras) = @_;

    my $rs = $self->item_rs($c);
    
    my $existing_item = $rs->search({
        'voip_subscriber.id' => $resource->{subscriber_id},
        'me.dir'             => {like => '%/'.$resource->{dir}},
    })->first;
    if($existing_item && (!$item || $item->id != $existing_item->id)) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, 'Voicemail greeting for the type "'.$resource->{dir}.'" and subscriber id "'.$resource->{subscriber_id}.'" already exists');
        return;
    }

    return 1;
}


1;
# vim: set tabstop=4 expandtab:
