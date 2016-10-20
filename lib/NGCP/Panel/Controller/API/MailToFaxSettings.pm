package NGCP::Panel::Controller::API::MailToFaxSettings;
use NGCP::Panel::Utils::Generic qw(:all);

use strict;
use warnings;

use TryCatch;


use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::DateTime;
use Path::Tiny qw(path);
use Safe::Isa qw($_isa);
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;
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



sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $cfs = $self->item_rs($c);
        (my $total_count, $cfs) = $self->paginate_order_collection($c, $cfs);
        my (@embedded, @links);
        for my $cf ($cfs->all) {
            try {
                push @embedded, $self->hal_from_item($c, $cf);
                push @links, NGCP::Panel::Utils::DataHalLink->new(
                    relation => 'ngcp:'.$self->resource_name,
                    href     => sprintf('%s%s', $self->dispatch_path, $cf->id),
                );
            }
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







1;

# vim: set tabstop=4 expandtab:
