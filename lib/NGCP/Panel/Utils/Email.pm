package NGCP::Panel::Utils::Email;

use Sipwise::Base;
use Template;

sub send_template {
    my ($c, $vars, $subject, $body, $from, $to) = @_;
    my $t = Template->new;

    my $processed_body = "";
    $t->process(\$body, $vars, \$processed_body) || 
        die "error processing email template body, type=".$t->error->type.", info='".$t->error->info."'";

    my $processed_subject = "";
    $t->process(\$subject, $vars, \$processed_subject) || 
        die "error processing email template, type=".$t->error->type.", info='".$t->error->info."'";

    $c->email(
        header => [
            From => $from,
            To => $to,
            Subject => $processed_subject,
        ],
        body => $processed_body,
    );
    #my $template_processed = process_template({
    #    subject => $subject,
    #    body => $body,
    #    from_email => $from,
    #    to => $to,
    #},$vars);
    #
    #$c->email(
    #    header => [
    #        From => $template_processed->{from_email},
    #        To => $template_processed->{to},
    #        Subject => $template_processed->{subject},
    #    ],
    #    body => $template_processed->{body},
    #);

    return 1;
}

sub new_subscriber {
    my ($c, $subscriber, $url) = @_;

    my $template = $subscriber->contract->subscriber_email_template;
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
1;

# vim: set tabstop=4 expandtab:
