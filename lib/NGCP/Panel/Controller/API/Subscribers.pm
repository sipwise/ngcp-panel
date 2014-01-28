package NGCP::Panel::Controller::API::Subscribers;
use Sipwise::Base;
use namespace::sweep;
use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use MooseX::ClassAttribute qw(class_has);
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Subscriber;
use NGCP::Panel::Utils::Preferences;
use Path::Tiny qw(path);
use Safe::Isa qw($_isa);
use UUID;
BEGIN { extends 'Catalyst::Controller::ActionRole'; }
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require Catalyst::ActionRole::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

with 'NGCP::Panel::Role::API';
with 'NGCP::Panel::Role::API::Subscribers';

class_has('resource_name', is => 'ro', default => 'subscribers');
class_has('dispatch_path', is => 'ro', default => '/api/subscribers/');
class_has('relation', is => 'ro', default => 'http://purl.org/sipwise/ngcp-api/#rel-subscribers');

__PACKAGE__->config(
    action => {
        map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => 'admin',
            Args => 0,
            Does => [qw(ACL CheckTrailingSlash RequireSSL)],
            Method => $_,
            Path => __PACKAGE__->dispatch_path,
        } } @{ __PACKAGE__->allowed_methods }
    },
    action_roles => [qw(HTTPMethods)],
);

