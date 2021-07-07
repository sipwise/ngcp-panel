package NGCP::Panel::Controller::API::AuthTokens;

use Sipwise::Base;

use Data::HAL qw();
use Data::HAL::Link qw();
use File::Basename;
use File::Find::Rule;
use HTTP::Headers qw();
use HTTP::Status qw(:constants);


sub allowed_methods{
    return [qw/POST OPTIONS/];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::AuthTokens/;

sub api_description {
    return '';
};

sub query_params {
    return [
    ];
}

sub resource_name{
    return 'authtokens';
}

sub dispatch_path{
    return '/api/authtokens/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-authtokens';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller ccare ccareadmin subscriber subscriberadmin/],
});

sub POST :Allow {
    my ($self, $c) = @_;

    my $resource = $self->get_valid_post_data(
        c => $c, 
        media_type => 'application/json',
    );
    return unless $resource;

    my $form = $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        resource => $resource,
        form => $form,
    );
    if($c->user->roles eq "reseller") {
        $resource->{reseller_id} = $c->user->reseller_id;
    }
    
    my $res = {};

    $res->{token} = $self->generate_auth_token($c, $resource);

    $c->response->status(HTTP_CREATED);
    $c->response->body(JSON::to_json($res));
    return;
}

1;

# vim: set tabstop=4 expandtab:
