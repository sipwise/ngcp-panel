package NGCP::Panel::Role::API::SoundHandles;
use NGCP::Panel::Utils::Generic qw(:all);
use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';

use HTTP::Status qw(:constants);

sub item_name{
    return 'soundhandle';
}

sub resource_name{
    return 'soundhandles';
}

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('voip_sound_handles')->search({}, {
        select => [qw/me.id me.name group.name/],
        as => [qw/id handle group/],
        join => 'group',
    });
    if ($c->user->roles eq 'subscriberadmin' ||
        $c->user->roles eq 'subscriber') {

        $item_rs = $item_rs->search({
                expose_to_customer => 1,
        });
    }
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::get("NGCP::Panel::Form::Sound::HandleAPI", $c);
}


1;
# vim: set tabstop=4 expandtab:
