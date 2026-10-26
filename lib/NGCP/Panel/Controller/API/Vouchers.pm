package NGCP::Panel::Controller::API::Vouchers;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use MIME::Base64;

use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Voucher;

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines vouchers to top-up subscriber balances. You can POST vouchers individually one-by-one using json. '.
           'To bulk-upload vouchers, specify the Content-Type as "text/csv" and POST the CSV in the request body to the '.
           'collection with an optional parameter "purge_existing=true". '.
           'The CSV has no header row, the columns order is "code,amount,valid_until,customer_id", an admin has to add '.
           'the "reseller_id" as first column. The valid_until is either "YYYY-MM-DD" or "YYYY-MM-DD hh:mm:ss" and '.
           'customer_id can be empty. As admin, purge_existing deletes the vouchers of all the resellers, as reseller only the own ones. '.
           'Lines with less than two columns are skipped. A line which cannot be parsed, an invalid value, a code which '.
           'already exists for the reseller or an unknown reseller, customer or package rejects the whole upload with a 422, '.
           'in which case nothing is imported or purged.';
};

sub query_params {
    return [
        {
            param => 'reseller_id',
            description => 'Filter for vouchers belonging to a specific reseller',
            query => {
                first => sub {
                    my $q = shift;
                    { reseller_id => $q };
                },
                second => sub {},
            },
        },
        {
            param => 'package_id',
            description => 'Filter for vouchers belonging to a specific profile package',
            query => {
                first => sub {
                    my $q = shift;
                    { package_id => $q };
                },
                second => sub {},
            },
        },
        {
            param => 'base64_code',
            description => 'Filter for a voucher with the code, the value is expected as an encoded base64 string',
            new_rs => sub {
                my ($c, $q, $rs) = @_;
                $q .= '=' unless $q =~ /=$/;
                my $code = decode_base64($q);
                my $enc_code = NGCP::Panel::Utils::Voucher::encrypt_code($c, $code);
                return $rs->search_rs({
                    code => $enc_code,
                });
            },
        },
    ],
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::Vouchers/;

sub resource_name{
    return 'vouchers';
}

sub dispatch_path{
    return '/api/vouchers/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-vouchers';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
    required_licenses => [qw/billing/],
});

sub auto :Private {
    my ($self, $c) = @_;

    $self->set_body($c);
    if ($self->get_config('log_request') && !$self->_is_csv_upload($c)) {
        $self->log_request($c);
    }

    return $self->validate_request($c);
}

sub _is_csv_upload {
    my ($self, $c) = @_;
    return index($self->get_content_type($c) // '', 'text/csv') == 0;
}

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $items = $self->item_rs($c);
        #todo - is it really necessary? move to item_rs?
        $items = $items->search_rs({}, {prefetch => ['reseller']});
        (my $total_count, $items, my $items_rows) = $self->paginate_order_collection($c, $items);
        my (@embedded, @links);
        my $form = $self->get_form($c);
        $self->expand_prepare_collection($c);
        for my $item (@$items_rows) {
            push @embedded, $self->hal_from_item($c, $item, $form);
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('/%s%d', $c->request->path, $item->id),
            );
        }
        $self->expand_collection_fields($c, \@embedded);
        push @links,
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            $self->collection_nav_links($c, $page, $rows, $total_count, $c->request->path, $c->request->query_params);

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

sub POST :Allow {
    my ($self, $c) = @_;

    unless($c->user->billing_data) {
        $self->error($c, HTTP_FORBIDDEN, "Insufficient rights to create voucher",
                     "user does not have billing data rights");
        return;
    }

    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $data = $self->get_valid_raw_post_data(
            c => $c,
            media_type => [qw#application/json text/csv#],
        );
        last unless $data;

        if ($self->_is_csv_upload($c)) {
            my $purge_existing = $c->req->query_params->{purge_existing} // '';
            my $text;
            try {
                (undef, undef, $text) = NGCP::Panel::Utils::Voucher::upload_csv(
                    c              => $c,
                    data           => \$data,
                    rs             => $self->_item_rs($c),
                    purge_existing => ($purge_existing eq 'true' || $purge_existing eq '1'),
                );
            } catch(DBIx::Class::Exception $e where { /Duplicate entry .* for key '\S*vouchers_rescode_idx'/ }) {
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY,
                    "Failed to upload vouchers, a voucher code is duplicated or already exists for its reseller", $e);
                last;
            } catch(DBIx::Class::Exception $e where { /foreign key constraint fails/ }) {
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY,
                    "Failed to upload vouchers, unknown reseller_id, customer_id or package_id", $e);
                last;
            } catch(DBIx::Class::Exception $e where { /Incorrect \w+ value|Data truncated|cannot be null|Out of range value/ }) {
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY,
                    "Failed to upload vouchers, invalid voucher data", $e);
                last;
            } catch($e where { ref $_ eq 'ARRAY' }) {
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Failed to upload vouchers, $e->[0]");
                last;
            } catch($e) {
                $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error",
                             "failed to upload csv", $e);
                last;
            };

            $c->log->info($$text);

            $guard->commit;

            $c->response->status(HTTP_CREATED);
            $c->response->body(q());
            last;
        }

        last unless $self->require_wellformed_json($c, 'application/json', $data);
        my $resource = JSON::from_json($data, { utf8 => 1 });

        my $form = $self->get_form($c);
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
        );
        if($c->user->roles eq "admin") {
        } elsif($c->user->roles eq "reseller") {
            $resource->{reseller_id} = $c->user->reseller_id;
        }

        my $item;
        my $code = NGCP::Panel::Utils::Voucher::encrypt_code($c, $resource->{code});
        $item = $c->model('DB')->resultset('vouchers')->find({
            reseller_id => $resource->{reseller_id},
            code => $code,
        });
        if($item) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Voucher with this code already exists for this reseller",
                         "voucher with code '$$resource{code}' already exists for reseller_id '$$resource{reseller_id}'");
            last;
        }
        $resource->{code} = $code;
        $resource->{created_at} = NGCP::Panel::Utils::DateTime::current_local;


        try {
            $item = $c->model('DB')->resultset('vouchers')->create($resource);
        } catch($e) {
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create voucher.", $e);
            last;
        }

        $guard->commit;

        $c->response->status(HTTP_CREATED);
        $c->response->header(Location => sprintf('/%s%d', $c->request->path, $item->id));
        $c->response->body(q());
    }
    return;
}

1;

# vim: set tabstop=4 expandtab:
