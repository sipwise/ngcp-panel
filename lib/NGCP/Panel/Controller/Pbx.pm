package NGCP::Panel::Controller::Pbx;
use NGCP::Panel::Utils::Generic qw(:all);
use Sipwise::Base;
use parent 'Catalyst::Controller';

use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Contract;
use NGCP::Panel::Utils::Phonebook;

sub auto :Private {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub base :Chained('/') :PathPart('') :CaptureArgs(0) :Does(License) :RequiresLicense('device_provisioning') :RequiresLicense('pbx') :RequiresLicense('phonebook') :LicenseDetachTo('/denied_page') {
    my ($self, $c) = @_;

    $c->stash->{schema} = $c->config->{deviceprovisioning}->{secure} ? 'https' : 'http';
    $c->stash->{host} = $c->config->{deviceprovisioning}->{host} // $c->req->uri->host;
    $c->stash->{port} = $c->config->{deviceprovisioning}->{port} // 1444;
    $c->stash->{cisco_port} = $c->config->{deviceprovisioning}->{cisco_port} // 1447;

    $c->log->debug("SSL_CLIENT_M_DN: " . ($c->request->env->{SSL_CLIENT_M_DN} // ""));
    unless(
        ($c->user_exists && ($c->user->roles eq "admin" || $c->user->roles eq "reseller")) ||
        defined $c->request->env->{SSL_CLIENT_M_DN}
    ) {
        $c->response->content_type('text/plain');
        if($c->config->{features}->{debug}) {
            $c->response->body("403 - unauthenticated pbx access");
        } else {
            $c->response->body("403 - forbidden");
        }
        $c->response->status(403);
        return;
    }
}

sub spa_directory_getsearch :Chained('base') :PathPart('pbx/directory/spasearch') :Args(1) {
    my ($self, $c, $id) = @_;

    my $schema = $c->stash->{schema};
    my $host = $c->stash->{host};
    my $port = $c->stash->{cisco_port};

    my $baseuri = "$schema://$host:$port/pbx/directory/spa/$id";
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

sub spa_directory_list :Chained('base') :PathPart('pbx/directory/spa') :Args(1) {
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

    my $schema = $c->stash->{schema};
    my $host = $c->stash->{host};
    my $port = $c->stash->{cisco_port};

    my $baseuri = "$schema://$host:$port/pbx/directory/spa/$id";
    my $data = '';

    my $delim = '?';
    my $q;
    my $dirsuffix = '';
    if(exists $c->req->params->{q} && length($c->req->params->{q})) {
        $q = $c->req->params->{q};
        $baseuri .= "?q=$q";
        $delim = '&amp;';
        $dirsuffix = ' (Search Results)';
    }


    my $customer = $dev->contract;

    my $page = $c->req->params->{page} // 1;
    my $rows = 10;

    my $rs = $self->_get_dirsearch_rs($customer, $q);
    my $total = $rs->count;
    my ($nextpage, $prevpage);

    if(($total / $rows) > $page ) {
        $nextpage = $page + 1;
    }
    if($page > 1) {
        $prevpage = $page - 1;
    }

    my @entries = ();
    my %entries = ();
    foreach my $sub($rs->search(undef,{page => $page, rows => $rows})->all) {
        my $prov_sub = $sub->provisioning_voip_subscriber;
        next unless($prov_sub && $prov_sub->pbx_extension);
        my $display_name = $sub->get_column('display_name');
        push @entries, { name => $display_name, ext => $prov_sub->pbx_extension };
        $entries{$prov_sub->pbx_extension} = 1;
    }

    $self->add_phonebook_entries($c, $dev, \@entries, \%entries);

    my $nexturi =  $baseuri . $delim . 'page='.($nextpage//0);
    my $prevuri = $baseuri . $delim . 'page='.($prevpage//0);

    my $searchuri = "$schema://$host:$port/pbx/directory/spasearch/$id";

    $data = "<CiscoIPPhoneDirectory><Title>PBX Address Book$dirsuffix</Title><Prompt>Select the User</Prompt>";
    $data .= join '', map {"<DirectoryEntry><Name>$$_{name}</Name><Telephone>$$_{ext}</Telephone></DirectoryEntry>"} @entries;
    $data .= "<SoftKeyItem><Name>Dial</Name><URL>SoftKey:Dial</URL><Position>1</Position></SoftKeyItem>";
    if($prevpage) {
        $data .= "<SoftKeyItem><Name>Prev</Name><URL>$prevuri</URL><Position>2</Position></SoftKeyItem>";
    } else {
        $data .= "<SoftKeyItem><Name>Search</Name><URL>$searchuri</URL><Position>2</Position></SoftKeyItem>";
    }
    $data .= "<SoftKeyItem><Name>Next</Name><URL>$nexturi</URL><Position>3</Position></SoftKeyItem>"
        if($nextpage);
    $data .= "<SoftKeyItem><Name>Cancel</Name><URL>Init:Services</URL><Position>4</Position></SoftKeyItem>";
    $data .= '</CiscoIPPhoneDirectory>';

    $c->log->debug("providing config to $id");
    $c->log->debug($data);

    $c->response->content_type('text/xml');
    $c->response->body($data);
}

sub panasonic_directory_list :Chained('base') :PathPart('pbx/directory/panasonic') :Args() {
    my ($self, $c) = @_;

    my $id = $c->req->params->{userid};
    my $q = $c->req->params->{name};

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

    my $schema = $c->stash->{schema};
    my $host = $c->stash->{host};
    my $port = $c->stash->{port};

    my $customer = $dev->contract;
	my $rs = $self->_get_dirsearch_rs($customer, $q);

    my @entries = ();
    my %entries = ();
    foreach my $sub($rs->all) {
        my $prov_sub = $sub->provisioning_voip_subscriber;
        next unless($prov_sub && $prov_sub->pbx_extension);
        my $display_name = $sub->get_column('display_name');
        push @entries, { name => $display_name, ext => $prov_sub->pbx_extension };
        $entries{$prov_sub->pbx_extension} = 1;
    }

    $self->add_phonebook_entries($c, $dev, \@entries, \%entries);

    my $data = <<'EOS_XML';
<?xml version="1.0" encoding="utf-8"?>
<ppxml xmlns="http://panasonic/sip_phone"
       xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
       xsi:schemaLocation="http://panasonic/sip_phone sip_phone.xsd">
    <Screen version="2.0">
        <PhoneBook version="2.0">
EOS_XML
        my $person_id = 0;
        $data .= join '', map {
            $person_id++;
            <<EOS_XMLLOOP;
            <Personnel id="$person_id">
                 <Name>$$_{name}</Name>
                 <PhoneNums>
                    <PhoneNum type="ext">$$_{ext}</PhoneNum>
                 </PhoneNums>
             </Personnel>
EOS_XMLLOOP
        } @entries;

    $data .= <<EOS_XML;
        </PhoneBook>
    </Screen>
</ppxml>
EOS_XML


    $c->log->debug("providing config to $id");
    $c->log->debug($data);

    $c->response->content_type('text/xml');
    $c->response->body($data);
}

sub yealink_directory_list :Chained('base') :PathPart('pbx/directory/yealink') :Args() {
    my ($self, $c) = @_;

    my $id = $c->req->params->{userid};
    my $q = $c->req->params->{name};

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

    my $schema = $c->stash->{schema};
    my $host = $c->stash->{host};
    my $port = $c->stash->{port};

    my $customer = $dev->contract;
    my $rs = $self->_get_dirsearch_rs($customer, $q);

    my @entries = ();
    my %entries = ();
    foreach my $sub($rs->all) {
        my $prov_sub = $sub->provisioning_voip_subscriber;
        next unless($prov_sub && $prov_sub->pbx_extension);
        my $display_name = $sub->get_column('display_name');
        push @entries, { name => $display_name, ext => $prov_sub->pbx_extension };
        $entries{$prov_sub->pbx_extension} = 1;
    }

    $self->add_phonebook_entries($c, $dev, \@entries, \%entries);

    my $req_uri = $c->req->uri;
    my $data = <<EOS_XML;
<?xml version="1.0" encoding="utf-8"?>
<SipwiseIPPhoneDirectory>
  <SoftKeyItem>
    <Name>0</Name>
    <URL>$req_uri</URL>
  </SoftKeyItem>
EOS_XML
    $data .= join '', map { <<EOS_XMLLOOP;
        <DirectoryEntry>
             <Name>$$_{name}</Name>
             <Telephone>$$_{ext}</Telephone>
         </DirectoryEntry>
EOS_XMLLOOP
    } @entries;
    $data .= '</SipwiseIPPhoneDirectory>';


    $c->log->debug("providing config to $id");
    $c->log->debug($data);

    $c->response->content_type('text/xml');
    $c->response->body($data);
}

sub polycom_directory_list :Chained('base') :PathPart('pbx/directory/polycom') :Args(1) {
    my ($self, $c, $id) = @_;

    $id =~ s/\-directory\.xml$//;
    my $q;

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

    my $schema = $c->stash->{schema};
    my $host = $c->stash->{host};
    my $port = $c->stash->{port};

    my $customer = $dev->contract;
    my $rs = $self->_get_dirsearch_rs($customer, $q);

    my @entries = ();
    my %entries = ();
    foreach my $sub($rs->all) {
        my $prov_sub = $sub->provisioning_voip_subscriber;
        next unless($prov_sub && $prov_sub->pbx_extension);
        my $display_name = $sub->get_column('display_name');
        push @entries, { name => $display_name, ext => $prov_sub->pbx_extension };
        $entries{$prov_sub->pbx_extension} = 1;
    }

    $self->add_phonebook_entries($c, $dev, \@entries, \%entries);

    foreach my $entry (@entries) {
        my ($fname, @rest) = split / +/, $entry->{name};
        my $lname = join ' ', @rest;
        $entry->{fname} = $fname;
        $entry->{lname} = $lname;
    }

    my $data = <<EOS_XML;
<?xml version="1.0" encoding="utf-8"?>
<directory>
  <item_list>
EOS_XML

# ln  last name
# fn  first name
# ct  contact
# sd  speed-dial index
# rt  ring type
# dc  divert contact for auto divert
# ad  auto divert
# ar  auto reject
# bw  buddy watching
# bb  buddy block

    $data .= join '', map { <<EOS_XMLLOOP;
        <item>
             <ln>$$_{lname}</ln>
             <fn>$$_{fname}</fn>
             <ct>$$_{ext}</ct>
             <sd/>
             <rt/>
             <dc/>
             <ad>0</ad>
             <ar>0</ar>
             <bw>0</bw>
             <bb>0</bb>
         </item>
EOS_XMLLOOP
    } @entries;
    $data .= '</item_list></directory>';

    $c->log->debug("providing config to $id");
    $c->log->debug($data);

    $c->response->content_type('text/xml');
    $c->response->body($data);
}

sub _get_dirsearch_rs :Private {
    my ($self, $customer, $q) = @_;

    my $rs = $customer->voip_subscribers->search({
        'status' => 'active',
        'provisioning_voip_subscriber.pbx_extension' => { '!=' => undef },
        'voip_usr_preferences.value' => { '!=' => undef },
        'attribute.attribute' => 'display_name',
        defined $q ? (
          -or => [
            'voip_usr_preferences.value' => { like => "%$q%" },
            'provisioning_voip_subscriber.pbx_extension' => { like => "$q%" }
          ]
        ) : (),
    },{
        join => { provisioning_voip_subscriber => { voip_usr_preferences => 'attribute'  } },
        '+select' => [qw/voip_usr_preferences.value/],
        '+as' => [qw/display_name/],
        order_by => { '-asc' => 'voip_usr_preferences.value' },
    });

    return $rs;
}

sub add_phonebook_entries {
    my ($self, $c, $dev, $entries, $entries_existent) = @_;
    my %phonebook = ();
    foreach my $private_line ($dev->autoprov_field_device_lines->search_rs({ line_type => 'private' })->all) {
        my $private_line_subscriber_id = $private_line->provisioning_voip_subscriber->voip_subscriber->id;
        $phonebook{$private_line_subscriber_id} //= NGCP::Panel::Utils::Phonebook::get_subscriber_phonebook($c, $private_line_subscriber_id);
        foreach my $entry (@{$phonebook{$private_line_subscriber_id}}) {
            push @$entries, { name => $entry->{name}, ext => $entry->{number} }
                unless $entries_existent->{$entry->{number}};
            $entries_existent->{$entry->{number}} = 1;
        }
    }
}

1;

__END__

=head1 NAME

NGCP::Panel::Controller::Pbx

=head1 DESCRIPTION

A controller to manipulate the PBX data

=head1 AUTHOR

Sipwise Development Team

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
