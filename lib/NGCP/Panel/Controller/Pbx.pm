package NGCP::Panel::Controller::Pbx;
use Sipwise::Base;
use namespace::sweep;
BEGIN { extends 'Catalyst::Controller'; }

use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Contract;
use NGCP::Panel::Utils::InvoiceTemplate;
use NGCP::Panel::Form::Invoice::Invoice;

sub auto :Private {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub spa_directory_getsearch :Chained('/') :PathPart('pbx/directory/spasearch') :Args(1) {
    my ($self, $c, $id) = @_;

    my $baseuri = 'http://' . $c->req->uri->host . ':' . ($c->config->{web}->{autoprov_plain_port} // '1444') . '/pbx/directory/spa/' . $id;
    my $data = '';

    $data = <<EOF;
    <CiscoIPPhoneInput>
        <Title>Search User</Title>
        <Prompt>Enter (part of) Name</Prompt>
        <URL>$baseuri</URL>
        <InputItem>
            <QueryStringParam>q</QueryStringParam>
            <InputFlags>A</InputFlags>
        </InputItem>
    </CiscoIPPhoneInput>
EOF

    $c->log->debug("providing config to $id");
    $c->log->debug($data);

    $c->response->content_type('text/xml');
    $c->response->body($data);
    return;
}

sub spa_directory_list :Chained('/') :PathPart('pbx/directory/spa') :Args(1) {
    my ($self, $c, $id) = @_;

    unless($id) {
        $c->response->content_type('text/plain');
        if($c->config->{features}->{debug}) {
            $c->response->body("404 - device id not given");
        } else {
            $c->response->body("404 - device not found");
        }
        $c->response->status(404);
        return;
    }

    $id =~ s/^([^\=]+)\=0$/$1/;
    $id = lc $id;

    my $dev = $c->model('DB')->resultset('autoprov_field_devices')->find({
        identifier => $id
    });
    unless($dev) {
        $c->response->content_type('text/plain');
        if($c->config->{features}->{debug}) {
            $c->response->body("404 - device id '" . $id . "' not found");
        } else {
            $c->response->body("404 - device not found");
        }
        $c->response->status(404);
        return;
    }

    my $baseuri = 'http://' . $c->req->uri->host . ':' . ($c->config->{web}->{autoprov_plain_port} // '1444') . '/device/autoprov/directory/spa/' . $id;
    my $data = '';

    my $delim = '?';
    my $q;
    if(exists $c->req->params->{q} && length($c->req->params->{q})) {
        $q = $c->req->params->{q};
        $baseuri .= "?q=$q";
        $delim = '&amp;';
    }


    my $customer = $dev->contract;

    my $page = $c->req->params->{page} // 1;
    my $rows = 1; # TODO: make it 30?

    # TODO: search for display name instead of username!
    my $rs = $customer->voip_subscribers->search({
        'status' => 'active',
        'provisioning_voip_subscriber.pbx_extension' => { '!=' => undef },
        defined $q ? ('me.username' => { like => "%$q%" }) : (),
    },{
        join => 'provisioning_voip_subscriber',
    });
    my $total = $rs->count;
    my ($nextpage, $prevpage);

    if(($total / $rows) > $page ) {
        $nextpage = $page + 1;
    }
    if($page > 1) {
        $prevpage = $page - 1;
    }

    my @entries = ();
    foreach my $sub($rs->search(undef,{page => $page, rows => $rows})->all) {
        my $prov_sub = $sub->provisioning_voip_subscriber;
        next unless($prov_sub && $prov_sub->pbx_extension);
        my $display_name = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
            c => $c,
            prov_subscriber => $sub,
            attribute => 'display_name',
        );
        if($display_name->first) {
            $display_name = $display_name->first->value;
        } else {
            $display_name = $sub->username;
        };

        push @entries, { name => $display_name, ext => $prov_sub->pbx_extension };
    }

    my $nexturi =  $baseuri . $delim . 'page='.($nextpage//0);
    my $prevuri = $baseuri . $delim . 'page='.($prevpage//0);
    my $searchuri = 'http://' . $c->req->uri->host . ':' . ($c->config->{web}->{autoprov_plain_port} // '1444') . '/pbx/directory/spasearch/' . $id;

    $data = '<CiscoIPPhoneDirectory><Title>PBX Address Book</Title><Prompt>Select the User</Prompt>';
    $data .= join '', map {"<DirectoryEntry><Name>$$_{name}</Name><Telephone>$$_{ext}</Telephone></DirectoryEntry>"} @entries; 
    $data .= "<SoftKeyItem><Name>Dial</Name><URL>SoftKey:Dial</URL><Position>1</Position></SoftKeyItem>";
    if($prevpage) {
        $data .= "<SoftKeyItem><Name>Prev</Name><URL>$prevuri</URL><Position>2</Position></SoftKeyItem>";
    } else {
        $data .= "<SoftKeyItem><Name>Search</Name><URL>$searchuri</URL><Position>2</Position></SoftKeyItem>";
    }
    $data .= "<SoftKeyItem><Name>Next</Name><URL>$nexturi</URL><Position>3</Position></SoftKeyItem>"
        if($nextpage);
    $data .= "<SoftKeyItem><Name>Cancel</Name><URL>SoftKey:Exit</URL><Position>4</Position></SoftKeyItem>";
    $data .= '</CiscoIPPhoneDirectory>';

    $c->log->debug("providing config to $id");
    $c->log->debug($data);

    # to make the exit button really exit the xml application
    $c->response->headers->header('Expires' => '-1');

    $c->response->content_type('text/xml');
    $c->response->body($data);
}

__PACKAGE__->meta->make_immutable;
1;
# vim: set tabstop=4 expandtab:
