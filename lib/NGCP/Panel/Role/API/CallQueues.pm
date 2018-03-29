package NGCP::Panel::Role::API::CallQueues;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();

my $redis_key_prefix = 'callqueue:';
my $number_search_limit = 100; # scan redis only if collection gets bigger than this

sub _get_redis {
    my ($self, $c, $select) = @_;
    my $redis = $c->stash->{redis};
    unless ($redis) {
        try {
            $redis = Redis->new(
                server => $c->config->{redis}->{central_url},
                reconnect => 10, every => 500000, # 500ms
                cnx_timeout => 3,
            );
            unless ($redis) {
                $c->log->error("Failed to connect to central redis url " . $c->config->{redis}->{central_url});
                return;
            }
            $redis->select($select);
            $c->stash(redis => $redis);
        } catch($e) {
            $c->log->error("Failed to fetch callqueue information from redis: $e");
            return;
        }
    }
    return $redis;
}

sub _item_rs {
    my ($self, $c, $id) = @_;

    my $redis = $self->_get_redis($c,$c->config->{redis}->{callqueue_db});

    my $rs = $c->model('DB')->resultset('voip_subscribers');
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $rs = $rs->search_rs({
            'contact.reseller_id' => $c->user->reseller_id,
        },{
            join => { 'contract' => 'contact' }
        });
    } elsif ($c->user->roles eq "subscriberadmin") {
        $rs = $rs->search_rs({
            'me.contract_id' => $c->user->account_id,
        });
    } elsif ($c->user->roles eq "subscriber") {
        $rs = $rs->search_rs({
            'me.uuid' => $c->user->uuid,
        });
    }

    if ($id) {
        my $subs = $rs->find($id);
        if ($subs) {
            $rs = $rs->search_rs({
                'me.uuid' => ($redis->exists($redis_key_prefix . $subs->uuid) ? $subs->uuid : -1),
            });
        }
    } else {
        my $callqueue_uuids = $c->stash->{callqueue_uuids};
        if ($c->req->params->{number}) {
            $rs = $rs->search_rs({
                'voip_dbaliases.username' => { like => $c->req->params->{number} },
            },{
                join => { 'provisioning_voip_subscriber' => 'voip_dbaliases' },
                distinct => 1,
            });
            if (not $callqueue_uuids and $rs->search_rs(undef,{ rows => $number_search_limit, })->count < $number_search_limit) {
                my @callqueue_uuids = ( -1 );
                for my $subs ($rs->all) {
                    push(@callqueue_uuids,$subs->uuid) if $redis->exists($redis_key_prefix . $subs->uuid);
                }
                $c->stash(callqueue_uuids => \@callqueue_uuids);
            }
        }
        unless ($callqueue_uuids) {
            my @callqueue_uuids = ( -1 );
            my $cursor = 0;
            do {
                my $res = $redis->scan($cursor, MATCH => $redis_key_prefix . '*', COUNT => 1000);
                $cursor = shift @$res;
                my $mapkeys = shift @$res;
                foreach my $mapkey (@$mapkeys) {
                    push(@callqueue_uuids,$mapkey =~ s/^callqueue://r);
                }
            } while ($cursor);
            $c->stash(callqueue_uuids => \@callqueue_uuids);
        }
        $rs = $rs->search_rs({
            'me.uuid' => { -in => $callqueue_uuids },
        });
    }

    return $rs;
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::get("NGCP::Panel::Form::CallQueue::API", $c);
}

sub hal_from_item {
    my ($self, $c, $item, $form) = @_;

    my $hal = Data::HAL->new(
        links => [
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'collection', href => sprintf("/api/%s/", $self->resource_name)),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            Data::HAL::Link->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $item->id)),
            Data::HAL::Link->new(relation => 'ngcp:subscribers', href => sprintf("/api/subscribers/%d", $item->id)),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    my $resource = $self->resource_from_item($c, $item, $form);
    $hal->resource($resource);
    return $hal;
}

sub resource_from_item {
    my ($self, $c, $item, $form) = @_;

    my %resource = ();
    $resource{id} = int($item->id);
    $resource{status} = $item->status;
    $resource{callid} = $item->call_id;



    return \%resource;
}

sub item_by_id {
    my ($self, $c, $id) = @_;
    my $item_rs = $self->item_rs($c,$id);
    return $item_rs->find($id);
}

1;
# vim: set tabstop=4 expandtab:
