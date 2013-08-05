package NGCP::Panel::Controller::Root;
use Moose;


BEGIN { extends 'Catalyst::Controller' }

use NGCP::Panel::Widget;
use Scalar::Util qw(blessed);

#
# Sets the actions in this controller to be registered with no prefix
# so they function identically to actions created in MyApp.pm
#
__PACKAGE__->config(namespace => '');

sub auto :Private {
    my($self, $c) = @_;

    $c->log->debug("*** Root::auto called");

    if($c->controller =~ /::Root\b/
        or $c->controller =~ /::Login\b/) {
        
        $c->log->debug("*** Root::auto grant access to " . $c->request->path);
        return 1;
    }
    
    unless($c->user_exists) {
        $c->log->debug("*** Root::auto user not authenticated");
        
        # don't redirect to login page for ajax uris
        if($c->request->path =~ /\/ajax$/) {
            $c->response->body("403 - Permission denied");
            $c->response->status(403);
            return;
        }
        
        # store uri for redirect after login
        my $target = undef;
        if($c->request->method eq 'GET') {
            if($c->request->uri !~ /\/logout$/) {
                $target = $c->request->uri;
            }
        } else {
            $target = $c->request->headers->referer;
        }
        $c->log->debug("*** Root::auto do login, target='$target'");
        $c->session(target => $target);
        $c->response->redirect($c->uri_for('/login/admin'));
        return;
    }

    $c->log->debug("*** Root::auto grant access for authenticated user");

    # load top menu widgets
    my $plugin_finder = NGCP::Panel::Widget->new;
    my $topmenu_templates = [];
    foreach($plugin_finder->instantiate_plugins($c, 'topmenu_widgets')) {
        $_->handle($c);
        push @{ $topmenu_templates }, $_->template; 
    }
    $c->stash(topmenu => $topmenu_templates);


    $c->session->{created_objects} = {} unless(defined $c->session->{created_objects});

    return 1;
}

sub index :Path :Args(0) {
    my ( $self, $c ) = @_;

    $c->response->redirect($c->uri_for('/dashboard'));
}

sub back :Path('/back') :Args(0) {
    my ( $self, $c ) = @_;
    my $target;
    my $ref_uri = URI->new($c->req->referer) || $c->uri_for('/dashboard');
    if($c->session->{redirect_targets}) {
        while(@{ $c->session->{redirect_targets} }) {
            $target = shift @{ $c->session->{redirect_targets} };
            last unless($ref_uri->path eq $target->path);
        }
        if(!defined $target || $ref_uri->path eq $target->path) {
            $target = $c->uri_for('/dashboard');
        }
    } else {
        $target = $c->uri_for('/dashboard');
    }
    $c->response->redirect($target);
    $c->detach;
}

sub default :Path {
    my ( $self, $c ) = @_;
    $c->detach( '/error_page' );
}

sub end : ActionClass('RenderView') {}

sub ajax_process_resultset :Private {
    my ($self, $c, $rs, $columns, $searchable) = @_;

    #Process Arguments
    my $sEcho = int($c->request->params->{sEcho} // 1); #/
    # http://datatables.net/usage/server-side#sEcho
    my $sSearch        = $c->request->params->{sSearch} // "";     #/
    my $iDisplayStart  = $c->request->params->{iDisplayStart};
    my $iDisplayLength = $c->request->params->{iDisplayLength};
    my $iSortCol_0     = $c->request->params->{iSortCol_0};
    my $sSortDir_0     = $c->request->params->{sSortDir_0};

    if (defined $sSortDir_0) {
        if ('desc' eq lc $sSortDir_0) {
            $sSortDir_0 = 'desc';
        } else {
            $sSortDir_0 = 'asc';
        }
    }

    my $iIdOnTop       = $c->request->params->{iIdOnTop};

    #will contain final data to be sent
    my $aaData = [];

    my $totalRecords = $rs->count;

    if ($sSearch) {
        $rs = $rs->search([ map{ +{ $_ => { like => '%'.$sSearch.'%' } } } @$searchable ]);
    }

    my $totalDisplayRecords = $rs->count;

    #potentially selected Id as first element
    if (defined $iIdOnTop) {
        if (defined(my $row = $rs->find($iIdOnTop))) {
            push @{ $aaData }, _prune_row($columns, $row->get_inflated_columns);
            $rs = $rs->search({ 'me.id' => { '!=', $iIdOnTop} });
        } else {
            $c->log->error("iIdOnTop $iIdOnTop not found in resultset " . ref $rs);
        };
    }

    #Sorting
    if (defined $iSortCol_0 && defined $sSortDir_0) {
        $rs = $rs->search(undef, {
            order_by => {
                "-$sSortDir_0" => $columns->[$iSortCol_0],
            }
        });
    }

    #Pagination
    # $iDisplayLength will be -1 if bPaginate is false
    if (defined $iDisplayStart && $iDisplayLength && $iDisplayLength > 0) {
        $rs = $rs->search(undef, {
            offset => $iDisplayStart,
            rows   => $iDisplayLength,
        });
    }

    for my $row ($rs->all) {
        push @{ $aaData }, _prune_row($columns, $row->get_inflated_columns);
    }

    $c->stash(
        aaData               => $aaData,
        iTotalRecords        => $totalRecords,
        iTotalDisplayRecords => $totalDisplayRecords,
        sEcho                => $sEcho,
    );
}

sub _prune_row {
    my ($columns, %row) = @_;
    while (my ($k,$v) = each %row) {
        unless ($k ~~ $columns) {
            delete $row{$k};
            next;
        }
        $row{$k} = $v->datetime if blessed($v) && $v->isa('DateTime');
    }
    return { %row };
}

sub error_page :Private {
    my ($self,$c) = @_;
    
    $c->log->info( 'Failed to find: ' . $c->request->path );
    $c->stash(template => 'error_page.tt');
    #$c->response->body( 'Page not found' );
    $c->response->status(404);
}

sub denied_page :Private {
    my ($self,$c) = @_;
    
    $c->log->info('Access to path denied: ' . $c->request->path );
    $c->stash(template => 'denied_page.tt');
    $c->response->status(403);
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

NGCP::Panel::Controller::Root - Root Controller for NGCP::Panel

=head1 DESCRIPTION

[enter your description here]

=head1 METHODS

=head2 auto

Verify user is logged in.
Check user roles.
Load top menu widgets.

=head2 index

The root page (/)

=head2 default

Standard 404 error page

=head2 end

Attempt to render a view, if needed.

=head2 ajax_process_resultset

Processes a L<ResultSet|DBIx::Class::ResultSet> and prepares data from other controllers to be used
with the JSON view. The items exposed to stash are namely:

* sEcho
* aaData
* iTotalRecords
* iTotalDisplayRecords

They are intended for use with datatables.

Arguments: $resultset, \@columns, \@searchable

=head2 error_page

should be called if the intended page could not be found (404).

=head1 AUTHOR

Andreas Granig,,,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
