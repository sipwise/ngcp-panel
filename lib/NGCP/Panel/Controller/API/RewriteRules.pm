package NGCP::Panel::Controller::API::RewriteRules;
use Sipwise::Base;
use namespace::sweep;
use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use MooseX::ClassAttribute qw(class_has);
use NGCP::Panel::Utils::DateTime;
BEGIN { extends 'Catalyst::Controller::ActionRole'; }
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require Catalyst::ActionRole::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

class_has 'api_description' => (
    is => 'ro',
    isa => 'Str',
    default => 
        'Defines a set of Rewrite Rules which are grouped in <a href="#rewriterulesets">Rewrite Rule Sets</a>. They can be used to alter incoming and outgoing numbers.',
);

class_has 'query_params' => (
    is => 'ro',
    isa => 'ArrayRef',
    default => sub {[
        {
            param => 'description',
            description => 'Filter rules for a certain description (wildcards possible).',
            query => {
                first => sub {
                    my $q = shift;
                    return { description => { like => $q } };
                },
                second => sub {},
            },
        },
        {
            param => 'set_id',
            description => 'Filter for rules belonging to a specific rewriteruleset.',
            query => {
                first => sub {
                    my $q = shift;
                    return { set_id => $q };
                },
                second => sub {},
            },
        },
    ]},
);


with 'NGCP::Panel::Role::API::RewriteRules';

class_has('resource_name', is => 'ro', default => 'rewriterules');
class_has('dispatch_path', is => 'ro', default => '/api/rewriterules/');
class_has('relation', is => 'ro', default => 'http://purl.org/sipwise/ngcp-api/#rel-rewriterules');

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
    action_roles => [qw(HTTPMethods)],
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
        my $rules = $self->item_rs($c, "rules");

        (my $total_count, $rules) = $self->paginate_order_collection($c, $rules);
        my (@embedded, @links);
        for my $rule ($rules->search({}, {order_by => {-asc => 'me.id'}})->all) {
            push @embedded, $self->hal_from_item($c, $rule, "rewriterules");
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('%s%d', $self->dispatch_path, $rule->id),
            );
        }
        push @links,
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            Data::HAL::Link->new(relation => 'self', href => sprintf('%s?page=%s&rows=%s', $self->dispatch_path, $page, $rows));
        if(($total_count / $rows) > $page ) {
            push @links, Data::HAL::Link->new(relation => 'next', href => sprintf('%s?page=%d&rows=%d', $self->dispatch_path, $page + 1, $rows));
        }
        if($page > 1) {
            push @links, Data::HAL::Link->new(relation => 'prev', href => sprintf('%s?page=%d&rows=%d', $self->dispatch_path, $page - 1, $rows));
        }

        my $hal = Data::HAL->new(
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
    my $allowed_methods = $self->allowed_methods;
    $c->response->headers(HTTP::Headers->new(
        Allow => $allowed_methods->join(', '),
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

        my $set_id = delete $resource->{set_id}; # keep this, cause formhandler doesn't know it

        my $form = $self->get_form($c);
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
        );

        my $rule;

        unless(defined $set_id) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Required: 'set_id'");
            last;
        }

        my $reseller_id;
        if($c->user->roles eq "reseller") {
            $reseller_id = $c->user->reseller_id;
        }

        my $ruleset = $schema->resultset('voip_rewrite_rule_sets')->find({
                id => $set_id,
                ($reseller_id ? (reseller_id => $reseller_id) : ()),
            });
        unless($ruleset) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'set_id'.");
            last;
        }
        $resource->{set_id} = $ruleset->id;
        try {
            $rule = $schema->resultset('voip_rewrite_rules')->create($resource);
        } catch($e) {
            $c->log->error("failed to create rewriterule: $e"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create rewriterule.");
            last;
        }

        $guard->commit;

        $c->response->status(HTTP_CREATED);
        $c->response->header(Location => sprintf('/%s%d', $c->request->path, $rule->id));
        $c->response->body(q());
    }
    return;
}

sub end : Private {
    my ($self, $c) = @_;

    $self->log_response($c);
    return 1;
}

# vim: set tabstop=4 expandtab:
