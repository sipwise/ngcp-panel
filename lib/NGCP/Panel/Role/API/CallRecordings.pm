package NGCP::Panel::Role::API::CallRecordings;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::Subscriber;

sub item_name {
    return 'callrecording';
}

sub resource_name {
    return 'callrecordings';
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::get("NGCP::Panel::Form::CallRecording::Recording", $c);
}

#Todo: maybe put it into Entities as common checking for all collections?
sub validate_request {
    my($self, $c) = @_;
    my $method = uc($c->request->method);
    if ($method eq 'GET') {
        if($c->req->param('tz') && !DateTime::TimeZone->is_valid_name($c->req->param('tz'))) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Query parameter 'tz' value is not a valid time zone");
            return;
        }
    }
    return 1;
}

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('recording_calls')->search_rs(
        undef, undef); #{ prefetch => 'recording_metakeys' }
    
    my $join_idx = 0;

    if($c->user->roles eq "reseller") {

        my $res_rs = $c->model('DB')->resultset('voip_subscribers')->search({
            'contact.reseller_id' => $c->user->reseller_id
        },{
            join => { 'contract' => 'contact' }
        });

        $join_idx += 1;
        $item_rs = $item_rs->search({
            status => { -in => [qw/completed confirmed/] },
            $self->get_join_alias('recording_metakeys%s.key',$join_idx) => 'uuid',
            $self->get_join_alias('recording_metakeys%s.value',$join_idx) => { -in => $res_rs->get_column('uuid')->as_query }
        },undef);
        
    } elsif ($c->user->roles eq "subscriberadmin") {

        my $res_rs = $c->model('DB')->resultset('provisioning_voip_subscribers')->search({
            'account_id' => $c->user->account_id
        });

        $join_idx += 1;
        $item_rs = $item_rs->search({
            status => { -in => [qw/completed confirmed/] },
            $self->get_join_alias('recording_metakeys%s.key',$join_idx) => 'uuid',
            $self->get_join_alias('recording_metakeys%s.value',$join_idx) => { -in => $res_rs->get_column('uuid')->as_query }
        },undef);
        
    } elsif ($c->user->roles eq "subscriber") {
        
        $join_idx += 1;
        $item_rs = $item_rs->search({
            status => { -in => [qw/completed confirmed/] },
            $self->get_join_alias('recording_metakeys%s.key',$join_idx) => 'uuid',
            $self->get_join_alias('recording_metakeys%s.value',$join_idx) => $c->user->uuid,
        },undef);

    }

    if($c->req->params->{subscriber_id}) {
        my $res_rs = $c->model('DB')->resultset('voip_subscribers')->search({
            id => $c->req->params->{subscriber_id}
        });
        
        $join_idx += 1;
        $item_rs = $item_rs->search({
            $self->get_join_alias('recording_metakeys%s.key',$join_idx) => 'uuid',
            $self->get_join_alias('recording_metakeys%s.value',$join_idx) => { -in => $res_rs->get_column('uuid')->as_query }
        },undef);

    }
    
    $item_rs = $self->apply_caller_filter(
        rs => $item_rs,
        params => $c->req->params,
        conjunctions => { 'recording_metakeys%s.key' => 'caller', },
        col => 'recording_metakeys%s.value',
        join_idx => \$join_idx,
    );
    $item_rs = $self->apply_callee_filter(
        rs => $item_rs,
        params => $c->req->params,
        conjunctions => { 'recording_metakeys%s.key' => 'callee', },
        col => 'recording_metakeys%s.value',
        join_idx => \$join_idx,
    );
    if ($join_idx > 0) {
        $item_rs = $item_rs->search_rs(undef,{
            join => [ ('recording_metakeys') x $join_idx ],
        });
    }

    return $item_rs;
}

sub hal_links {
    my($self, $c, $item, $resource, $form) = @_;

    my $res_rs = $item->recording_metakeys->search({
        key => 'uuid'
    });
    my @sub_ids = $c->model('DB')->resultset('voip_subscribers')->search({
        uuid => { -in => $res_rs->get_column('value')->as_query }
    })->get_column('id')->all;

    return [
        (map { Data::HAL::Link->new(relation => 'ngcp:subscribers', href => sprintf("/api/subscribers/%d", $_)) } @sub_ids),
        Data::HAL::Link->new(relation => 'ngcp:callrecordingstreams', href => sprintf("/api/callrecordingstreams/?recording_id=%d", $item->id)),
    ];
}

sub resource_from_item {
    my ($self, $c, $item, $form) = @_;

    my %resource = ();
    $resource{id} = int($item->id);
    $resource{status} = $item->status;
    $resource{callid} = $item->call_id;

    my $caller_meta_row = $item->recording_metakeys->search({key => 'caller'})->first;
    $resource{caller} = $caller_meta_row ? $caller_meta_row->value : undef;
    my $callee_meta_row = $item->recording_metakeys->search({key => 'callee'})->first;
    $resource{callee} = $callee_meta_row ? $callee_meta_row->value : undef;

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

1;
# vim: set tabstop=4 expandtab:
