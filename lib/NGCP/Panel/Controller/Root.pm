package NGCP::Panel::Controller::Root;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller' }

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
        
        $c->log->debug("*** Root::auto grant access to root and login controller");
        return 1;
    }

    unless($c->user_exists) {
        $c->log->debug("*** Root::auto user not authenticated");
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
    $c->response->body( 'Page not found' );
    $c->response->status(404);
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
    
    #parse $data into $aaData
    my $aaData = [];
    
    for my $row (@$data) {
        my @aaRow = @$row{@$columns};
        if (grep /$sSearch/, @aaRow[@$searchable]) {
            push @$aaData, \@aaRow;
        }
    }
    my $totalRecords = scalar(@$aaData);
    #Pagination
    if($iDisplayStart || $iDisplayLength ) {
        my $endIndex = $iDisplayLength+$iDisplayStart-1;
        $endIndex = $#$aaData if $endIndex > $#$aaData;
        @$aaData = @$aaData[$iDisplayStart .. $endIndex];
    }
    
    $c->stash(aaData => $aaData,
          iTotalRecords => $totalRecords,
          iTotalDisplayRecords => $totalRecords);
    
    
    $c->stash(sEcho => $sEcho);
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
