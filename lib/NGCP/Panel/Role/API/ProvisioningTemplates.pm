package NGCP::Panel::Role::API::ProvisioningTemplates;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use Scalar::Util qw/blessed/;
use JSON qw();

use NGCP::Panel::Utils::ProvisioningTemplates qw();
use NGCP::Panel::Utils::API qw();
use NGCP::Panel::Utils::Generic qw(trim);

sub _item_rs {

    my ($self, $c) = @_;

    unless ($c->stash->{provisioning_templates}) {
        NGCP::Panel::Utils::ProvisioningTemplates::load_template_map($c);
    }

    my $editable;
    if (length($c->req->param('editable'))) {
        if ('1' eq $c->req->param('editable')
            or 'true' eq lc($c->req->param('editable'))) {
            $editable = 1;
        } elsif ('0' eq $c->req->param('editable')
            or 'false' eq lc($c->req->param('editable'))) {
            $editable = 0;
        }
    }

    my @result = ();

    foreach my $id (keys %{$c->stash->{provisioning_templates}}) {
        my $template = $c->stash->{provisioning_templates}->{$id};
        my $include = 1;
        if (defined $editable) {
            if ($editable) {
                $include &= ($template->{static} ? 0 : 1);
            } else {
                $include &= ($template->{static} ? 1 : 0);
            }
        }
        push(@result,$self->item_by_id($c,$id)) if $include;
    }

    return \@result;

}

sub get_id {

    my ($self,$reseller_name,$name) = @_;
    my $id = '';
    $id .= ($reseller_name . '/') if length($reseller_name);
    $id .= $name;
    return $id;

}

sub get_item_id {

    my($self, $c, $item, $resource, $form, $params) = @_;
    return unless defined $item;
    if (blessed($item)) {
        return $self->get_id(($item->reseller ? $item->reseller->name : undef), $item->name);
    } else {
        return unless scalar keys %$item;
        my $reseller_name;
        if (exists $item->{reseller}) {
            $reseller_name = $item->{reseller};
        } else {
            my $reseller;
            $reseller = $c->model('DB')->resultset('resellers')->find(
                $item->{reseller_id}) if $item->{reseller_id};
            $reseller_name = $reseller->name if $reseller;
        }
        return $self->get_id($reseller_name, $item->{name});
    }

}

sub valid_id {

    my ($self, $c, $id) = @_;
    return 1 if length($id);
    $self->error($c, HTTP_BAD_REQUEST, "Invalid id in request URI");
    return;

}

sub get_form {

    my ($self, $c, $type, $id) = @_;
    if ($type and 'form' eq lc($type)) {
        unless ($c->stash->{provisioning_templates}) {
            NGCP::Panel::Utils::ProvisioningTemplates::load_template_map($c);
        }
        $c->stash->{provisioning_template_name} = $id;
        return NGCP::Panel::Utils::ProvisioningTemplates::get_provisioning_template_form($c);
    } else {
        if ($c->user->is_superuser) {
            return NGCP::Panel::Form::get("NGCP::Panel::Form::ProvisioningTemplate::AdminAPI", $c);
        } else {
            return NGCP::Panel::Form::get("NGCP::Panel::Form::ProvisioningTemplate::ResellerAPI", $c);
        }
    }

}

sub resource_from_item {

    my ($self, $c, $item) = @_;

    my %resource;
    if (blessed($item)) {
        %resource = $item->get_inflated_columns;
        if ($c->req->param('format')) {
            if (grep { $_ eq lc($c->req->param('format')); } qw(yml yaml)) {
                $resource{template} = delete $resource{yaml};
            } elsif ('json' eq lc($c->req->param('format'))) {
                eval {
                    $resource{template} = _template_as_json(NGCP::Panel::Utils::ProvisioningTemplates::parse_template($c, $resource{id}, $resource{name}, delete $resource{yaml}));
                };
            }
        } else {
            eval {
                $resource{template} = NGCP::Panel::Utils::ProvisioningTemplates::parse_template($c, $resource{id}, $resource{name}, delete $resource{yaml});
            };
        }
    } else {
        %resource = ();
        $resource{name} = $item->{name};
        $resource{description} = $item->{description};
        $resource{lang} = $item->{lang};
        $resource{id} = $self->get_item_id($c,$item);
        $resource{reseller_id} = undef;
        #delete $resource{reseller};
        $resource{template} = $item;
        delete @{$item}{qw(id reseller static)};
        if ($c->req->param('format')) {
            if (grep { $_ eq lc($c->req->param('format')); } qw(yml yaml)) {
                eval {
                    $resource{template} = NGCP::Panel::Utils::ProvisioningTemplates::dump_template($c, $resource{id}, $resource{name}, $resource{template});
                };
            } elsif ('json' eq lc($c->req->param('format'))) {
                $resource{template} = _template_as_json($resource{template});
            }
        }
    }

    return \%resource;

}

sub _template_as_json {

    my $template = shift;
    return JSON::to_json($template, {
        allow_nonref => 1, allow_blessed => 1,
        canonical => 1, utf8 => 1,
        convert_blessed => 1, pretty => 1 });

}

sub _template_from_json {

    my $template = shift;
    return JSON::from_json($template, { utf8 => 1 });

}

sub item_by_id {

    my ($self, $c, $id) = @_;

    return unless length($id);

    unless ($c->stash->{provisioning_templates}) {
        NGCP::Panel::Utils::ProvisioningTemplates::load_template_map($c);
    }

    my $item = $c->stash->{provisioning_templates}->{$id};

    if ($item and $item->{id}) {
        $item = $c->model('DB')->resultset('provisioning_templates')->find($item->{id});
    }
    return $item;

}

sub check_resource {

    my($self, $c, $item, $old_resource, $resource, $form) = @_;

    if ($item
        and not blessed($item)) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Provisioning template cannot be updated");
        return;
    }

    NGCP::Panel::Utils::API::apply_resource_reseller_id($c,$resource);
    return unless NGCP::Panel::Utils::API::check_resource_reseller_id($self,$c,$resource,$old_resource);

    eval {
        my $reseller;
        $reseller = $c->model('DB')->resultset('resellers')->find(
            $resource->{reseller_id}) if $resource->{reseller_id};
        NGCP::Panel::Utils::ProvisioningTemplates::validate_template_name($c,
            $resource->{name},($old_resource ? $old_resource->{name} : undef),
            $reseller);
    };
    if ($@) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY,trim($@));
        return;
    }

    eval {
        if ($c->req->param('format')) {
            if (grep { $_ eq lc($c->req->param('format')); } qw(yml yaml)) {
                $resource->{template} = NGCP::Panel::Utils::ProvisioningTemplates::parse_template($c, $resource->{id}, $resource->{name}, $resource->{template});
            } elsif ('json' eq lc($c->req->param('format'))) {
                $resource->{template} = _template_from_json($resource->{template});
            }
        }
        NGCP::Panel::Utils::ProvisioningTemplates::validate_template($resource->{template});
    };
    if ($@) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY,trim($@));
        return;
    }

    return 1;
}

sub process_form_resource {

    my($self, $c, $item, $old_resource, $resource, $form) = @_;

    NGCP::Panel::Utils::API::apply_resource_reseller_id($c,$resource);

    return $resource;

}

sub get_journal_item_hal {

    my ($self, $c, $item, $params) = @_;
    my ($hal,$id) = $self->SUPER::get_journal_item_hal($c, $item, $params);
    $hal->{id} = $item->id if $hal;
    return ($hal,($hal ? $hal->{id} : undef));

}

1;
