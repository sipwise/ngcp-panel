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
    my $reseller_id;
    if ($c->user->roles eq "admin") {
    } elsif ($c->user->roles eq "reseller") {
        my $reseller_id = $c->user->reseller_id;
    } elsif ($c->user->roles eq "subscriberadmin" || $c->user->roles eq "subscriber") {
        my $reseller_id = $c->user->contract->contact->reseller_id;
    }
    if ($reseller_id) {
        $item_rs = $item_rs->search({
                '-or' => [
                        'autoprov_devices.reseller_id' => $c->user->reseller_id ,
                        'voip_preference_relations.reseller_id' => $c->user->reseller_id ,
                        'voip_preference_relations.voip_preference_id' => undef,
                    ],
            },{
                'join' => { 'voip_preference_relations' => 'autoprov_devices' },
        });
    }
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::get("NGCP::Panel::Form::Device::PreferenceAPI", $c);
}

sub check_resource{
    my($self, $c, $item, $old_resource, $resource, $form) = @_;

    my $schema = $c->model('DB');
    if ($resource->{dev_pref}) {
        if ($resource->{reseller_id}) {
            if ($resource->{autoprov_device_id}) {
                $c->log->error("reseller_id and autoprov_device_id can't be specified together.");
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "reseller_id and autoprov_device_id can't be specified together.");
                return;
            }   
            if ($c->user->roles eq "reseller") {
                $resource->{reseller_id} = $c->user->reseller_id;
            } else {
                unless($schema->resultset('resellers')->find($resource->{reseller_id})) {
                    $c->log->error("Invalid reseller_id '$$resource{reseller_id}'");
                    $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "invalid reseller_id '$$resource{reseller_id}'");
                    return;
                }
            }
        } elsif ($resource->{autoprov_device_id}) {
            my $rs = $schema->resultset('autoprov_devices')->search({ 
                id => $resource->{autoprov_device_id},
                ($c->user->roles eq "reseller") ? (reseller_id => $c->user->reseller_id) : (),
            });
            unless ($rs->first) {
                $c->log->error("Invalid autoprov_device_id '$$resource{autoprov_device_id}'");
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "invalid autoprov_device_id '$$resource{autoprov_device_id}'");
                return;
            }
        }
    }
    return 1;
}

sub process_form_resource{
    my($self,$c, $item, $old_resource, $resource, $form, $process_extras) = @_;
    if ($resource->{dev_pref} && !$resource->{reseller_id} && !$resource->{autoprov_device_id} ) {
        if ($c->user->roles eq "reseller") {
            $resource->{reseller_id} = $c->user->reseller_id;
        }    
    }
    return $resource;
}
1;
# vim: set tabstop=4 expandtab:
