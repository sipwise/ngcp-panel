package NGCP::Panel::Controller::Root;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller' }

use NGCP::Panel::Widget;

#
# Sets the actions in this controller to be registered with no prefix
# so they function identically to actions created in MyApp.pm
#
__PACKAGE__->config(namespace => '');

=head1 NAME

NGCP::Panel::Controller::Root - Root Controller for NGCP::Panel

=head1 DESCRIPTION

[enter your description here]

=head1 METHODS

=head2 auto

Verify user is logged in.

=cut

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
        $c->response->redirect($c->uri_for('/login'));
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

    return 1;
}

=head2 index

The root page (/)

=cut

sub index :Path :Args(0) {
    my ( $self, $c ) = @_;

    $c->response->redirect($c->uri_for('/dashboard'));
}

=head2 default

Standard 404 error page

=cut

sub default :Path {
    my ( $self, $c ) = @_;
    $c->detach( '/error_page' );
}

=head2 end

Attempt to render a view, if needed.

=cut

sub end : ActionClass('RenderView') {}

sub ajax_process :Private {
    my ($self,$c,@arguments) = @_;
    
    my ($data,$columns,$searchable) = @arguments;
    
    #Process Arguments
    my $sEcho = $c->request->params->{sEcho} // "1"; #/
    my $sSearch = $c->request->params->{sSearch} // ""; #/
    my $iDisplayStart = $c->request->params->{iDisplayStart};
    my $iDisplayLength = $c->request->params->{iDisplayLength};
    my $iSortCol_0 = $c->request->params->{iSortCol_0};
    my $sSortDir_0 = $c->request->params->{sSortDir_0};
    my $iIdOnTop = $c->request->params->{iIdOnTop};
    
    #parse $data into $aaData
    my $aaData = [];
    
    for my $row (@$data) {
        my @aaRow = @$row{@$columns};
        #my %aaRow = %$row; #in case of using mData
        if (grep /$sSearch/, @aaRow[@$searchable]) {
            push @$aaData, \@aaRow;
        }
    }
    #Sorting
    if(defined($iSortCol_0) && defined($sSortDir_0)) {
        if($sSortDir_0 eq "asc") {
            @$aaData = sort {$a->[$iSortCol_0] cmp
                             $b->[$iSortCol_0]} @$aaData;
        } else {
            @$aaData = sort {$b->[$iSortCol_0] cmp
                             $a->[$iSortCol_0]} @$aaData;
        }
    }
    #potentially selected Id (search it (col 0) and move on top)
    if( defined($iIdOnTop) ) {
        my $elem;
        for (my $i=0; $i<@$aaData; $i++) {
            if(@$aaData[$i]->[0] == $iIdOnTop) {
                $elem = splice(@$aaData, $i, 1);
                unshift(@$aaData, $elem);
            }
        }
    }
    my $totalRecords = scalar(@$data);
    my $totalDisplayRecords = scalar(@$aaData);
    #Pagination
    if($iDisplayStart || $iDisplayLength ) {
        my $endIndex = $iDisplayLength+$iDisplayStart-1;
        $endIndex = $#$aaData if $endIndex > $#$aaData;
        @$aaData = @$aaData[$iDisplayStart .. $endIndex];
    }
    
    $c->stash(aaData => $aaData,
          iTotalRecords => $totalRecords,
          iTotalDisplayRecords => $totalDisplayRecords);
    
    
    $c->stash(sEcho => $sEcho);
}

sub error_page :Private {
    my ($self,$c) = @_;
    
    $c->stash(template => 'error_page.tt');
    #$c->response->body( 'Page not found' );
    $c->response->status(404);
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
