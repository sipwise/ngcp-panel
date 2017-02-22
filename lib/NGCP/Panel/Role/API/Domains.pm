package NGCP::Panel::Role::API::Domains;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';

use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use JSON::Types;
use NGCP::Panel::Form::Domain::Admin qw();
use NGCP::Panel::Form::Domain::Reseller qw();
use NGCP::Panel::Utils::XMLDispatcher;
use NGCP::Panel::Utils::Prosody;

sub get_form {
    my ($self, $c) = @_;
    if($c->user->roles eq "admin") {
        return NGCP::Panel::Form::Domain::Admin->new;
    } elsif($c->user->roles eq "reseller") {
        return NGCP::Panel::Form::Domain::Reseller->new;
    }
    return;
}

sub hal_from_item {
    my ($self, $c, $item, $form) = @_;
    my %resource = $item->get_inflated_columns;

    my $hal = NGCP::Panel::Utils::DataHal->new(
        links => [
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'collection', href => sprintf("/api/%s/", $self->resource_name)),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            Data::HAL::Link->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $item->id)),
            #( map { $_->attribute->internal ? () : Data::HAL::Link->new(relation => 'ngcp:domainpreferences', href => sprintf("/api/domainpreferences/%d", $_->id), name => $_->attribute->attribute) } $item->provisioning_voip_domain->voip_dom_preferences->all ),
            Data::HAL::Link->new(relation => 'ngcp:domainpreferences', href => sprintf("/api/domainpreferences/%d", $item->id)),
            $self->get_journal_relation_link($item->id),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $form //= $self->get_form($c);

    $self->validate_form(
        c => $c,
        resource => \%resource,
        form => $form,
        run => 0,
    );

    $resource{id} = int($item->id);
    if($c->user->roles eq "admin") {
        $resource{reseller_id} = 
            int($item->domain_resellers->first->reseller_id)
            if($item->domain_resellers->first);
    } elsif($c->user->roles eq "reseller") {
    }

=pod
    # TODO: do we really want to provide this info, as you can't actually
    # PUT/PATCH/POST it? Or should you?
    $resource{preferences} = {};
    foreach my $pref($item->provisioning_voip_domain->voip_dom_preferences->all) {
        next if($pref->attribute->internal);
        my $plain = { "boolean" => 1, "int" => 1, "string" => 1 };
        if(exists $plain->{$pref->attribute->data_type}) {
            # plain key/value pairs
            my $value;
            SWITCH: for ($pref->attribute->data_type) {
                /^int$/ && do {
                    $value = int($pref->value);
                    last SWITCH;
                };
                /^boolean$/ && do {
                    $value = JSON::Types::bool($pref->value);
                    last SWITCH;
                };
                # default
                $value = $pref->value;
            } # SWITCH
            if($pref->attribute->max_occur != 1) {
                $resource{preferences}{$pref->attribute->attribute} = $value;
            } else {
                $resource{preferences}{$pref->attribute->attribute} = []
                    unless(exists $resource{preferences}{$pref->attribute->attribute});
                push @{ $resource{preferences}{$pref->attribute->attribute} }, $value;
            }
        } else {
            # enum mappings
            my $value;
            SWITCH: for ($pref->attribute->data_type) {
                /^int$/ && do {
                    $value = int($pref->value);
                    last SWITCH;
                };
                /^boolean$/ && do {
                    $value = JSON::Types::bool($pref->value);
                    last SWITCH;
                };
                # default
                $value = $pref->value;
            } # SWITCH
            $resource{preferences}{$pref->attribute->attribute} = $value;
        }
    }
=cut    
    
    $hal->resource({%resource});
    return $hal;
}

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs;
    if($c->user->roles eq "admin") {
        $item_rs = $c->model('DB')->resultset('domains');
    } elsif($c->user->roles eq "reseller") {
        $item_rs = $c->model('DB')->resultset('admins')->find(
                { id => $c->user->id, } )
            ->reseller
            ->domain_resellers
            ->search_related('domain');
    }
    return $item_rs;
}

sub item_by_id {
    my ($self, $c, $id) = @_;

    my $item_rs = $self->item_rs($c);
    return $item_rs->find($id);
}

sub sip_domain_reload {
    my ($self, $c) = @_;
    my $dispatcher = NGCP::Panel::Utils::XMLDispatcher->new;
    my ($res) = $dispatcher->dispatch($c, "proxy-ng", 1, 1, <<EOF );
<?xml version="1.0" ?>
<methodCall>
<methodName>domain.reload</methodName>
<params/>
</methodCall>
EOF

    return ref $res ? @{ $res } : ();
}

sub xmpp_domain_reload {
    my ($self, $c, $domain) = @_;
    NGCP::Panel::Utils::Prosody::activate_domain($c, $domain);
}

sub xmpp_domain_disable {
    my ($self, $c, $domain) = @_;
    NGCP::Panel::Utils::Prosody::deactivate_domain($c, $domain);
}

=pod
# you can't update a domain per se, only its preferences!
sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    $form //= $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
    );

    $item->update($resource);

    return $item;
}
=cut

1;
# vim: set tabstop=4 expandtab:
