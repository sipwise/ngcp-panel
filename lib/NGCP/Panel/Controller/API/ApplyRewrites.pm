package NGCP::Panel::Controller::API::ApplyRewrites;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);


sub allowed_methods{
    return [qw/POST OPTIONS/];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::ApplyRewrites/;

sub api_description {
    return 'Applies rewrite rules to a given number according to the given direction. It can for example be used to normalize user input to E164 using callee_in direction, or to denormalize E164 to user output using caller_out.';
};

sub query_params {
    return [
    ];
}

sub resource_name{
    return 'applyrewrites';
}

sub dispatch_path{
    return '/api/applyrewrites/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-applyrewrites';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
});

sub POST :Allow {
    my ($self, $c) = @_;
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $resource = $self->get_valid_post_data(
            c => $c, 
            media_type => 'application/json',
        );
        last unless $resource;

        my $form = $self->get_form($c);
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
        );

        my $subscriber_rs = $c->model('DB')->resultset('voip_subscribers')->search({
            'me.id' => $resource->{subscriber_id},
            'me.status' => { '!=' => 'terminated' },
        });
        if($c->user->roles eq "admin") {
        } elsif($c->user->roles eq "reseller") {
            $subscriber_rs = $subscriber_rs->search({
                'contact.reseller_id' => $c->user->reseller_id,
            },{
                join => { contract => 'contact' },
            });
        }
        my $subscriber = $subscriber_rs->first;
        unless($subscriber) {
            $c->log->error("invalid subscriber id $$resource{subscriber_id} for outbound call");
            $self->error($c, HTTP_NOT_FOUND, "Calling subscriber not found.");
            last;
        }

        my $normalized;
        try {

            $normalized = NGCP::Panel::Utils::Subscriber::apply_rewrite(
                c => $c, subscriber => $subscriber, 
                number => $resource->{number}, direction => $resource->{direction},
            );
        } catch($e) {
            $c->log->error("failed to rewrite number: $e");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to rewrite number.");
            last;
        }

        $guard->commit;

        my $res = '{ "result": "'.$normalized.'" }'."\n";

        $c->response->status(HTTP_OK);
        $c->response->body($res);
    }
    return;
}

1;

# vim: set tabstop=4 expandtab:
