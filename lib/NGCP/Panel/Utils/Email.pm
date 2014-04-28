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

1;

# vim: set tabstop=4 expandtab:
