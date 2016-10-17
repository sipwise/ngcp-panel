package NGCP::Panel::Controller::API::RewriteRuleSets;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Rewrite;
use Path::Tiny qw(path);
use Safe::Isa qw($_isa);
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines a collection of <a href="#rewriterules">Rewrite Rules</a>.';
};

sub query_params {
    return [
        {
            param => 'reseller_id',
            description => 'Filter for rewriterulesets belonging to a specific reseller',
            query => {
                first => sub {
                    my $q = shift;
                    { reseller_id => $q };
                },
                second => sub {},
            },
        },
        {
            param => 'description',
            description => 'Filter rulesets for a certain description (wildcards possible).',
            query => {
                first => sub {
                    my $q = shift;
                    return { description => { like => $q } };
                },
                second => sub {},
            },
        },
        {
            param => 'name',
            description => 'Filter rulesets for a certain name (wildcards possible).',
            query => {
                first => sub {
                    my $q = shift;
                    return { name => { like => $q } };
                },
                second => sub {},
            },
        },
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::RewriteRuleSets/;

sub resource_name{
    return 'rewriterulesets';
}
sub dispatch_path{
    return '/api/rewriterulesets/';
}
sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-rewriterulesets';
}

__PACKAGE__->config(
    action => {
        map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin reseller/],
            Args => 0,
            Does => [qw(ACL CheckTrailingSlash RequireSSL)],
            Method => $_,
            Path => __PACKAGE__->dispatch_path,
        } } @{ __PACKAGE__->allowed_methods },
    },
    action_roles => [qw(+NGCP::Panel::Role::HTTPMethods)],
);

sub auto :Private {
    my ($self, $c) = @_;

    $self->set_body($c);
    $self->log_request($c);
    return 1;
}

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $rwr_set = $self->item_rs($c, "rulesets");
        (my $total_count, $rwr_set) = $self->paginate_order_collection($c, $rwr_set);
        my (@embedded, @links);
        for my $set ($rwr_set->all) {
            push @embedded, $self->hal_from_item($c, $set, "rewriterulesets");
            push @links, NGCP::Panel::Utils::DataHalLink->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('%s%d', $self->dispatch_path, $set->id),
            );
        }
        push @links,
            NGCP::Panel::Utils::DataHalLink->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'self', href => sprintf('%s?page=%s&rows=%s', $self->dispatch_path, $page, $rows));
        if(($total_count / $rows) > $page ) {
            push @links, NGCP::Panel::Utils::DataHalLink->new(relation => 'next', href => sprintf('%s?page=%d&rows=%d', $self->dispatch_path, $page + 1, $rows));
        }
        if($page > 1) {
            push @links, NGCP::Panel::Utils::DataHalLink->new(relation => 'prev', href => sprintf('%s?page=%d&rows=%d', $self->dispatch_path, $page - 1, $rows));
        }

        my $hal = NGCP::Panel::Utils::DataHal->new(
            embedded => [@embedded],
            links => [@links],
        );
        $hal->resource({
            total_count => $total_count,
        });
        my $response = HTTP::Response->new(HTTP_OK, undef, 
            HTTP::Headers->new($hal->http_headers(skip_links => 1)), $hal->as_json);
        $c->response->headers($response->headers);
        $c->response->body($response->content);
        return;
    }
    return;
}

sub HEAD :Allow {
    my ($self, $c) = @_;
    $c->forward(qw(GET));
    $c->response->body(q());
    return;
}

sub OPTIONS :Allow {
    my ($self, $c) = @_;
    my $allowed_methods = $self->allowed_methods_filtered($c);
    $c->response->headers(HTTP::Headers->new(
        Allow => join(', ', @{ $allowed_methods }),
        Accept_Post => 'application/hal+json; profile=http://purl.org/sipwise/ngcp-api/#rel-'.$self->resource_name,
    ));
    $c->response->content_type('application/json');
    $c->response->body(JSON::to_json({ methods => $allowed_methods })."\n");
    return;
}

sub POST :Allow {
    my ($self, $c) = @_;

    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $schema = $c->model('DB');
        my $resource = $self->get_valid_post_data(
            c => $c,
            media_type => 'application/json',
        );
        last unless $resource;

        my $reseller_id;
        if($c->user->roles eq "admin") {
            try {
                $reseller_id = $resource->{reseller_id}
                     || $c->user->contract->contact->reseller_id;
             }
        } elsif($c->user->roles eq "reseller") {
            $reseller_id = $c->user->reseller_id;
        }
        $resource->{reseller_id} = $reseller_id;

        my $reseller = $c->model('DB')->resultset('resellers')->find($resource->{reseller_id});
        unless($reseller) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'reseller_id', doesn't exist.");
            last;
        }

        my $rewriterules = $resource->{rewriterules};

        my $form = $self->get_form($c);
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
        );

        my $ruleset_test = $schema->resultset('voip_rewrite_rule_sets')->search_rs({
                name => $resource->{name}
            })->first;
        if ($ruleset_test) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Ruleset with this 'name' already exists.");
            last;
        }

        my $ruleset;

        try {
            $ruleset = $schema->resultset('voip_rewrite_rule_sets')->create($resource);
        } catch($e) {
            $c->log->error("failed to create rewriteruleset: $e"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create rewriteruleset.");
            last;
        }

        if ($rewriterules) {
            my $i = 30;
            if (ref($rewriterules) ne "ARRAY") {
                $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "rewriterules must be an array.");
            }
            for my $rule (@{ $rewriterules }) {
                my $rule_form = $self->get_form($c, "rules");
                last unless $self->validate_form(
                    c => $c,
                    resource => $rule,
                    form => $rule_form,
                );
                try {
                    $ruleset->voip_rewrite_rules->create({
                        %{ $rule },
                        priority => $i++,
                    });
                } catch($e) {
                    $c->log->error("failed to create rewriterules: $e"); # TODO: user, message, trace, ...
                    $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create rewrite rules.");
                    last;
                }
            }
        }

        $guard->commit;
        NGCP::Panel::Utils::Rewrite::sip_dialplan_reload($c);

        $c->response->status(HTTP_CREATED);
        $c->response->header(Location => sprintf('/%s%d', $c->request->path, $ruleset->id));
        $c->response->body(q());
    }
    return;
}

sub end : Private {
    my ($self, $c) = @_;

    $self->log_response($c);
    return 1;
}

1;

# vim: set tabstop=4 expandtab:
