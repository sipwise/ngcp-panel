package NGCP::Panel::Role::API::SoundFiles;
use Moose::Role;
use Sipwise::Base;
with 'NGCP::Panel::Role::API' => {
    -alias       =>{ item_rs  => '_item_rs', },
    -excludes    => [ 'item_rs' ],
};

use boolean qw(true);
use TryCatch;
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use File::Temp qw(tempfile);
use NGCP::Panel::Form::Sound::FileAPI;
use NGCP::Panel::Utils::Sounds;

sub transcode_data {
    my ($self, $c, $from_codec, $resource) = @_;

    my ($fh, $filename) = tempfile();
    print $fh $resource->{data};
    try {
        $resource->{data} = NGCP::Panel::Utils::Sounds::transcode_file(
            $filename, $from_codec, $resource->{codec},
        );
    } catch($e) {
        $self->log->error("failed to transcode file: $e");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Failed to transcode file");
        return;
    }
    return $resource;
}

sub item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('voip_sound_files')->search(
        {}, 
        {
            prefetch => ['handle', 'set']
        });
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({
            'set.reseller_id' => $c->user->reseller_id
        },{
            join => 'set',
        });
    }
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::Sound::FileAPI->new;
}

sub hal_from_item {
    my ($self, $c, $item, $form) = @_;

    $form //= $self->get_form($c);
    my $resource = $self->resource_from_item($c, $item, $form);

    my $hal = Data::HAL->new(
        links => [
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'collection', href => sprintf("/api/%s/", $self->resource_name)),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            Data::HAL::Link->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $item->id)),
            Data::HAL::Link->new(relation => 'ngcp:soundsets', href => sprintf("/api/soundsets/%d", $item->set_id)),
            Data::HAL::Link->new(relation => 'ngcp:soundfilerecordings', href => sprintf("/api/soundfilerecordings/%d", $item->id)),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );


    $self->validate_form(
        c => $c,
        resource => $resource,
        form => $form,
        run => 0,
        exceptions => [ "set_id" ],
    );

    $resource->{id} = int($item->id);
    $hal->resource($resource);
    return $hal;
}

sub resource_from_item {
    my ($self, $c, $item, $form) = @_;

    my $resource = { $item->get_inflated_columns };
    delete $resource->{data};
    $resource->{filename} =~ s/\.pcma$/.wav/;

    $resource->{handle} = $item->handle->name;
    delete $resource->{handle_id};

    return $resource;
}

sub item_by_id {
    my ($self, $c, $id) = @_;
    my $item_rs = $self->item_rs($c);
    return $item_rs->find($id);
}

sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    my $recording = delete $resource->{data};
    $form //= $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
        exceptions => [ "set_id" ],
    );

    $resource->{loopplay} = ($resource->{loopplay} eq "true" || $resource->{loopplay}->is_int && $resource->{loopplay}) ? 1 : 0;


    my $set_rs = $c->model('DB')->resultset('voip_sound_sets')->search({ 
        id => $resource->{set_id} 
    });
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $set_rs = $set_rs->search({
            reseller_id => $c->user->reseller_id,
        });
    }
    my $set = $set_rs->first;
    unless($set) {
        $c->log->error("invalid set_id '$$resource{set_id}'");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Sound set does not exist");
        last;
    }

    my $handle_rs = $c->model('DB')->resultset('voip_sound_handles')->search({
        'me.name' => $resource->{handle},   
    });
    my $handle;
    if($set->contract_id) {
        $handle_rs = $handle_rs->search({
            'group.name' => { 'in' => ['pbx'] }
        },{
            join => 'group'
        });
        $handle = $handle_rs->first;
        unless($handle) {
            $c->log->error("invalid handle '$$resource{handle}', must be in group pbx or music_on_hold for a customer sound set");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Handle must be in group pbx or music_on_hold for a customer sound set");
            last;
        }
    } else {
        $handle_rs = $handle_rs->search({
            'group.name' => { 'not in' => ['pbx'] }
        },{
            join => 'group'
        });
        $handle = $handle_rs->first;
        unless($handle) {
            $c->log->error("invalid handle '$$resource{handle}', must not be in group pbx for a system sound set");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Handle must not be in group pbx for a system sound set");
            last;
        }
    }
    $resource->{handle_id} = $handle->id;

    if($resource->{handle} eq 'music_on_hold' && !$set->contract_id) {
        $resource->{codec} = 'PCMA';
        $resource->{filename} =~ s/\.[^.]+$/.pcma/;
    } else {
        $resource->{codec} = 'WAV';
    }
    $resource->{data} = $recording;
    $resource = $self->transcode_data($c, 'WAV', $resource);
    last unless($resource);
    delete $resource->{handle};

    $item->update($resource);

    return $item;
}

1;
# vim: set tabstop=4 expandtab:
