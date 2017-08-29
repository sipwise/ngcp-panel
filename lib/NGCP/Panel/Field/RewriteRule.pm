package NGCP::Panel::Field::RewriteRule;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Compound';

has_field 'match_pattern' => (
    type => '+NGCP::Panel::Field::Regexp',
    required => 1,
    inflate_default_method => \&inflate_match_pattern,
    deflate_value_method => \&deflate_match_pattern,
    element_attr => {
        rel => ['tooltip'],
        title => ['Match pattern, a regular expression.'],
    },
);

has_field 'replace_pattern' => (
    type => 'Text',
    required => 1,
    label => 'Replacement Pattern',
    inflate_default_method => \&inflate_replace_pattern,
    deflate_value_method => \&deflate_replace_pattern,
    element_attr => {
        rel => ['tooltip'],
        title => ['Replacement pattern.'],
    },
);

has_field 'description' => (
    type => 'Text',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Arbitrary text.'],
    },
);

has_field 'direction' => (
    type => 'Select',
    options => [
        { label => 'Inbound', value => 'in'},
        { label => 'Outbound', value => 'out'},
        { label => 'LNP', value => 'lnp'},
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['Inbound (in), Outbound (out) or LNP (lnp).']
    },
);

has_field 'enabled' => (
    type => 'Boolean',
    label => 'Enabled',
    default => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Rule enabled state.'],
    },
);

has_field 'field' => (
    type => 'Select',
    options => [
        { label => 'Callee', value => 'callee'},
        { label => 'Caller', value => 'caller'},
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['caller or callee.']
    },
);

sub deflate_match_pattern {
    my ($self, $value) = @_;

    $value =~ s/\$\{(\w+)\}/\$avp(s:$1)/g;
    $value =~ s/\@\{(\w+)\}/\$(avp(s:$1)[+])/g;
    return $value;
};

sub inflate_match_pattern {
    my ($self, $value) = @_;
    
    $value =~ s/\$avp\(s\:(\w+)\)/\${$1}/g;
    $value =~ s/\$\(avp\(s\:(\w+)\)\[\+\]\)/\@{$1}/g;
    return $value;
}

sub deflate_replace_pattern {
    my ($self, $value) = @_;

    $value =~ s/\$\{(\w+)\}/\$avp(s:$1)/g;
    return $value;
};

sub inflate_replace_pattern {
    my ($self, $value) = @_;
    
    $value =~ s/\$avp\(s\:(\w+)\)/\${$1}/g;
    return $value;
}

1;

# vim: set tabstop=4 expandtab:
