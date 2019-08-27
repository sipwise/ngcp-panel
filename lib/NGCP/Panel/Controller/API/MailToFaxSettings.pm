package NGCP::Panel::Controller::API::MailToFaxSettings;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;


use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

sub api_description {
    return 'Specifies mail to fax settings for a specific subscriber.';
}

sub query_params {
    return [
        {
            param => 'active',
            description => 'Filter for items (subscribers) with active mail to fax settings',
            query => {
                first => sub {
                    my $q = shift;
                    if ($q) {
                        { 'voip_mail_to_fax_preference.active' => 1 };
                    } else {
                        {};
                    }
                },
                second => sub {
                    { prefetch => { 'provisioning_voip_subscriber' => 'voip_mail_to_fax_preference' } };
                },
            },
        },
        {
            param => 'secret_key_renew',
            description => 'Filter for items (subscribers) where secret_key_renew field matches given pattern',
            query => {
                first => sub {
                    my $q = shift;
                    if ($q) {
                        { 'voip_mail_to_fax_preference.secret_key_renew' => $q };
                    } else {
                        {};
                    }
                },
                second => sub {
                    return { prefetch => { 'provisioning_voip_subscriber' => 'voip_mail_to_fax_preference' } };
                },
            },
        },
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::MailToFaxSettings/;

sub resource_name{
    return 'mailtofaxsettings';
}

sub dispatch_path{
    return '/api/mailtofaxsettings/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-mailtofaxsettings';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller ccareadmin ccare/],
});

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $cfs = $self->item_rs($c);
        (my $total_count, $cfs, my $cfs_rows) = $self->paginate_order_collection($c, $cfs);
        my (@embedded, @links);
        for my $cf (@$cfs_rows) {
            try {
                push @embedded, $self->hal_from_item($c, $cf);
                push @links, Data::HAL::Link->new(
                    relation => 'ngcp:'.$self->resource_name,
                    href     => sprintf('%s%s', $self->dispatch_path, $cf->id),
                );
            }
        }
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

1;

# vim: set tabstop=4 expandtab:
