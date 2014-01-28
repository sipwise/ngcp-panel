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

    my $schema = $c->model('DB');
    my $guard = $schema->txn_scope_guard;
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

        my $customer = $self->get_customer($c, $resource->{contract_id});
        last unless($customer);
        if(defined $customer->max_subscribers && $customer->voip_subscribers->search({ 
                status => { '!=' => 'terminated' }
            })->count >= $customer->max_subscribers) {
            
            $self->error($c, HTTP_FORBIDDEN, "Maximum number of subscribers reached.");
            last;
        }

        my $preferences = {};
        my $admin = 0;
        unless($customer->get_column('product_class') eq 'pbxaccount') {
            delete $resource->{is_pbx_group};
            delete $resource->{pbx_group_id};
            $admin = $resource->{admin} // 0;
        } elsif($c->config->{features}->{cloudpbx}) {
            my $subs = NGCP::Panel::Utils::Subscriber::get_custom_subscriber_struct(
                c => $c,
                contract => $customer,
                show_locked => 1,
            );
            use Data::Printer; say ">>>>>>>>>>>>>>>>>>>> subs"; p $subs;
            my $admin_subscribers = NGCP::Panel::Utils::Subscriber::get_admin_subscribers(
                voip_subscribers => $subs->{subscribers});
            unless(@{ $admin_subscribers }) {
                $admin = $resource->{admin} // 1;
            } else {
                $admin = $resource->{admin} // 0;
            }

            $preferences->{shared_buddylist_visibility} = 1;
            $preferences->{display_name} = $resource->{display_name}
                if(defined $resource->{display_name});

            my $default_sound_set = $customer->voip_sound_sets
                ->search({ contract_default => 1 })->first;
            if($default_sound_set) {
                $preferences->{contract_sound_set} = $default_sound_set->id;
            }

            my $admin_subscriber = $admin_subscribers->[0];
            my $base_number = $admin_subscriber->{primary_number};
            if($base_number) {
                $preferences->{cloud_pbx_base_cli} = $base_number->{cc} . $base_number->{ac} . $base_number->{sn};
            }
        }

        my $billing_profile = $self->get_billing_profile($c, $customer);
        last unless($billing_profile);
        if($billing_profile->prepaid) {
            $preferences->{prepaid} = 1;
        }

        my $subscriber = $c->model('DB')->resultset('voip_subscribers')->find({
            username => $resource->{username},
            domain_id => $resource->{domain_id},
            status => { '!=' => 'terminated' },
        });
        if($subscriber) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Subscriber already exists.");
            last;
        }

        my $alias_numbers = [];
        if(ref $resource->{alias_numbers} eq "ARRAY") {
            foreach my $num(@{ $resource->{alias_numbers} }) {
                unless(ref $num eq "HASH") {
                    $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid parameter 'alias_numbers', must be hash or array of hashes.");
                    last;
                }
                push @{ $alias_numbers }, { e164 => $num };
            }
        } elsif(ref $resource->{alias_numbers} eq "HASH") {
            push @{ $alias_numbers }, { e164 => $resource->{alias_numbers} };
        } else {
            use Data::Printer; p $resource->{alias_numbers}; say ">>>>>>>>>>> '".(ref $resource->{alias_numbers})."'";
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid parameter 'alias_numbers', must be hash or array of hashes.");
            last;
        }

        # TODO: handle pbx subscribers:
            # extension
            # is group
            # default sound set

        # TODO: handle status != active

        try {
            my ($uuid_bin, $uuid_string);
            UUID::generate($uuid_bin);
            UUID::unparse($uuid_bin, $uuid_string);

            $subscriber = NGCP::Panel::Utils::Subscriber::create_subscriber(
                c => $c,
                schema => $schema,
                contract => $customer,
                params => $resource,
                admin_default => $admin,
                preferences => $preferences,
            );

            NGCP::Panel::Utils::Subscriber::update_subscriber_numbers(
                schema         => $c->model('DB'),
                alias_numbers  => $alias_numbers,
                reseller_id    => $customer->contact->reseller_id,
                subscriber_id  => $subscriber->id,
            );
            $subscriber->discard_changes; # reload row because of new number

            # TODO: pbx prefs (group handling, display name, extension etc)

        } catch(DBIx::Class::Exception $e where { /Duplicate entry '([^']+)' for key 'number_idx'/ }) {
            $e =~ /Duplicate entry '([^']+)' for key 'number_idx'/;
            $c->log->error("failed to create subscribere, number $1 already exists"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Number '$1' already exists.");
            last;
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