sub auto :Private {
    my ($self, $c) = @_;

    $self->set_body($c);
    $self->log_request($c);
}

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $subscribers = $self->item_rs($c);
        my $total_count = int($subscribers->count);
        $subscribers = $subscribers->search(undef, {
            page => $page,
            rows => $rows,
        });
        my (@embedded, @links);
        my $form = $self->get_form($c);
        for my $subscriber ($subscribers->search({}, {order_by => {-asc => 'me.id'}})->all) {
            push @embedded, $self->hal_from_item($c, $subscriber, $form);
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('%s%d', $self->dispatch_path, $subscriber->id),
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
            push @links, Data::HAL::Link->new(relation => 'prev', href => sprintf('/%s?page=%d&rows=%d', $c->request->path, $page - 1, $rows));
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
        my $resource = $self->get_valid_post_data(
            c => $c, 
            media_type => 'application/json',
        );
        last unless $resource;

        my $domain;
        if($resource->{domain}) {
            $domain = $c->model('DB')->resultset('domains')
                ->search({ domain => $resource->{domain} });
            if($c->user->roles eq "admin") {
            } elsif($c->user->roles eq "reseller") {
                $domain = $domain->search({ 
                    'domain_resellers.reseller_id' => $c->user->reseller_id,
                }, {
                    join => 'domain_resellers',
                });
            }
            $domain = $domain->first;
            unless($domain) {
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'domain', doesn't exist.");
                last;
            }
            delete $resource->{domain};
            $resource->{domain_id} = $domain->id;
        }

        $resource->{e164} = delete $resource->{primary_number};
        $resource->{contract_id} = delete $resource->{customer_id};
        $resource->{status} //= 'active';
        $resource->{administrative} //= 0;

        my $form = $self->get_form($c);
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
        );

        unless($domain) {
            $domain = $c->model('DB')->resultset('domains')->search($resource->{domain_id});
            if($c->user->roles eq "admin") {
            } elsif($c->user->roles eq "reseller") {
                $domain = $domain->search({ 
                    'domain_resellers.reseller_id' => $c->user->reseller_id,
                }, {
                    join => 'domain_resellers',
                });
            }
            $domain = $domain->first;
            unless($domain) {
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'domain', doesn't exist.");
                last;
            }
        }


        my $customer = NGCP::Panel::Utils::Contract::get_contract_rs(
            schema => $c->model('DB'),
        );
        $customer = $customer->search({
                'contact.reseller_id' => { '-not' => undef },
                'me.id' => $resource->{contract_id},
            },{
                join => 'contact'
            });
        $customer = $customer->search({
                '-or' => [
                    'product.class' => 'sipaccount',
                    'product.class' => 'pbxaccount',
                ],
            },{
                join => {'billing_mappings' => 'product' },
                '+select' => 'billing_mappings.id',
                '+as' => 'bmid',
            }); 
        if($c->user->roles eq "admin") {
        } elsif($c->user->roles eq "reseller") {
            $customer = $customer->search({
                'contact.reseller_id' => $c->user->reseller_id,
            });
        }
        $customer = $customer->first;
        unless($customer) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'customer_id', doesn't exist.");
            last;
        }
        if(defined $customer->max_subscribers && $customer->voip_subscribers->search({ 
                status => { '!=' => 'terminated' }
            })->count >= $customer->max_subscribers) {
            
            $self->error($c, HTTP_FORBIDDEN, "Maximum number of subscribers reached.");
            last;
        }

        # TODO: check if number is already taken

        # TODO: handle pbx subscribers:
            # extension
            # is group
            # default sound set

        # TODO: handle status != active

        my $subscriber;
        try {
            my ($uuid_bin, $uuid_string);
            UUID::generate($uuid_bin);
            UUID::unparse($uuid_bin, $uuid_string);

            my $rs = $self->item_rs($c);
            $subscriber = $rs->create({
                contract_id => $customer->id,
                uuid => $uuid_string,
                username => $resource->{username},
                domain_id => $domain->id,
                status => $resource->{status},
            });
            my $prov_subscriber = $c->model('DB')->resultset('provisioning_voip_subscribers')->create({
                uuid => $uuid_string,
                username => $resource->{username},
                password => $resource->{password},
                webusername => $resource->{webusername},
                webpassword => $resource->{webpassword},
                admin => $resource->{administrative},
                account_id => $customer->id,
                domain_id => $domain->provisioning_voip_domain->id,
                create_timestamp => NGCP::Panel::Utils::DateTime::current_local,
            });

            NGCP::Panel::Utils::Subscriber::update_subscriber_numbers(
                schema         => $c->model('DB'),
                primary_number => $resource->{e164},
                reseller_id    => $customer->contact->reseller_id,
                subscriber_id  => $subscriber->id,
            );
            $subscriber->discard_changes; # reload row because of new number

            my $voip_preferences = $c->model('DB')->resultset('voip_preferences')->search({
                'usr_pref' => 1,
            });
            $voip_preferences->find({ 'attribute' => 'account_id' })
                ->voip_usr_preferences->create({
                    'subscriber_id' => $prov_subscriber->id,
                    'value' => $customer->id,
                });
            my $cli;
            if($subscriber->primary_number) {
                $voip_preferences->find({ 'attribute' => 'ac' })
                    ->voip_usr_preferences->create({
                        'subscriber_id' => $prov_subscriber->id,
                        'value' => $subscriber->primary_number->ac,
                    });
                $voip_preferences->find({ 'attribute' => 'cc' })
                    ->voip_usr_preferences->create({
                        'subscriber_id' => $prov_subscriber->id,
                        'value' => $subscriber->primary_number->cc,
                    });
                $cli =  $subscriber->primary_number->cc .
                        ($subscriber->primary_number->ac // '').
                        $subscriber->primary_number->sn;
                $voip_preferences->find({ 'attribute' => 'cli' })
                    ->voip_usr_preferences->create({
                        'subscriber_id' => $prov_subscriber->id,
                        'value' => $cli,
                    });
            }

            $c->model('DB')->resultset('voicemail_users')->create({
                customer_id => $uuid_string,
                mailbox => ($cli // 0),
                password => sprintf("%04d", int(rand 10000)),
                email => '',
            });

            # TODO: pbx prefs (group handling, display name, extension etc)

        } catch($e) {
            $c->log->error("failed to create subscriber: $e"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create subscriber.");
            last;
        }


        $guard->commit;

        $c->response->status(HTTP_CREATED);
        $c->response->header(Location => sprintf('%s%d', $self->dispatch_path, $subscriber->id));
        $c->response->body(q());
    }
    return;
}

sub end : Private {
    my ($self, $c) = @_;

    $self->log_response($c);
}

# vim: set tabstop=4 expandtab:
