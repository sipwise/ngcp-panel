package NGCP::Panel::Role::API::TimeSets;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';

use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::Subscriber;
use NGCP::Panel::Utils::TimeSet;
use NGCP::Panel::Form;

sub resource_name {
    return 'timesets';
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::get("NGCP::Panel::Form::TimeSet::API", $c);
}

sub hal_links{
    my($self, $c, $item, $resource, $form) = @_;
    my $adm = $c->user->roles eq "admin" || $c->user->roles eq "reseller";
    return [
        Data::HAL::Link->new(relation => "ngcp:resellers", href => sprintf("/api/resellers/%d", $resource->{reseller_id})),
    ];
}

sub _item_rs {
    my ($self, $c) = @_;
    my $item_rs;

    if($c->user->roles eq "admin") {
        $item_rs = $c->model('DB')->resultset('voip_time_sets');
    } elsif ($c->user->roles eq "reseller") {
        my $reseller_id = $c->user->reseller_id;
        $item_rs = $c->model('DB')->resultset('voip_time_sets')
            ->search_rs({
                    'reseller_id' => $reseller_id,
                });
    }

    return $item_rs;
}

sub resource_from_item {
    my ($self, $c, $item, $form) = @_;
    my $resource = NGCP::Panel::Utils::TimeSet::get_timeset(
        c => $c, timeset => $item, date_mysql_format => 1);
    return $resource;
}

# called automatically by POST (and manually by update_item if you want)
sub check_resource {
    my($self, $c, $item, $old_resource, $resource, $form) = @_;

    my $schema = $c->model('DB');

    if(!defined $resource->{reseller_id}) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Missing mandatory field 'reseller_id'");
        return;
    }

    my $reseller = $schema->resultset('resellers')->find({
            id => $resource->{reseller_id},
        });
    unless ($reseller) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'reseller_id'.");
        return;
    }

    if (! exists $resource->{times} ) {
        $resource->{times} = [];
    }
    if (ref $resource->{times} ne "ARRAY") {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid field 'times'. Must be an array.");
        return;
    }

    return 1; # all good
}

sub check_duplicate {
    my($self, $c, $item, $old_resource, $resource, $form, $process_extras) = @_;

    my $schema = $c->model('DB');

    my $existing_item = $schema->resultset('voip_time_sets')->find({
        name => $resource->{name},
    });
    if ($existing_item && (!$item || $item->id != $existing_item->id)) {
        $c->log->error("time_set name '$$resource{name}' already exists");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "time_set with this name already exists");
        return;
    }
    return 1;
}

sub update_item_model {
    my($self, $c, $item, $old_resource, $resource, $form) = @_;

    try {
        NGCP::Panel::Utils::TimeSet::update_timesets( 
            c => $c,
            timeset  => $item,
            resource => $resource,
            form     => $form
        );
        $item->discard_changes;
    } catch($e) {
        $c->log->error("failed to update timeset: $e");
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to update timesets.");
        return;
    };

    return $item;
}

1;
# vim: set tabstop=4 expandtab:
