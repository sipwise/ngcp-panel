package NGCP::Panel::Role::API::SoundFiles;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use File::Temp qw(tempfile);
use NGCP::Panel::Utils::Sounds;
use NGCP::Panel::Utils::Sems;
use NGCP::Panel::Utils::Generic;

sub transcode_data {
    my ($self, $c, $from_codec, $resource) = @_;

    my ($fh, $filename) = tempfile(SUFFIX => ".$from_codec");
    print $fh $resource->{data};
    try {
        $resource->{data} = NGCP::Panel::Utils::Sounds::transcode_file(
            $filename, uc($from_codec), $resource->{codec},
        );
    } catch($e) {
        $c->log->error("failed to transcode file: $e");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Failed to transcode file");
        return;
    }
    return $resource;
}

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('voip_sound_files')->search(
        {},
        {
            prefetch => ['handle', 'set'],
        });
    if ($c->user->roles eq "admin") {
    } elsif ($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({
            'set.reseller_id' => $c->user->reseller_id,
        },{
            join => 'set',
        });
    } elsif ($c->user->roles eq "subscriberadmin") {
        $item_rs = $item_rs->search({
            'set.contract_id' => $c->user->account_id,
        },{
            join => 'set',
        });
    } elsif ($c->user->roles eq "subscriber") {
        return;
    }
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::get("NGCP::Panel::Form::Sound::FileAPI", $c);
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
    );

    $resource->{id} = int($item->id);
    $hal->resource($resource);
    return $hal;
}

sub resource_from_item {
    my ($self, $c, $item, $form) = @_;

    my $resource = { $item->get_inflated_columns };
    delete $resource->{data};
    $resource->{filename} =~ s/\.pcma$/.wav/ if $resource->{filename};

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
    );

    $resource->{loopplay} = ($resource->{loopplay} eq "true" || is_int($resource->{loopplay}) && $resource->{loopplay}) ? 1 : 0;

    my $set_rs = $c->model('DB')->resultset('voip_sound_sets')->search({
        id => $resource->{set_id},
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
        return;
    }

    my $handle_rs = $c->model('DB')->resultset('voip_sound_handles')->search({
        'me.name' => $resource->{handle},
    });
    my $handle;
    if($set->contract_id) {
        $handle_rs = $handle_rs->search({
            'group.name' => { 'in' => ['pbx', 'music_on_hold', 'digits'] },
        },{
            join => 'group',
        });
        $handle = $handle_rs->first;
        unless($handle) {
            $c->log->error("invalid handle '$$resource{handle}', must be in group pbx, music_on_hold or digits for a customer sound set");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Handle must be in group pbx, music_on_hold or digits for a customer sound set");
            return;
        }
    } else {
        $handle_rs = $handle_rs->search({
            'group.name' => { 'not in' => ['pbx'] },
        },{
            join => 'group',
        });
        $handle = $handle_rs->first;
        unless($handle) {
            $c->log->error("invalid handle '$$resource{handle}', must not be in group pbx for a system sound set");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Handle must not be in group pbx for a system sound set");
            return;
        }
    }
    $resource->{handle_id} = $handle->id;

    # clear audio caches
    my $group_name = $handle->group->name;
    try {
        NGCP::Panel::Utils::Sems::clear_audio_cache($c, $set->id, $handle->name, $group_name);
    } catch ($e) {
        $c->log->error("Failed to clear audio cache for " . $group_name . " at appserver",);
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, 'Failed to clear audio cache.');
        return;
    }

    my $from_codec = mime_type_to_extension($c->req->content_type) // '';
    $resource->{codec} = 'WAV';
    $resource->{data} = $recording;
    $resource = $self->transcode_data($c, $from_codec, $resource);
    unless ($resource) {
        $c->log->error("Failed to transcode sound file",);
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, 'Failed to transcode sound file');
        return;
    }
    delete $resource->{handle};

    try {
        if ($item) {
            $item->update($resource);
        } else {
            $item = $c->model('DB')->resultset('voip_sound_files')->create($resource);
        }
    } catch($e) {
        $c->log->error("failed to create soundfile: $e"); # TODO: user, message, trace, ...
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create soundfile.");
        return;
    }

    return $item;
}

1;
# vim: set tabstop=4 expandtab:
