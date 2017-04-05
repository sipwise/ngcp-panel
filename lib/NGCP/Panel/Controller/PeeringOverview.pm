package NGCP::Panel::Controller::PeeringOverview;
use NGCP::Panel::Utils::Generic qw(:all);
use Sipwise::Base;

use parent 'Catalyst::Controller';

use NGCP::Panel::Form::PeeringOverview::Columns;
use NGCP::Panel::Utils::Navigation;

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub list :Chained('/') :PathPart('peeringoverview') :CaptureArgs(0) {
    my ( $self, $c ) = @_;

    my $stored = $c->session->{created_objects}{peeringoverview} //= {};
    $stored->{rule_direction} //= "outbound";

    my @default = (
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
    );

    if (defined $stored->{cols}) {
        foreach my $col (@{$stored->{cols}}) {
            unless ($col->{name} || $col->{title}) {
                delete $stored->{$col};
            }
        }
    } else {
        @{$stored->{cols}} = @default;
    }

    $c->stash->{po_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => $c->loc("#") },
        @{$stored->{cols}}
    ]);

    $c->stash->{template} = 'peeringoverview/list.tt';

    return;
}

sub root :Chained('list') :PathPart('') :Args(0) {
    my ( $self, $c ) = @_;
}

sub ajax :Chained('list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;

    my $stored = $c->session->{created_objects}{peeringoverview} //= {};
    $stored->{search} = $c->req->params->{sSearch} // '';

    my $rules_table = "voip_peer_rules";
    if ($stored->{rule_direction} eq "inbound") {
        $rules_table = "voip_peer_inbound_rules";
    }

    my $join = { 'join' => 'group' };
    if (grep { /voip_peer_hosts/ } map { $_->{name} } @{$stored->{cols}}) {
        $join = {
            'join' => { 'group' => 'voip_peer_hosts' },
            '+select' => [ 'voip_peer_hosts.id' ],
            '+as' => [ 'peer_id' ],
        };
    }

    $c->stash->{po_rs} = $c->model('DB')->resultset($rules_table)->search(
        {}, $join
    );

    NGCP::Panel::Utils::Datatables::process($c, @{$c->stash}{qw(po_rs po_dt_columns)}, sub {
        my $item = shift;
        my %cols = $item->get_inflated_columns;
        return ( peer_group_id => $cols{group_id},
                 peer_host_id  => $cols{peer_id} );
    },);

    $c->detach( $c->view("JSON") );
}


sub edit :Chained('list') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;

    my $form = NGCP::Panel::Form::PeeringOverview::Columns->new(ctx => $c);
    my $params = $c->session->{created_objects}{peeringoverview}{states} // {};
    my $posted = ($c->req->method eq 'POST');
    my $data = $c->req->params;

    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params,
    );

    unless ($posted && $form->validated) {
        $c->stash(
            template => 'peeringoverview/edit.tt',
            form => $form,
        );
        return;
    }

    my $stored = { rule_direction => $data->{rule_direction} // "undef", cols => [] };
    foreach my $field ($form->fields) {
        my $prefix = ($stored->{rule_direction} eq "outbound" ? "out" : "in");
        if ($field->name =~ /^${prefix}_(.+)$/ && $data->{$field->name}) {
            push @{$stored->{cols}}, {
                name  => $field->{element_attr}->{field},
                title => $c->loc($field->label),
                search => 1,
            };
        }
        $stored->{states}{$field->name} = $data->{$field->name} // 0;
    }
    $c->session->{created_objects}{peeringoverview} = $stored;
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for);
}

sub csv :Chained('list') :PathPart('csv') :Args(0) {
    my ($self, $c) = @_;

    my $stored = $c->session->{created_objects}{peeringoverview} //= {};

    my $csv = Text::CSV_XS->new({ allow_whitespace => 1, binary => 1, keep_meta_info => 1 });
    my @hdr_cols = map { $_->{title} } @{$stored->{cols}};
    $csv->column_names(@hdr_cols);
    my $io = IO::String->new();

    my $rules_table = "voip_peer_rules";
    if ($stored->{rule_direction} eq "inbound") {
        $rules_table = "voip_peer_inbound_rules";
    }

    my @sel_cols = map { scalar split(/\./, $_->{name}) == 3
                            ? join('.', (split(/\./, $_->{name}))[1,2])
                            : $_->{name}
                       } @{$stored->{cols}};
    my @as_cols = map { (my $t = $_) =~ s/\./_/g; $t } @sel_cols;

    my $filter = {};
    if ($stored->{search}) {
        foreach my $col (@sel_cols) {
            my $rel_col = ($col =~ /\./ ? $col : 'me.'.$col);
            push @{$filter->{'-or'}},
                { $rel_col => { like => '%'.$stored->{search}.'%' } }
        }
    }

    my $join = {
                    'join' => 'group',
                    'select' => [ @sel_cols ],
                    'as' => [ @as_cols ],
    };
    if (grep { /voip_peer_hosts/ } map { $_->{name} } @{$stored->{cols}}) {
        $join = {
            'join' => { 'group' => 'voip_peer_hosts' },
            'select' => [ @sel_cols ],
            'as' => [ @as_cols ],
        };
    }

    my $res = $c->model('DB')->resultset($rules_table)->search(
        $filter, $join
    );

    $csv->print($io, [ @hdr_cols ]);
    print $io "\n";
    foreach my $row ($res->all) {
        my %data = $row->get_inflated_columns;
        $csv->print($io, [ @data{@as_cols} ]);
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
