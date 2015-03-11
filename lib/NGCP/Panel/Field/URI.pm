package NGCP::Panel::Field::URI;

use Sipwise::Base;
use HTML::FormHandler::Moose;
use parent 'HTML::FormHandler::Field::Text';
use NGCP::Panel::Utils::Subscriber;

our $class_messages = {
    'uri_format' => 'URI must be in format "username", "username@domain" or phone number',
};

sub get_class_messages  {
    my $self = shift;
    return {
        %{ $self->next::method },
        %$class_messages,
    }
}

apply(
    [
        {
            transform => sub { 
	    	    lc($_[0]);
		    }
        },
        {
            transform => sub {
                my ($v, $field) = @_;
                my $c = $field->form->ctx;
                return $v unless($c);

                my $sub = $c->stash->{subscriber};
                return $v unless($sub);

                $v =~ s/^sips?://;
                my ($user, $domain) = split(/\@/, $v);
                $domain = $sub->domain->domain unless($domain);
                my $uri;

                if($c->user->roles eq "subscriberadmin" || $c->user->roles eq "subscriber") {
                    $user = NGCP::Panel::Utils::Subscriber::apply_rewrite(
                        c => $c, subscriber => $sub, number => $user, direction => 'callee_in'
                    );
                }
                $uri = 'sip:' . $user . '@' . $domain;

                return $uri;
		    }
        },
        {
            check => sub {
                my ( $value, $field ) = @_;
                my ($user, $domain) = split(/\@/, $value);
                my $checked = $value if $user && $domain; # TODO: proper check
                $field->value($checked)
                    if $checked;
            },
            message => sub {
                my ( $value, $field ) = @_;
                return $field->get_message('uri_format');
            },
        }
    ]
);

has '+deflate_method'  => ( default => sub { \&uri_deflate } );

sub uri_deflate {
    my ( $field, $v ) = @_;
    return unless($v);
    my $c = $field->form->ctx;
    return $v unless($c);

    my $sub = $c->stash->{subscriber};
    return $v unless($sub);

    $v =~ s/^sips?://;
    my $t;
    my ($user, $domain) = split(/\@/, $v);
    if($c->user->roles eq "subscriberadmin" || $c->user->roles eq "subscriber") {
        $user = NGCP::Panel::Utils::Subscriber::apply_rewrite(
            c => $c, subscriber => $sub, number => $user, direction => 'caller_out'
        );
    }
    if($domain eq $sub->domain->domain) {
        $v = $user;
    } else {
        $v = $user . '@' . $domain;
    }
    return $v;    
}

1;
__PACKAGE__->meta->make_immutable;
use namespace::autoclean

# vim: set tabstop=4 expandtab:
