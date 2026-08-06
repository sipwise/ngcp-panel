package NGCP::Panel::Role::API::CallListSuppressions;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';

use HTTP::Status qw(:constants);

sub resource_name {
    return 'calllistsuppressions';
}

sub _item_rs {
    my ($self, $c) = @_;

    return $c->model('DB')->resultset('call_list_suppressions');
}

sub get_form {
    my ($self, $c) = @_;

    return NGCP::Panel::Form::get("NGCP::Panel::Form::CallListSuppression::SuppressionAPI", $c);
}

sub process_form_resource {
    my ($self, $c, $item, $old_resource, $resource, $form, $process_extras) = @_;

    # the domain column is NOT NULL with an empty string default, which means
    # "apply to subscribers of any domain". Normalize a missing or null domain
    # so it doesn't hit the DB as NULL, and so a PUT omitting it resets it.
    $resource->{domain} //= '';

    return 1;
}

sub check_duplicate {
    my ($self, $c, $item, $old_resource, $resource, $form, $process_extras) = @_;

    my $dup_item = $c->model('DB')->resultset('call_list_suppressions')->search({
        $item ? (id => { '!=' => $item->id }) : (),
        domain => $resource->{domain},
        direction => $resource->{direction},
        pattern => $resource->{pattern},
    })->first;

    if ($dup_item) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY,
                     "The combination of domain, direction and pattern must be unique",
                     "call list suppression with domain '$$resource{domain}', direction '$$resource{direction}' and pattern '$$resource{pattern}' already exists");
        return;
    }

    return 1;
}

1;
# vim: set tabstop=4 expandtab:
