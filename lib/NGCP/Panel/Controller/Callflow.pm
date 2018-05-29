package NGCP::Panel::Controller::Callflow;
use NGCP::Panel::Utils::Generic qw(:all);
use Sipwise::Base;

use parent 'Catalyst::Controller';

use NGCP::Panel::Form;

use NGCP::Panel::Utils::Callflow;
use NGCP::Panel::Utils::Navigation;
use NGCP::Panel::Utils::Message;

use HTML::Entities;
use MIME::Base64 qw(encode_base64url decode_base64url);

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    $c->detach('/denied_page')
        unless($c->config->{features}->{callflow});
    return 1;
}

sub root :Chained('/') :PathPart('callflow') :CaptureArgs(0) {
    my ( $self, $c ) = @_;

    $c->stash->{capture_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "min_timestamp", search => 0, title => $c->loc('Timestamp') },
        { name => "call_id", search => 1, title => $c->loc('Call-ID') },
        { name => "caller_uuid", search => 1, title => $c->loc('Caller UUID') },
        { name => "callee_uuid", search => 1, title => $c->loc('Callee UUID') },
        { name => "cseq_method", search => 1, title => $c->loc('Method') },
    ]);

}

sub index :Chained('root') :PathPart('') :Args(0) {
    my ( $self, $c ) = @_;

    $c->stash(
        template => 'callflow/list.tt',
    );

}

sub ajax :Chained('root') :PathPart('ajax') :Args(0) {
    my ( $self, $c ) = @_;

    my $calls_rs_cb = sub {
        my %params = @_;
        my $total_count =  $c->model('Storage')->resultset('messages')->search(undef,{group_by => 'call_id'})->count;
        my $base_rs =  $c->model('Storage')->resultset('messages_custom');
        my $searchstring = $params{searchstring} ? $params{searchstring}.'%' : '';

        my @bind_vals = (($searchstring) x 3, $params{offset}, $params{rows});

        my $new_rs = $base_rs->search(undef,{
            bind => \@bind_vals,
        });
        return ($new_rs, $total_count, $total_count);
    };

    NGCP::Panel::Utils::Datatables::process(
        $c,
        $calls_rs_cb,
        $c->stash->{capture_dt_columns},
        sub {
            my $item = shift;
            my %result;
            $result{call_id} = $item->call_id =~ s/(_b2b-1|_pbx-1)+$//r;
            $result{call_id_url} = encode_base64url($result{call_id});
            return %result;
        },
    );
    $c->detach( $c->view("JSON") );
}

sub callflow_base :Chained('root') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $callid) = @_;

    $c->stash->{callid} = decode_base64url($callid)
            =~ s/(_b2b-1|_pbx-1)+$//r
            =~ s/[^[:print:]]+//gr;  # remove non-printable chars to be sure for db-operation
}

sub get_pcap :Chained('callflow_base') :PathPart('pcap') :Args(0) {
    my ($self, $c) = @_;
    my $cid = $c->stash->{callid};

    my $packet_rs = $c->model('Storage')->resultset('packets')->search({
        'message.call_id' => { -in => [ $cid, $cid.'_b2b-1', $cid.'_pbx-1' ] },
    }, {
        join => { message_packets => 'message' },
    });

    my $packets = [ $packet_rs->all ];
    my $pcap = NGCP::Panel::Utils::Callflow::generate_pcap($packets);

    $c->response->header ('Content-Disposition' => 'attachment; filename="' . $cid . '.pcap"');
    $c->response->content_type('application/octet-stream');
    $c->response->body($pcap);
}

sub get_png :Chained('callflow_base') :PathPart('png') :Args(0) {
    my ($self, $c) = @_;
    my $cid = $c->stash->{callid};

    my $calls_rs = $c->model('Storage')->resultset('messages')->search({
        'me.call_id' => { -in => [ $cid, $cid.'_b2b-1', $cid.'_pbx-1' ] },
    }, {
        order_by => { -asc => 'timestamp' },
    });

    my $calls = [ $calls_rs->all ];
    my $png = NGCP::Panel::Utils::Callflow::generate_callmap_png($c, $calls);

    $c->response->header ('Content-Disposition' => 'attachment; filename="' . $cid . '.png"');
    $c->response->content_type('image/png');
    $c->response->body($png);
}

sub get_callmap :Chained('callflow_base') :PathPart('callmap') :Args(0) {
    my ($self, $c) = @_;
    my $cid = $c->stash->{callid};
    $c->stash->{template} = 'callflow/callmap.tt';

    my $calls_rs = $c->model('Storage')->resultset('messages')->search({
        'me.call_id' => { -in => [ $cid, $cid.'_b2b-1', $cid.'_pbx-1' ] },
    }, {
        order_by => { -asc => 'timestamp' },
    });

    my $calls = [ $calls_rs->all ];
    unless(@{ $calls }) {
         $c->log->error("No packets for call-id $cid found");
         $c->stash(messages => [{type => 'error', text => $c->loc('No packets for this Call-ID found.')}])
    } else {
        my $map = NGCP::Panel::Utils::Callflow::generate_callmap($c, $calls);
        $c->stash->{canvas} = $map;
    }
}

sub get_packet :Chained('callflow_base') :PathPart('packet') :Args() {
    my ($self, $c, $packet_id) = @_;
    my $cid = $c->stash->{callid};

    my $packet = $c->model('Storage')->resultset('messages')->find({
        'me.call_id' => { -in => [ $cid, $cid.'_b2b-1', $cid.'_pbx-1' ] },
        'me.id' => $packet_id,
    }, {
        order_by => { -asc => 'timestamp' },
    });

    return unless($packet);

    my $pkg = { $packet->get_inflated_columns };

    my $t = $packet->timestamp;
    my $tstamp = $t->ymd('-') . ' ' . $t->hms(':') . '.' . $t->microsecond;

    $pkg->{payload} = encode_entities($pkg->{payload});
    $pkg->{payload} =~ s/\r//g;
    $pkg->{payload} =~ s/([^\n]{120})/$1<br\/>/g;
    $pkg->{payload} =~ s/^([^\n]+)\n/<b>$1<\/b>\n/;
    $pkg->{payload} = $tstamp .' ('.$t->hires_epoch.')<br/>'.
        $pkg->{src_ip}.':'.$pkg->{src_port}.' &rarr; '. $pkg->{dst_ip}.':'.$pkg->{dst_port}.'<br/><br/>'.
        $pkg->{payload};
    $pkg->{payload} =~ s/\n([a-zA-Z0-9\-_]+\:)/\n<b>$1<\/b>/g;
    $pkg->{payload} =~ s/\n/<br\/>/g;

    $c->response->content_type('text/html');
    $c->response->body($pkg->{payload});

}


1;

# vim: set tabstop=4 expandtab:
