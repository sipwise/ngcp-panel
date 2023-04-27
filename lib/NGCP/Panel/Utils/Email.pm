package NGCP::Panel::Utils::Email;

use Sipwise::Base;
use Template;
use Email::Sender::Simple qw();
use Email::Simple;
use Email::Simple::Creator;
use Email::Sender::Transport::Sendmail qw();

sub send_email {
    my %args = @_;
    my $subject = $args{subject};
    my $body = $args{body};
    my $from = $args{from};
    my $to = $args{to};

    my $transport = Email::Sender::Transport::Sendmail->new;
    my $email = Email::Simple->create(
        header => [
            To      => $to,
            From    => $from,
            Subject => $subject,
        ],
        body => $body,
    );
    try {
        Email::Sender::Simple->send($email, { transport => $transport });
    } catch($e) {
        return $e->message;
    }
    return;
}

sub send_template {
    my ($c, $vars, $subject, $body, $from, $to) = @_;
    my $t = Template->new;

    $c->log->info("Trying to send mail from '" . $c->qs($from) . "' to '" . $c->qs($to) . "'");

    my $processed_body = "";
    $t->process(\$body, $vars, \$processed_body) || 
        die "error processing email template body, type=".$t->error->type.", info='".$t->error->info."'";

    my $processed_subject = "";
    $t->process(\$subject, $vars, \$processed_subject) || 
        die "error processing email template, type=".$t->error->type.", info='".$t->error->info."'";

    my $err = send_email(
        subject => $processed_subject,
        body => $processed_body,
        from => $from,
        to => $to,
    );

    #my $template_processed = process_template({
    #    subject => $subject,
    #    body => $body,
    #    from_email => $from,
    #    to => $to,
    #},$vars);
    #
    #send_email(
    #    subject => $template_processed->{subject},
    #    body => $template_processed->{body},
    #    from => $template_processed->{from_email},
    #    to => $template_processed->{to},
    #);

    $err ? $c->log->info("Could not send email from '" . $c->qs($from) . "' to '" . $c->qs($to) . "' error=$err")
         : $c->log->error("Successfully handed over mail from '" . $c->qs($from) . "' to '" . $c->qs($to) . "'");

    return 1;
}

sub new_subscriber {
    my ($c, $subscriber, $url, $params) = @_;

    my $template = $subscriber->contract->subscriber_email_template;
    return unless($template);
    my $email = $subscriber->contact ? 
        $subscriber->contact->email : $subscriber->contract->contact->email;

    my $vars = {
        url => $url,
        subscriber => $subscriber->username . '@' . $subscriber->domain->domain,
        
        username => $params->{username},
        password => $params->{password},
        
        webusername => $params->{webusername},
        webpassword => $params->{webpassword},
        
        cc => $params->{e164}->{cc},
        ac => $params->{e164}->{ac},
        sn => $params->{e164}->{sn},
    };

    my $body = $template->body;
    my $subject = $template->subject;

    return send_template($c, $vars, $subject, $body, $template->from_email, $email);
}

sub password_reset {
    my ($c, $subscriber, $url) = @_;

    my $template = $subscriber->contract->passreset_email_template;
    return unless($template);
    my $email = $subscriber->contact ? 
        $subscriber->contact->email : $subscriber->contract->contact->email;

    my $vars = {
        url => $url,
        subscriber => $subscriber->username . '@' . $subscriber->domain->domain,
    };

    my $body = $template->body;
    my $subject = $template->subject;

    return send_template($c, $vars, $subject, $body, $template->from_email, $email);
}

sub admin_password_reset {
    my ($c, $admin, $url) = @_;

    my $template = $admin->reseller->email_templates->search({name => 'admin_passreset_default_email'})->first;
    return unless($template);
    my $email = $admin->email;

    my $vars = {
        url => $url,
        admin => $admin->login,
    };

    my $body = $template->body;
    my $subject = $template->subject;

    return send_template($c, $vars, $subject, $body, $template->from_email, $email);
}

sub process_template{
    my ($c, $tmpl, $vars) = @_;
    my $t = Template->new;
    my $tmpl_processed;
    foreach(qw/body subject from_email to/){
        $tmpl_processed->{$_} = "";
        if($tmpl->{$_}){
            $t->process(\$tmpl->{$_}, $vars, \$tmpl_processed->{$_}) 
                || die "error processing email template $_, type=".$t->error->type.", info='".$t->error->info."'";
        }
    }
    return $tmpl_processed;
}
#just to make all processgin variants through one sub
#sub process_template_object{
#    my ($c, $tmpl, $vars,  $tmpl_hash) = @_;
#    $tmpl_hash //= {};
#    foreach(qw/body subject from_email/){
#        $tmpl_hash->{$_} = $tmpl->get_column($_);
#    }
#    return process_template($c, $tmpl_hash, $vars);
#}

sub rewrite_url {
    my ($format,$url) = @_;
    if (length($url) and length($format)) {
        if ($url =~ /^(https?):\/\/([^\/]+)(\/.+)?$/i) {
            my $scheme = $1;
            my $domain = $2;
            my $base_path = $3;
            $base_path =~ s/^\/// if length($base_path);
            my $port;
            if ($domain =~ /^([^@]*@)?([^:]+)(:\d+)?$/) {
                $domain = $2;
                $port = $3;
                $port =~ s/^:// if length($port);
            }
            $url = sprintf($format,$scheme,$domain,$port,$base_path);
        }
    }
    return $url;
}

1;

# vim: set tabstop=4 expandtab:
