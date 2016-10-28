package NGCP::Panel::Controller::API::SMS;

use Sipwise::Base;
use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::SMS/;

use HTTP::Status qw(:constants);


__PACKAGE__->set_config();

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Shows a journal of sent and received messages. New messages can be sent by issuing a POST request to the api collection.';
}

# sub query_params {
#     return [
#     ];
# }

sub create_item {
    my ($self, $c, $resource, $form, $process_extras) = @_;

    my $error_msg = "";

    NGCP::Panel::Utils::SMS::send_sms(
            c => $c,
            caller => $resource->{caller},
            callee => $resource->{callee},
            text => $resource->{text},
            err_code => sub {$error_msg = shift;},
        );

    my $rs = $self->item_rs($c);
    my $item = $rs->create({
            subscriber_id => $resource->{subscriber_id},
            direction => 'out',
            caller => $resource->{caller},
            callee => $resource->{callee},
            text => $resource->{text},
            $error_msg ? (status => $error_msg) : (),
        });
    return $item;
}

sub auto :Private {
    my ($self, $c) = @_;

    $self->set_body($c);
    $self->log_request($c);
    return 1;
}



sub end : Private {
    my ($self, $c) = @_;

    $self->log_response($c);
    return 1;
}

1;

# vim: set tabstop=4 expandtab:
