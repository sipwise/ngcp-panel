package NGCP::Panel::Controller::API::BalanceIntervalsItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::ValidateJSON qw();
use Path::Tiny qw(path);
use Safe::Isa qw($_isa);
require Catalyst::ActionRole::ACL;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::BalanceIntervals/;

sub resource_name{
    return 'balanceintervals';
}
sub dispatch_path{
    return '/api/balanceintervals/';
}
sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-balanceintervals';
}

#sub journal_query_params {
#    my($self,$query_params) = @_;
#    return $self->get_journal_query_params($query_params);
#}

sub query_params {
    return [
        {
            param => 'start',
            description => 'Filter balance intervals starting after or at the specified time stamp.',
            query => {
                first => sub {
                    my $q = shift;
                    my $dt = NGCP::Panel::Utils::DateTime::from_string($q);
                    return { 'start' => { '>=' => $dt  } };
                },
                second => sub { },
            },
        },
        #the end value of intervals is not constant along the retrieval operations 
    ];
}

__PACKAGE__->config(
    action => {
        (map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin reseller/],
            Args => 1,
            Does => [qw(ACL RequireSSL)],
            Method => $_,
            Path => __PACKAGE__->dispatch_path,
        } } @{ __PACKAGE__->allowed_methods }),
        item_base => {
            Chained => '/',
            PathPart => 'api/' . __PACKAGE__->resource_name,
            CaptureArgs => 1,
        },
        item_get => {
            Chained => 'item_base',
            PathPart => '',
            Args => 1,
            Method => 'GET',
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin reseller/],
            Does => [qw(ACL RequireSSL)]
        },
        item_options => {
            Chained => 'item_base',
            PathPart => '',
            Args => 1,
            Method => 'OPTIONS',
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin reseller/],
            Does => [qw(ACL RequireSSL)]
        },
        item_head => {
            Chained => 'item_base',
            PathPart => '',
            Args => 1,
            Method => 'OPTIONS',
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin reseller/],
            Does => [qw(ACL RequireSSL)]
        },        
    },
    action_roles => [qw(+NGCP::Panel::Role::HTTPMethods)],
);

sub auto :Private {
    my ($self, $c) = @_;

    $self->set_body($c);
    $self->log_request($c);
    #$self->apply_fake_time($c);    
}

sub GET :Allow {
    my ($self, $c, $id) = @_;
    
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    $c->model('DB')->set_transaction_isolation('READ COMMITTED');
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $now = NGCP::Panel::Utils::DateTime::current_local;
        last unless $self->valid_id($c, $id);
        my $contract = $self->contract_by_id($c, $id);
        last unless $self->resource_exists($c, contract => $contract);
        my $balances = $self->balances_rs($c,$contract,$now);
        (my $total_count, $balances) = $self->paginate_order_collection($c, $balances);
        my (@embedded, @links);
        my $form = $self->get_form($c);
        for my $balance ($balances->all) {
            my $hal = $self->hal_from_balance($c, $balance, $form, $now);
            $hal->_forcearray(1);
            push @embedded, $hal;
            my $link = NGCP::Panel::Utils::DataHalLink->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('/%s%d', $c->request->path, $balance->id),
            );
            $link->_forcearray(1);
            push @links, $link;
        }
        $guard->commit;
        push @links,
            NGCP::Panel::Utils::DataHalLink->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/');
        
        push @links, $self->collection_nav_links($page, $rows, $total_count, $c->request->path, $c->request->query_params);

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





sub item_base {
    my ($self,$c,$id) = @_;
    $c->stash->{contract_id} = $id;
    return undef;
}

sub item_get {
    my ($self,$c,$id) = @_;
    $c->model('DB')->set_transaction_isolation('READ COMMITTED');
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $now = NGCP::Panel::Utils::DateTime::current_local;
        my $contract_id = $c->stash->{contract_id};
        last unless $self->valid_id($c, $contract_id);
        my $contract = $self->contract_by_id($c, $contract_id);
        last unless $self->resource_exists($c, contract => $contract);        
        my $balance = undef;

        if ($self->valid_id($c, $id)) {
            $balance = $self->balance_by_id($c,$contract,$id,$now);
        } else {
            last;
        }
        
        last unless $self->resource_exists($c, balanceinterval => $balance);

        my $form = $self->get_form($c);
        my $hal = $self->hal_from_balance($c,$balance,$form,$now);
        $guard->commit;

        $c->response->headers(HTTP::Headers->new($hal->http_headers));
        $c->response->body($hal->as_json);
        return;
    }
    return;
}

sub item_options {
    my ($self, $c, $id) = @_;
    my $allowed_methods = [ 'GET', 'HEAD', 'OPTIONS' ];
    $c->response->headers(HTTP::Headers->new(
        Allow => join(', ', @{ $allowed_methods }),
        Accept_Patch => 'application/json-patch+json',
    ));
    $c->response->content_type('application/json');
    $c->response->body(JSON::to_json({ methods => $allowed_methods })."\n");
    return;    
}

sub item_head {
    my ($self, $c, $id) = @_;
    $c->forward('item_get');
    $c->response->body(q());
    return;
}



1;
