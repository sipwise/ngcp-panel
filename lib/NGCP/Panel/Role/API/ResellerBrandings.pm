package NGCP::Panel::Role::API::ResellerBrandings;

use parent qw/NGCP::Panel::Role::API/;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);
use HTTP::Status qw(:constants);

use NGCP::Panel::Form;

use boolean qw(true);
use JSON qw();
use File::Type;

sub item_name{
    return 'resellerbrandings';
}

sub resource_name{
    return 'resellerbrandings';
}

sub dispatch_path{
    return '/api/resellerbrandings/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-resellerbrandings';
}

sub config_allowed_roles {
    return {
        'Default' => [qw/admin reseller subscriberadmin subscriber/],
        #GET will use default
        'POST'    => [qw/admin reseller/],
        'PUT'     => [qw/admin reseller/],
        'PATCH'   => [qw/admin reseller/],
    };
}

sub get_form {
    my ($self, $c) = @_;
    #use_fields_for_input_without_param
    return NGCP::Panel::Form::get(
        $c->user->roles eq "admin"
            ? "NGCP::Panel::Form::Reseller::BrandingAPIAdmin"
            : "NGCP::Panel::Form::Reseller::BrandingAPI",
        $c
    );
}

sub _item_rs {
    my ($self, $c) = @_;
    my $item_rs = $c->model('DB')->resultset('reseller_brandings')->search(
        {
            'reseller.status' => { '!=' => 'terminated' }
        },
        {
            join => 'reseller'
        }
    );
    if ($c->user->roles eq "admin") {
    } elsif ($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({ reseller_id => $c->user->reseller_id });
    } elsif ($c->user->roles eq "subscriberadmin" || $c->user->roles eq "subscriber") {
        my $reseller_id = $c->user->contract->contact->reseller_id;
        return unless $reseller_id;
        $item_rs = $item_rs->search({
            reseller_id => $reseller_id,
        });
    }
    return $item_rs;
}

sub item_by_id {
    my ($self, $c, $id) = @_;
    my $item_rs = $self->item_rs($c);
    return $item_rs->find($id);
}

sub resource_from_item {
    my ($self, $c, $item) = @_;

    my %resource = $item->get_inflated_columns;
    delete $resource{logo};

    my ($form) = $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => \%resource,
        run => 0,
    );

    foreach my $field (qw/reseller_id id/){
        $resource{$field} = int($item->$field // 0);
    }

    return \%resource;
}


sub process_form_resource{
    my($self,$c, $item, $old_resource, $resource, $form, $process_extras) = @_;

    my $reseller_id = delete $resource->{reseller_id};
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $reseller_id = $c->user->reseller_id;
    }
    $resource->{reseller_id} = $reseller_id;

    my $ft = File::Type->new();
    if($resource->{logo}) {
        my $image = delete $resource->{logo};
        $resource->{logo} = $image->slurp;
        $resource->{logo_image_type} = $ft->mime_type($resource->{logo});
    }

    return $resource;
}

sub check_resource{
    my($self, $c, $item, $old_resource, $resource, $form, $process_extras) = @_;
    my $schema = $c->model('DB');

    my $reseller = $c->model('DB')->resultset('resellers')->find($resource->{reseller_id});
    unless($reseller) {
        $c->log->error("invalid reseller_id '".((defined $resource->{reseller_id})?$resource->{reseller_id} : "undefined")."', does not exist");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid reseller_id, does not exist");
        return;
    }

    return 1;
}

sub check_duplicate{
    my($self, $c, $item, $old_resource, $resource, $form, $process_extras) = @_;

    my $schema = $c->model('DB');
    my $existing_item = $c->model('DB')->resultset('reseller_brandings')->find({
        reseller_id => $resource->{reseller_id},
    });
    if($existing_item && (!$item || $item->id != $existing_item->id)) {
        $c->log->error("Branding already exists for reseller_id '$$resource{reseller_id}'");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Branding already exists for this reseller");
        return;
    }
    return 1;
}

sub update_item_model {
    my ($self, $c, $item, $old_resource, $resource, $form, $process_extras) = @_;

    $item->update($resource);

    return $item;
}

1;
# vim: set tabstop=4 expandtab:
