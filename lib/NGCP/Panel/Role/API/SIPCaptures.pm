package NGCP::Panel::Role::API::SIPCaptures;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);

sub resource_name {
    return 'sipcaptures';
}

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('Storage')->resultset('messages');

    if ($c->user->roles eq "admin") {
    } elsif ($c->user->roles eq "reseller" ||
             $c->user->roles eq "subsriberadmin") {
        #TODO: possibly store reseller_id inside sipstats.messages
        # as such logic becomes quite expensive on large amount of subscribers
        # per reseller
        my $sub_rs;
        if ($c->user->roles eq "reseller") {
            $sub_rs = $c->model('DB')->resultset('voip_subscribers')->search({
                'contact.reseller_id' => $c->user->reseller_id
            },{
                join => { contract => 'contact' }
            });
        } else {
            $sub_rs = $c->model('DB')->resultset('voip_subscribers')->search({
                'contract.id' => $c->user->account_id,
            },{
                join => 'contract'
            });
        }
        my @uuids = map { $_->uuid } $sub_rs->all;
        $item_rs = $item_rs->search({
            -or => [
                    'me.caller_uuid' => { -in => \@uuids },
                    'me.callee_uuid' => { -in => \@uuids },
                   ],
        });
    } elsif ($c->user->roles eq "subscriber") {
        $item_rs = $item_rs->search_rs({
            -or => [
                    'me.caller_uuid' => $c->user->uuid,
                    'me.callee_uuid' => $c->user->uuid,
                   ],
        });
    }

    return $item_rs;
}

sub packets_by_callid {
    my ($self, $c, $id) = @_;
    my $item_rs = $c->model('Storage')->resultset('packets')->search({
		'message.call_id' => $id
	},{
		join => { message_packets => 'message' }
	});
    return $item_rs->first ? [$item_rs->all] : undef;
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::get("NGCP::Panel::Form::SIPCaptures", $c);
}

#
sub resource_from_item {
    my ($self, $c, $item, $form) = @_;

    my %resource = $item->get_inflated_columns;

    my $datetime_fmt = DateTime::Format::Strptime->new(
        pattern => '%F %T',
    );
    my $tz = $c->req->param('tz');
    unless($tz && DateTime::TimeZone->is_valid_name($tz)) {
        $tz = undef;
    }
    if($item->timestamp) {
        if($tz) {
            $item->timestamp->set_time_zone($tz);
        }
        $resource{timestamp} = $datetime_fmt->format_datetime($item->timestamp);
		if ($item->timestamp->millisecond > 0.0) {
			$resource{timestamp} .= '.'.$item->timestamp->millisecond;
		}
    }

	$resource{request_uri} = $item->request_uri;

    return \%resource;
}

sub get_item_id {
   my ($self, $c, $item, $resource, $form) = @_;
   return $item->call_id;
}

1;
# vim: set tabstop=4 expandtab:
