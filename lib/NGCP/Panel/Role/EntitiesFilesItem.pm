package NGCP::Panel::Role::EntitiesFilesItem;

use parent qw/NGCP::Panel::Role::EntitiesItem/;

use boolean qw(true);
use Safe::Isa qw($_isa);
use Path::Tiny qw(path);
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use Data::HAL qw();
use Data::HAL::Link qw();
use NGCP::Panel::Utils::Generic qw(:all);
use NGCP::Panel::Utils::ValidateJSON qw();

sub get {
    my ($self, $c, $id, %params) = @_;

    {

        #params based is a variant for call from custom GET. And so id can be passed too
        my ($filename, $content_type, $data_ref) = @params{qw/filename content_type data/};
        $id //= $params{id};
        if ($id){
            last unless $self->valid_id($c, $id);
        }else{
            return;
        }

        my $item = $self->item_by_id_valid($c, $id);
        last unless $item;

        if (!$data_ref) {
            ($filename, $content_type, $data_ref) = $self->get_item_file($c, $id, $item);
        }
        last unless $data_ref;
        
        $c->response->header ('Content-Disposition' => 'attachment; filename="' . $filename . '"');
        $c->response->content_type($content_type);
        $c->response->body($$data_ref);
        return;
    }
    return;
}
sub get_item_file{
    return;
}

sub put {
    my ($self, $c, $id) = @_;
    my($media_type) = @params{qw/media_type/};
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $preference = $self->require_preference($c);
        last unless $preference;

        my $item = $self->item_by_id_valid($c, $id);
        last unless $item;

        my $binary = $self->get_valid_raw_put_data(
            c => $c,
            id => $id,
            media_type => $self->config->{action}->{PUT}->{ContentType} // 'application/octet-stream',,
        );
        last unless $binary;
        my $resource = $c->req->query_params;
        last unless($resource);
        
        #todo: remove aftermigration. backward compatibility.
        my($form, $form_exceptions) = $self->get_form($c);
        my $old_resource = $self->resource_from_item($c, $item, $form);
        #/todo

        ($item,$form) = $self->update_item(
            $c, $item, $old_resource, $resource, $form,
            {
                process_extras => { binary_ref => \$binary },
                form => $form,
                form_exceptions => $form_exceptions,
            }
        );
        last unless $item;

        $guard->commit; 
        $self->return_representation($c, $item, $form, $preference);
    }
    return;
}

1;

# vim: set tabstop=4 expandtab:
