package NGCP::Panel::Role::API::VoicemailGreetings;

use parent qw/NGCP::Panel::Role::API/;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);

use NGCP::Panel::Form::Voicemail::GreetingAPI;

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
        'duration' => { '!=' => '' },
        'msgnum' => '-1',
        'dir' => {-in => [qw/unavail busy/]},
        'voip_subscriber.id' => { '!=' => undef },
    },{
        join => { 'mailboxuser' => { provisioning_voip_subscriber => 'voip_subscriber' } }
    });
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({ 
            'contact.reseller_id' => $c->user->reseller_id 
        },{
            join => { mailboxuser => { provisioning_voip_subscriber => { voip_subscriber => { contract => 'contact' } } } }
        });
    }
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::Voicemail::GreetingAPI->new;
}

sub update_item{

}

1;
# vim: set tabstop=4 expandtab:
