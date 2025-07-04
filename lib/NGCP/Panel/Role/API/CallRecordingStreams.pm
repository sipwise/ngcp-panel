package NGCP::Panel::Role::API::CallRecordingStreams;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::Subscriber;

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('recording_streams');
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {

        my $res_rs = $c->model('DB')->resultset('voip_subscribers')->search({
            'contact.reseller_id' => $c->user->reseller_id
        }, {
            join => { 'contract' => 'contact' }
        });

        $item_rs = $item_rs->search({
            status => { -in => [qw/completed confirmed/] },
            'recording_metakeys.key' => 'uuid',
            'recording_metakeys.value' => { -in => $res_rs->get_column('uuid')->as_query }
        },{
            join => { 'recording_call' => 'recording_metakeys' },
        });
    } elsif ($c->user->roles eq "subscriberadmin") {

        my $res_rs = $c->model('DB')->resultset('provisioning_voip_subscribers')->search({
            'account_id' => $c->user->account_id
        });

        $item_rs = $item_rs->search({
            status => { -in => [qw/completed confirmed/] },
            'recording_metakeys.key' => 'uuid',
            'recording_metakeys.value' => { -in => $res_rs->get_column('uuid')->as_query }
        },{
            join => { 'recording_call' => 'recording_metakeys' },
        });
    } elsif ($c->user->roles eq "subscriber") {
        $item_rs = $item_rs->search({
            status => { -in => [qw/completed confirmed/] },
            'recording_metakeys.key' => 'uuid',
            'recording_metakeys.value' => $c->user->uuid,
        },{
            join => { 'recording_call' => 'recording_metakeys' },
        });
    }

    if($c->req->params->{subscriber_id}) {
        my $res_rs = $c->model('DB')->resultset('voip_subscribers')->search({
            id => $c->req->params->{subscriber_id}
        });
        $item_rs = $item_rs->search({
            'recording_metakeys.key' => 'uuid',
            'recording_metakeys.value' => { -in => $res_rs->get_column('uuid')->as_query }
        },{
            join => { 'recording_call' => 'recording_metakeys' },
        });
    }
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::get("NGCP::Panel::Form::CallRecording::Stream", $c);
}

sub hal_from_item {
    my ($self, $c, $item, $form) = @_;

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
            Data::HAL::Link->new(relation => 'ngcp:callrecordings', href => sprintf("/api/callrecordings/%d", $item->call)),
            Data::HAL::Link->new(relation => 'ngcp:callrecordingfiles', href => sprintf("/api/callrecordingfiles/%d", $item->id)),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    my $resource = $self->resource_from_item($c, $item, $form);

    $self->expand_fields($c, $resource);
    $hal->resource($resource);
    return $hal;
}

sub resource_from_item {
    my ($self, $c, $item, $form) = @_;

    my %resource = ();
    $resource{id} = int($item->id);
    $resource{type} = $item->output_type;
    $resource{recording_id} = $item->call;
    $resource{format} = lc($item->file_format);
    $resource{sample_rate} = $item->sample_rate;
    $resource{channels} = $item->channels;
    $resource{transcript_status} = $item->transcript_status;
    $resource{transcript} = $item->transcript;

    my $datetime_fmt = DateTime::Format::Strptime->new(
        pattern => '%F %T',
    );
    my $tz = $c->req->param('tz');
    unless($tz && DateTime::TimeZone->is_valid_name($tz)) {
        $tz = undef;
    }
    if($item->start_timestamp) {
        if($tz) {
            $item->start_timestamp->set_time_zone($tz);
        }
        $resource{start_time} = $datetime_fmt->format_datetime($item->start_timestamp);
        # no need to show millisec precision here, I guess...
        #$resource{start_time} .= '.'.sprintf("%03d",$item->start_timestamp->millisecond)
        #    if $item->start_timestamp->millisecond > 0.0;
    } else {
        $resource{start_time} = undef;
    }
    if($item->end_timestamp) {
        if($tz) {
            $item->end_timestamp->set_time_zone($tz);
        }
        $resource{end_time} = $datetime_fmt->format_datetime($item->end_timestamp);
        #$resource{end_time} .= '.'.sprintf("%03d",$item->end_timestamp->millisecond)
        #    if $item->end_timestamp->millisecond > 0.0;
    } else {
        $resource{end_time} = undef;
    }

    return \%resource;
}

sub item_by_id {
    my ($self, $c, $id) = @_;
    my $item_rs = $self->item_rs($c);
    return $item_rs->find($id);
}

1;
# vim: set tabstop=4 expandtab:
