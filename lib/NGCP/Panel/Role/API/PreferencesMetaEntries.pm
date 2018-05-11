package NGCP::Panel::Role::API::PreferencesMetaEntries;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);

sub _item_rs {
    my ($self, $c) = @_;
    my $item_rs = $c->model('DB')->resultset('voip_preferences')->search_rs({
            'me.dynamic' => 1,
        },{
            '+columns' => {'autoprov_device_id' => 'voip_preference_relations.autoprov_device_id'},
            'join'     => 'voip_preference_relations',
    });
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::get("NGCP::Panel::Form::Device::PreferenceAPI", $c);
}

1;
# vim: set tabstop=4 expandtab:
