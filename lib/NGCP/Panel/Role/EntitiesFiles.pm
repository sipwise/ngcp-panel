package NGCP::Panel::Role::EntitiesFiles;

use parent qw/NGCP::Panel::Role::Entities/;

sub post {
    my ($self, $c) = @_;
    
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $binary = $self->get_valid_raw_post_data(
            c => $c, 
            media_type => $self->config->{action}->{OPTIONS}->{POST}->{ContentType} // 'application/octet-stream',
        );
        last unless $binary;

        my $resource = $c->req->query_params;
        last unless($resource);
        
        my ($form, $exceptions) = $self->get_form($c);
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
            $exceptions ? (exceptions => $exceptions) : (),
        );
        my $process_extras = {binary_ref => \$binary};
        
        last unless $self->process_form_resource($c, undef, undef, $resource, $form, $process_extras);
        last unless $resource;
        last unless $self->check_duplicate($c, undef, undef, $resource, $form, $process_extras);
        last unless $self->check_resource($c, undef, undef, $resource, $form, $process_extras);

        my $item = $self->create_item($c, $resource, $form, $process_extras);
        
        $guard->commit;

        $self->return_representation_post($c, $item, $form);
    }
    return;
}

#disable logging of the binary data
sub auto :Private {
    my ($self, $c) = @_;

    $self->set_body($c);
    $self->log_request($c);
}

sub end :Private {
    my ($self, $c) = @_;

    $self->log_response($c);
}

1;

# vim: set tabstop=4 expandtab:
