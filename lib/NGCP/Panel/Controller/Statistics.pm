package NGCP::Panel::Controller::Statistics;
use Sipwise::Base;

BEGIN { use parent 'Catalyst::Controller'; }

use NGCP::Panel::Utils::Statistics;
use NGCP::Panel::Form::Statistics;
use NGCP::Panel::Utils::Navigation;

use Sys::Hostname;

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub root :PathPart('/') :CaptureArgs(0) {
    my ( $self, $c ) = @_;
}

sub index :Chained('/') :PathPart('statistics') :Args(0) {
    my ( $self, $c ) = @_;

    my $posted = ($c->req->method eq 'POST');
    my $selected_host;
    my $selected_folder;

    my $hosts = NGCP::Panel::Utils::Statistics::get_host_list();
    unless($posted) {
        my $ownhost = hostname;
        if(grep { $ownhost eq $_ } @$hosts) {
            $selected_host = $ownhost;
        } else {
            $selected_host = $hosts->[0];
        }
    } else {
        $selected_host = $c->request->params->{host};
    }
    $c->stash->{hosts} = $hosts;

    my $subdirs = NGCP::Panel::Utils::Statistics::get_host_subdirs($selected_host);
    unless($posted) {
        $selected_folder = $subdirs->[0];
        
    } else {
        $selected_folder = $c->request->params->{folder};
    }
    $c->stash->{folders} = $subdirs;

    my $form = NGCP::Panel::Form::Statistics->new(ctx => $c);
    $form->process(
        posted => ($c->req->method eq 'POST'),
        params => { host => $selected_host, folder => $selected_folder },
    );
    if($posted && !$form->validated) {
        $c->log->error("tried to select invalid host/folder pair");
        $c->response->redirect($c->uri_for_action('/statistics/index'));
        return;
    }
    delete $c->stash->{hosts};
    delete $c->stash->{folders};

    my $rrds = NGCP::Panel::Utils::Statistics::get_rrd_files(
        $selected_host, $selected_folder
    );
    my @plotdata = ();
    foreach my $rrd (@{ $rrds }) {
        my $name = $rrd;
        $name =~ s/[\.:]/-/g;
        my $title = $rrd;
        $title =~ s/\.rrd$//;

        push @plotdata, {
            name  => $name,
            title => $title,
            url   => $c->uri_for_action('/statistics/rrd', 
                        $selected_host, $selected_folder, $rrd),
            si    => 1,
        };
    }

    $c->stash(
        template => 'statistics/list.tt',
        form => $form,
        plotdata => \@plotdata,
        tz_offset => NGCP::Panel::Utils::Statistics::tz_offset(),
    );
}

sub subdirs : Chained('/') :PathPart('statistics/subdirs') :Args(1) {
    my ( $self, $c, $host) = @_;

    return unless(defined $host);
    my $subdirs = NGCP::Panel::Utils::Statistics::get_host_subdirs($host);

    my $options = "";
    foreach my $opt(@{ $subdirs }) {
        $options .= '<option value="' . $opt. '">' . $opt . "</option>\n";
    }
    $c->response->body($options);
    return;
}

sub rrd : Chained('/') :PathPart('statistics/rrd') :Args() {
    my ( $self, $c, $host, $folder, $file ) = @_;

    unless(defined $host && defined $folder && defined $file) {
        $c->log->error("tried to fetch rrd with incomplete path");
        $c->response->redirect($c->uri_for_action('/statistics/index'));
        return;
    }

    my $path = $host.'/'.$folder.'/'.$file;
    my $content = NGCP::Panel::Utils::Statistics::get_rrd($path);
    if($content) {
        $c->response->content_type('application/octet-stream');
        $c->response->body($content);
        return;
    }

    $c->response->redirect($c->uri_for_action('/statistics/index'));
    return;
}

=head1 AUTHOR

Andreas Granig,,,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;

# vim: set tabstop=4 expandtab:
