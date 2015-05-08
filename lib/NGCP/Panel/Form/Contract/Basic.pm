package NGCP::Panel::Form::Contract::Basic;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Contract::Base';

has_field 'billing_profiles.network' => (
    type => '+NGCP::Panel::Field::BillingNetwork',
    #validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The billing network id this profile is restricted to.']
    },
);

sub update_fields {
    my $self = shift;
    my $c = $self->ctx;
    return unless $c;

    foreach my $field(qw/subscriber_email_template passreset_email_template invoice_email_template/) {
        my $email = $self->field($field);
        if($email && $c->stash->{contract}) {
            $email->field('id')->ajax_src(
                $c->uri_for_action('/emailtemplate/tmpl_ajax_reseller', [$c->stash->{contract}->contact->reseller_id])->as_string
            );
        }
    }
}

1;
# vim: set tabstop=4 expandtab: