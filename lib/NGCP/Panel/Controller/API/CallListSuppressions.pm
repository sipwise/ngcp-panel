package NGCP::Panel::Controller::API::CallListSuppressions;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::CallListSuppressions/;

__PACKAGE__->set_config({
    allowed_roles => [qw/admin/],
});

sub allowed_methods {
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines global call list suppressions, which hide or obfuscate matching numbers in the <a href="#calllists">Call Lists</a> of subscriber and subscriber admin users. '.
           'A suppression applies to the subscribers of the given "domain", or to the subscribers of any domain if "domain" is empty. '.
           'In "filter" mode matching calls do not appear at all, in "obfuscate" mode the number is replaced by the given "label", and in "disabled" mode the suppression is not applied. '.
           'Admin and reseller users always see the unsuppressed call lists. The combination of "domain", "direction" and "pattern" must be unique.';
}

sub order_by_cols {
    return {
        id => 'me.id',
        domain => 'me.domain',
        direction => 'me.direction',
        pattern => 'me.pattern',
        mode => 'me.mode',
        label => 'me.label',
    };
}

sub query_params {
    return [
        {
            param => 'domain',
            description => 'Filter for call list suppressions of a specific domain. Use an empty value to filter for the suppressions applying to any domain.',
            query_type => 'string_eq',
        },
        {
            param => 'direction',
            description => 'Filter for call list suppressions with a specific direction ("outgoing" or "incoming")',
            query_type => 'string_eq',
        },
        {
            param => 'mode',
            description => 'Filter for call list suppressions with a specific mode ("filter", "obfuscate" or "disabled")',
            query_type => 'string_eq',
        },
        {
            param => 'pattern',
            description => 'Filter for call list suppressions with a specific pattern',
            query_type => 'wildcard',
        },
        {
            param => 'label',
            description => 'Filter for call list suppressions with a specific label',
            query_type => 'wildcard',
        },
    ];
}

1;

# vim: set tabstop=4 expandtab:
