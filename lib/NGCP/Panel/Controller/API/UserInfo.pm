package NGCP::Panel::Controller::API::UserInfo;

use Sipwise::Base;

use Data::HAL qw();
use Data::HAL::Link qw();
use File::Basename;
use File::Find::Rule;
use HTTP::Headers qw();
use HTTP::Status qw(:constants);


sub allowed_methods{
    return [qw/GET OPTIONS/];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::UserInfo/;

sub api_description {
    return '';
};

sub query_params {
    return [
    ];
}

sub resource_name{
    return 'userinfo';
}

sub dispatch_path{
    return '/api/userinfo/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-userinfo';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller ccare ccareadmin subscriber subscriberadmin/],
});

sub GET :Allow {
    my ($self, $c) = @_;

    my $operations_map = {
        'GET'    => 'read',
        'POST'   => 'create',
        'PATCH'  => 'update',
        'PUT'    => 'update',
        'DELETE' => 'delete',
    };

    my $blacklist = {
        "DomainPreferenceDefs" => 1,
        "SubscriberPreferenceDefs" => 1,
        "CustomerPreferenceDefs" => 1,
        "ProfilePreferenceDefs" => 1,
        "PeeringServerPreferenceDefs" => 1,
        "ResellerPreferenceDefs" => 1,
        "PbxDevicePreferenceDefs" => 1,
        "PbxDeviceProfilePreferenceDefs" => 1,
        "PbxFieldDevicePreferenceDefs" => 1,
        "MetaConfigDefs" => 1,
    };

    my $res = { username => $c->user->login, role => $c->user->roles };

    my $colls = NGCP::Panel::Utils::API::get_collections_files;
    my %user_roles = map {$_ => 1} $c->user->roles;
    foreach my $coll (@$colls) {
        my $mod = $coll;
        $mod =~ s/^.+\/([a-zA-Z0-9_]+)\.pm$/$1/;
        next if (exists $blacklist->{$mod});
        my $rel = lc $mod;
        my $full_mod = 'NGCP::Panel::Controller::API::' . $mod;
        my $full_item_mod = 'NGCP::Panel::Controller::API::' . $mod . 'Item';

        my $role = $full_mod->config->{action}->{OPTIONS}->{AllowedRole};
        if ($role && ref $role eq "ARRAY") {
            next unless grep { $user_roles{$_}; } @{ $role };
        } elsif ($role) {
            next unless $user_roles{$role};
        }

        $res->{permissions}->{entity}->{$rel}->{'$p'} = {
            create => JSON::false,
            read => JSON::false,
            update => JSON::false,
            delete => JSON::false,
        };
        my $actions = [];
        if ($c->user->read_only) {
            foreach my $m (sort keys %{ $full_mod->config->{action} }) {
                next unless $m =~ /^(GET|HEAD|OPTIONS)$/;
                push @{ $actions }, $m;
            }
        } else {
            $actions = [ sort keys %{ $full_mod->config->{action} } ];
        }
        foreach my $action (@$actions) {
            my $operation = $operations_map->{$action};
            next unless $operation;
            $res->{permissions}->{entity}->{$rel}->{'$p'}->{$operation} = JSON::true;
        }
        my $item_actions = [];
        if ($full_item_mod->can('config')) {
            if ($c->user->read_only) {
                foreach my $m (sort keys %{ $full_item_mod->config->{action} }) {
                    next unless $m =~ /^(GET|HEAD|OPTIONS)$/;
                    push @{ $item_actions }, $m;
                }
            } else {
                foreach my $m (sort keys %{ $full_item_mod->config->{action} }) {
                    next unless $m =~ /^(GET|HEAD|OPTIONS|PUT|PATCH|DELETE)$/;
                    push @{ $item_actions }, $m;
                }
            }
            foreach my $action (@$item_actions) {
                my $operation = $operations_map->{$action};
                next unless $operation;
                $res->{permissions}->{entity}->{$rel}->{'$p'}->{$operation} = JSON::true;
            }
        }
        if ($full_item_mod->can('get_form')) {
            my $form = $full_item_mod->get_form($c);
            if ($form) {
                foreach my $field ($form->fields) {
                    next if (
                        $field->type eq "Hidden" ||
                        $field->type eq "Button" ||
                        $field->type eq "Submit" ||
                        0);
                    $res->{permissions}->{entity}->{$rel}->{columns}->{$field->name}->{'$p'} = {
                        $field->{read_only} ? (create => JSON::false) : (create => JSON::true),
                        read => JSON::true,
                        $field->{read_only} ? (update => JSON::false) : (update => JSON::true),
                        $field->{read_only} ? (delete => JSON::false) : (delete => JSON::true),
                    };
                }
            }
        }
    }
    $c->response->status(HTTP_OK);
    $c->response->body(JSON::to_json($res));
    return;
}

1;

# vim: set tabstop=4 expandtab:
