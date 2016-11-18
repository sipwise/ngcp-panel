package NGCP::Panel::Controller::InternalSms;
use NGCP::Panel::Utils::Generic qw(:all);
use Sipwise::Base;


use parent 'Catalyst::Controller';

#sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) {
sub auto {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    #NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub list :Chained('/') :PathPart('internalsms') :CaptureArgs(0) {
    # my ($self, $c) = @_;
    return;
}

sub receive :Chained('list') :PathPart('receive') :Args(0) {
    my ($self, $c) = @_;

    my $from = $c->req->params->{from} // "";
    my $to = $c->req->params->{to} // "";
    my $text = $c->req->params->{text} // "";
    my $token = $c->req->params->{auth_token} // "";

    unless ($from && $to && $text && $token) {
        $c->log->error("Missing one param of: from ($from), to ($to), text ($text), auth_token ($token).");
        $c->detach('/denied_page');
    }

    unless ($c->config->{sms}{api_token} && $c->config->{sms}{api_token} eq $token) {
        $c->log->error("Token mismatch (sent: $token).");
        $c->detach('/denied_page');
    }

    $to =~ s/^\+//;
    $from =~ s/^\+//;

    try {
        my $schema = $c->model('DB');
        $schema->txn_do(sub {
            my $prov_dbalias = $c->model('DB')->resultset('voip_dbaliases')
                ->search_rs({
                        'me.username' => $to,
                    },{
                        join => { subscriber => 'voip_subscriber' }
                    })->first;

            unless ($prov_dbalias) {
                $c->log->warn("No corresponding subscriber for incoming number ($to) found.");
                $c->log->debug("from: $from, to: $to, text: $text");
                die "no_subscriber_found";
            }

            my $created_item = $c->model('DB')->resultset('sms_journal')->create({
                subscriber_id => $prov_dbalias->subscriber_id,
                direction => "in",
                caller => $from,
                callee => $to,
                text => $text,
                });
        });
    } catch($e) {
        $c->log->error("Failed to store received SMS message.");
        $c->log->debug($e);
    }

    $c->response->code(200);
    $c->response->body("");
    return;
}

__PACKAGE__->meta->make_immutable;

1;

# vim: set tabstop=4 expandtab:
