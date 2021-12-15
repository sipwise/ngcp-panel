package NGCP::Panel::Role::API::Admins;
use NGCP::Panel::Utils::Generic qw(:all);
use NGCP::Panel::Utils::API;

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';

use Data::HAL::Link qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Auth;
use NGCP::Panel::Utils::UserRole;

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

    my $where;
    my $item_rs = $c->model('DB')->resultset('admins');

    if ( ! $c->user->is_master) {
        $where->{id} = $c->user->id;
        return $item_rs->search($where);
    }

    if ($c->user->is_system) {
        return $item_rs;
    }

    if ($c->user->is_superuser) {
        $where = {
            is_system => 0,
            lawful_intercept => 0
        };
    } elsif ($c->user->roles eq 'reseller') {
        $where = {
            reseller_id => $c->user->reseller_id,
            is_system => 0,
            is_superuser => 0,
            lawful_intercept => 0
        };
    } else {
        $where->{id} = $c->user->id;
    }

    return $item_rs->search($where);
}

sub get_form {
    my ($self, $c) = @_;
    my $form;
    if ($c->user->is_system) {
       $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Administrator::SystemAPI", $c);
    } elsif ($c->user->roles eq "lintercept") {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Administrator::LInterceptAPI", $c);
    } elsif ($c->user->roles eq "admin") {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Administrator::AdminAPI", $c);
    } else {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Administrator::ResellerAPI", $c);
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

sub process_form_resource {
    my($self,$c, $item, $old_resource, $resource, $form, $process_extras) = @_;

    NGCP::Panel::Utils::API::apply_resource_reseller_id($c, $resource);

    my $pass = $resource->{password};
    delete $resource->{password};
    if (defined $pass) {
        $resource->{md5pass} = undef;
        $resource->{saltedpass} = NGCP::Panel::Utils::Auth::generate_salted_hash($pass);
    }

    foreach my $f (qw/billing_data call_data is_active is_master
                      is_superuser is_ccare lawful_intercept
                      read_only show_passwords can_reset_password/) {
        $resource->{$f} = (ref $resource->{$f} eq 'JSON::true' ||
                           ( defined $resource->{$f} &&
                            ( $resource->{$f} eq 'true' || $resource->{$f} eq '1' )
                           )
                          ) ? 1 : 0;
    }

    return $resource;
}

sub check_resource {
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
    my $existing_email;
    if ($resource->{email}) {
        $existing_email = $schema->resultset('admins')->find({
            email => $resource->{email},
        });
    }
    if ($existing_item && (!$item || $item->id != $existing_item->id)) {
        $c->log->error("admin with login '$$resource{login}' already exists");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Admin with this login already exists");
        return;
    }
    elsif ($existing_email && (!$item || $item->id != $existing_email->id)) {
        $c->log->error("admin with email '$$resource{email}' already exists");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Admin with this email already exists");
        return;
    }
    return 1;
}

sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    if ($form->field('password')){
        $form->field('password')->{required} = 0;
    }
    $form //= $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
    );

    if ($item->id == $c->user->id) {
        # user cannot modify the following own permissions for security reasons
        my $own_forbidden = 0;
        foreach my $k (qw(login role is_master is_active
                          is_system is_superuser lawful_intercept
                          read_only show_passwords
                          call_data billing_data)) {
            if (defined $old_resource->{$k} && defined $resource->{$k}) {
                if ($old_resource->{$k} ne $resource->{$k}) {
                    $own_forbidden = 1;
                    last;
                }
            } elsif (defined $resource->{$k}) {
                $own_forbidden = 1;
                last;
            }
        }
        if ($own_forbidden) {
            $self->error($c, HTTP_FORBIDDEN, "User cannot modify own permissions");
            return;
        }
        delete $resource->{role};
    } else {
        $resource = NGCP::Panel::Utils::UserRole::resolve_resource_role($c, $resource);
        if (defined $resource->{role_id} &&
            ! NGCP::Panel::Utils::UserRole::has_permission(
                    $c, $c->user->acl_role->id, $resource->{role_id})) {
            $self->error($c, HTTP_FORBIDDEN, "Cannot change user role");
            return;
        }
    }

    my $pass = $resource->{password};
    delete $resource->{password};
    if (defined $pass && $pass ne $old_resource->{saltedpass}) {
        if ($c->user->id != $item->id) {
            $self->error($c, HTTP_FORBIDDEN, "Only own user can change password");
            return;
        }
        $resource->{md5pass} = undef;
        $resource->{saltedpass} = NGCP::Panel::Utils::Auth::generate_salted_hash($pass);
    }

    if ($old_resource->{login} eq NGCP::Panel::Utils::Auth::get_special_admin_login()) {
        my $active = $resource->{is_active};
        $resource = $old_resource;
        $resource->{is_active} = $active;
    }

    $item->update($resource);

    return $item;
}

sub post_process_hal_resource {
    my ($self, $c, $item, $resource, $form) = @_;

    if ($c->user->id == $item->id) {
        $resource->{role} = $c->user->roles;
    }

    return $resource;
}

1;
# vim: set tabstop=4 expandtab:
