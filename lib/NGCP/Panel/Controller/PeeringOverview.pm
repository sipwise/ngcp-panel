package NGCP::Panel::Controller::PeeringOverview;
use NGCP::Panel::Utils::Generic qw(:all);
use Sipwise::Base;

use parent 'Catalyst::Controller';

use NGCP::Panel::Utils::Navigation;

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub list :Chained('/') :PathPart('peeringoverview') :CaptureArgs(0) {
    my ( $self, $c ) = @_;

    $c->stash->{po_rs} = $c->model('DB')->resultset('voip_peer_rules')->search({
        },{
            'join' => { 'group' => 'voip_peer_hosts' },
            '+select' => [ 'voip_peer_hosts.id' ],
            '+as' => [ 'peer_id' ],
        });

    $c->stash->{po_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => $c->loc("#") },
        { name => "callee_prefix", search => 1, title => $c->loc("Callee Prefix") },
        { name => "enabled", search => 1, title => $c->loc("State") },
        { name => "description", search => 1, title => $c->loc("Description") },
        { name => "group.name", search => 1, title => $c->loc("Peer Group") },
        { name => "group.voip_peer_hosts.name", search => 1, title => $c->loc("Peer Name") },
        { name => "group.voip_peer_hosts.host", search => 1, title => $c->loc("Peer Host") },
        { name => "group.voip_peer_hosts.ip", search => 1, title => $c->loc("Peer IP") },
        { name => "group.voip_peer_hosts.enabled", search => 1, title => $c->loc("Peer State") },
        { name => "group.priority", search => 1, title => $c->loc("Priority") },
        { name => "group.voip_peer_hosts.weight", search => 1, title => $c->loc("Weight") },
    ]);

    $c->stash->{template} = 'peeringoverview/list.tt';

    return;
}

sub root :Chained('list') :PathPart('') :Args(0) {
    my ( $self, $c ) = @_;
}

sub ajax :Chained('list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;

    $c->stash->{search_str} = $c->req->params->{sSearch};

    NGCP::Panel::Utils::Datatables::process($c, @{$c->stash}{qw(po_rs po_dt_columns)}, sub {
        my $item = shift;
        my %cols = $item->get_inflated_columns;
        return ( peer_group_id => $cols{group_id},
                 peer_host_id  => $cols{peer_id},
                 search_str    => $c->req->params->{sSearch} );
    },);

    $c->detach( $c->view("JSON") );
}

sub csv :Chained('list') :PathPart('csv') :Args(0) {
    my ($self, $c) = @_;

    my $csv = Text::CSV_XS->new({ allow_whitespace => 1, binary => 1, keep_meta_info => 1 });
    my @cols = qw(callee_prefix enabled description
                  group_name peer_name peer_host peer_ip
                  peer_enabled group_priority peer_weight);
    $csv->column_names(@cols);
    my $io = IO::String->new();

    my $res = $c->model('DB')->resultset('voip_peer_rules')->search({
        },{
            'join' => { 'group' => 'voip_peer_hosts' },
            '+select' => [
                            'group.name',
                            'voip_peer_hosts.name',
                            'voip_peer_hosts.host',
                            'voip_peer_hosts.ip',
                            'voip_peer_hosts.enabled',
                            'group.priority',
                            'voip_peer_hosts.weight',
                         ],
            '+as' => [
                            'group_name',
                            'peer_name',
                            'peer_host',
                            'peer_ip',
                            'peer_enabled',
                            'group_priority',
                            'peer_weight',
                     ],
        });

    foreach my $row ($res->all) {
        my %data = $row->get_inflated_columns;
        $csv->print($io, [ @data{@cols} ]);
        print $io "\n";
    }

    my $date_str = POSIX::strftime('%Y-%m-%d_%H_%M_%S', localtime(time));

    $c->response->header ('Content-Disposition' => 'attachment; filename="peering_overview_'. $date_str .'.csv"');
    $c->response->content_type('text/csv');
    $c->response->body(${$io->string_ref});
}


__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 AUTHOR

Kirill Solomko <ksolomko@sipwise.com>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
