package NGCP::Panel::Role::API::Admins;
use NGCP::Panel::Utils::Generic qw(:all);
use NGCP::Panel::Utils::API;

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';

use Data::HAL::Link qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Admin;

sub item_name{
    return 'admin';
}

sub resource_name{
    return 'admins';
}

sub dispatch_path{
    return '/api/admins/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-admins';
}

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('admins');
    if($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({
            reseller_id => $c->user->reseller_id
        });
    }

    if($c->user->is_master || $c->user->is_superuser) {
        # return all (or all of reseller) admins
    } else {
        # otherwise, only return the own admin if master is not set
        $item_rs = $item_rs->search({
            id => $c->user->id,
        });
    }
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    my $form;
    if($c->user->roles eq "admin") {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Administrator::Admin", $c);
    } else {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Administrator::Reseller", $c);
    }
    return $form;
}

sub hal_links {
    my($self, $c, $item, $resource, $form) = @_;
    my $adm = $c->user->roles eq "admin";
    return [
        $adm ? Data::HAL::Link->new(relation => 'ngcp:resellers', href => sprintf("/api/resellers/%d", $item->reseller_id)) : (),
    ];
}

sub process_form_resource{
    my($self,$c, $item, $old_resource, $resource, $form, $process_extras) = @_;

    NGCP::Panel::Utils::API::apply_resource_reseller_id($c, $resource);

    my $pass = $resource->{password};
    delete $resource->{password};
    if(defined $pass) {
        $resource->{md5pass} = undef;
        $resource->{saltedpass} = NGCP::Panel::Utils::Admin::generate_salted_hash($pass);
    }
    foreach my $f(qw/billing_data call_data is_active is_master is_superuser is_ccare lawful_intercept read_only show_passwords/) {
        $resource->{$f} = (ref $resource->{$f} eq 'JSON::true' || ( defined $resource->{$f} && ( $resource->{$f} eq 'true' || $resource->{$f} eq '1' ) ) ) ? 1 : 0;
    }
    return $resource;
}

sub check_resource{
    my($self, $c, $item, $old_resource, $resource, $form, $process_extras) = @_;
    #TODO: move to config
    return unless NGCP::Panel::Utils::API::check_resource_reseller_id($self, $c, $resource, $old_resource);
    return 1;
}

sub check_duplicate{
    my($self, $c, $item, $old_resource, $resource, $form, $process_extras) = @_;
    my $schema = $c->model('DB');
    my $existing_item = $schema->resultset('admins')->find({
        login => $resource->{login},
    });
    if ($existing_item && (!$item || $item->id != $existing_item->id)) {
        $c->log->error("admin with login '$$resource{login}' already exists");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Admin with this login already exists");
        return;
    }
    return 1;
}

1;
# vim: set tabstop=4 expandtab:
