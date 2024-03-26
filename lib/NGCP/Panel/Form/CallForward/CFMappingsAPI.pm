package NGCP::Panel::Form::CallForward::CFMappingsAPI;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

has_field 'id' => (
    type => 'Hidden',
    noupdate => 1,
);

has_field 'cfu' => (
    type => 'Repeatable',
    do_wrapper => 1,
    do_label => 0,
    required => 0,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['Call Forward Unconditional, Number of Objects, each containing the keys ' .
                  '"destinationset", "timeset" and "sourceset". The values must be the name of ' .
                  'a corresponding set which belongs to the same subscriber.'],
    },
);

has_field 'cfb' => (
    type => 'Repeatable',
    do_wrapper => 1,
    do_label => 0,
    required => 0,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['Call Forward Busy, Number of Objects, each containing the keys ' .
                  '"destinationset", "timeset" and "sourceset". The values must be the name of ' .
                  'a corresponding set which belongs to the same subscriber.'],
    },
);

has_field 'cft' => (
    type => 'Repeatable',
    do_wrapper => 1,
    do_label => 0,
    required => 0,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['Call Forward Timeout, Number of Objects, each containing the keys ' .
                  '"destinationset", "timeset" and "sourceset". The values must be the name of ' .
                  'a corresponding set which belongs to the same subscriber.'],
    },
);

has_field 'cfna' => (
    type => 'Repeatable',
    do_wrapper => 1,
    do_label => 0,
    required => 0,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['Call Forward Unavailable, Number of Objects, each containing the keys ' .
                  '"destinationset", "timeset" and "sourceset". The values must be the name of ' .
                  'a corresponding set which belongs to the same subscriber.'],
    },
);

has_field 'cfs' => (
    type => 'Repeatable',
    do_wrapper => 1,
    do_label => 0,
    required => 0,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['Call Forward SMS, Number of Objects, each containing the keys ' .
                  '"destinationset", "timeset" and "sourceset". The values must be the name of ' .
                  'a corresponding set which belongs to the same subscriber. Alternatively, ' .
                  'you can pass destinationset_id, timeset_id and sourceset_id instead of names.'],
    },
);

has_field 'cfr' => (
    type => 'Repeatable',
    do_wrapper => 1,
    do_label => 0,
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Call Forward on Response, Number of Objects, each containing the keys ' .
                  '"destinationset", "timeset" and "sourceset". The values must be the name of ' .
                  'a corresponding set which belongs to the same subscriber.'],
    },
);

has_field 'cfo' => (
    type => 'Repeatable',
    do_wrapper => 1,
    do_label => 0,
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Call Forward on Overflow, Number of Objects, each containing the keys ' .
                  '"destinationset", "timeset" and "sourceset". The values must be the name of ' .
                  'a corresponding set which belongs to the same subscriber.'],
    },
);

has_field 'cfu.destinationset' => (
    type => 'Compound',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfu.destinationset_id' => (
    type => 'PosInteger',
    do_label => 0,
);

has_field 'cfu.timeset' => (
    type => 'Compound',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfu.timeset_id' => (
    type => 'PosInteger',
    do_label => 0,
);

has_field 'cfu.sourceset' => (
    type => 'Compound',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfu.sourceset_id' => (
    type => 'PosInteger',
    do_label => 0,
);

has_field 'cfu.bnumberset' => (
    type => 'Compound',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfu.bnumberset_id' => (
    type => 'PosInteger',
    do_label => 0,
);

has_field 'cfu.cfm_id' => (
    type => 'PosInteger',
    do_label => 0,
);

has_field 'cfb.destinationset' => (
    type => 'Compound',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfb.destinationset_id' => (
    type => 'PosInteger',
    do_label => 0,
);

has_field 'cfu.enabled' => (
    type => 'Boolean',
    do_label => 0,
);

has_field 'cfu.use_redirection' => (
    type => 'Boolean',
    do_label => 0,
);

has_field 'cfb.timeset' => (
    type => 'Compound',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfb.timeset_id' => (
    type => 'PosInteger',
    do_label => 0,
);

has_field 'cfb.sourceset' => (
    type => 'Compound',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfb.sourceset_id' => (
    type => 'PosInteger',
    do_label => 0,
);

has_field 'cfb.bnumberset' => (
    type => 'Compound',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfb.bnumberset_id' => (
    type => 'PosInteger',
    do_label => 0,
);

has_field 'cfb.enabled' => (
    type => 'Boolean',
    do_label => 0,
);

has_field 'cfb.use_redirection' => (
    type => 'Boolean',
    do_label => 0,
);

has_field 'cfb.cfm_id' => (
    type => 'PosInteger',
    do_label => 0,
);

has_field 'cft.destinationset' => (
    type => 'Compound',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cft.destinationset_id' => (
    type => 'PosInteger',
    do_label => 0,
);

has_field 'cft.timeset' => (
    type => 'Compound',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cft.timeset_id' => (
    type => 'PosInteger',
    do_label => 0,
);

has_field 'cft.sourceset' => (
    type => 'Compound',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cft.sourceset_id' => (
    type => 'PosInteger',
    do_label => 0,
);

has_field 'cft.bnumberset' => (
    type => 'Compound',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cft.bnumberset_id' => (
    type => 'PosInteger',
    do_label => 0,
);

has_field 'cft.enabled' => (
    type => 'Boolean',
    do_label => 0,
);

has_field 'cft.use_redirection' => (
    type => 'Boolean',
    do_label => 0,
);

has_field 'cft.cfm_id' => (
    type => 'PosInteger',
    do_label => 0,
);

has_field 'cfna.destinationset' => (
    type => 'Compound',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfna.destinationset_id' => (
    type => 'PosInteger',
    do_label => 0,
);

has_field 'cfna.timeset' => (
    type => 'Compound',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfna.timeset_id' => (
    type => 'PosInteger',
    do_label => 0,
);

has_field 'cfna.sourceset' => (
    type => 'Compound',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfna.sourceset_id' => (
    type => 'PosInteger',
    do_label => 0,
);

has_field 'cfna.bnumberset' => (
    type => 'Compound',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfna.bnumberset_id' => (
    type => 'PosInteger',
    do_label => 0,
);

has_field 'cfna.enabled' => (
    type => 'Boolean',
    do_label => 0,
);

has_field 'cfna.use_redirection' => (
    type => 'Boolean',
    do_label => 0,
);

has_field 'cfna.cfm_id' => (
    type => 'PosInteger',
    do_label => 0,
);

has_field 'cfs.destinationset' => (
    type => 'Compound',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfs.destinationset_id' => (
    type => 'PosInteger',
    do_label => 0,
);

has_field 'cfs.timeset' => (
    type => 'Compound',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfs.timeset_id' => (
    type => 'PosInteger',
    do_label => 0,
);

has_field 'cfs.sourceset' => (
    type => 'Compound',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfs.sourceset_id' => (
    type => 'PosInteger',
    do_label => 0,
);

has_field 'cfs.bnumberset' => (
    type => 'Compound',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfs.bnumberset_id' => (
    type => 'PosInteger',
    do_label => 0,
);

has_field 'cfs.enabled' => (
    type => 'Boolean',
    do_label => 0,
);

has_field 'cfs.use_redirection' => (
    type => 'Boolean',
    do_label => 0,
);

has_field 'cfs.cfm_id' => (
    type => 'PosInteger',
    do_label => 0,
);

has_field 'cft_ringtimeout' => (
    type => 'PosInteger',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfr.destinationset' => (
    type => 'Compound',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfr.destinationset_id' => (
    type => 'PosInteger',
    do_label => 0,
);

has_field 'cfr.timeset' => (
    type => 'Compound',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfr.timeset_id' => (
    type => 'PosInteger',
    do_label => 0,
);

has_field 'cfr.sourceset' => (
    type => 'Compound',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfr.sourceset_id' => (
    type => 'PosInteger',
    do_label => 0,
);

has_field 'cfr.bnumberset' => (
    type => 'Compound',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfr.bnumberset_id' => (
    type => 'PosInteger',
    do_label => 0,
);

has_field 'cfr.enabled' => (
    type => 'Boolean',
    do_label => 0,
);

has_field 'cfr.use_redirection' => (
    type => 'Boolean',
    do_label => 0,
);

has_field 'cfr.cfm_id' => (
    type => 'PosInteger',
    do_label => 0,
);

has_field 'cfo.destinationset' => (
    type => 'Compound',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfo.destinationset_id' => (
    type => 'PosInteger',
    do_label => 0,
);

has_field 'cfo.timeset' => (
    type => 'Compound',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfo.timeset_id' => (
    type => 'PosInteger',
    do_label => 0,
);

has_field 'cfo.sourceset' => (
    type => 'Compound',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfo.sourceset_id' => (
    type => 'PosInteger',
    do_label => 0,
);

has_field 'cfo.bnumberset' => (
    type => 'Compound',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'cfo.bnumberset_id' => (
    type => 'PosInteger',
    do_label => 0,
);

has_field 'cfo.enabled' => (
    type => 'Boolean',
    do_label => 0,
);

has_field 'cfo.use_redirection' => (
    type => 'Boolean',
    do_label => 0,
);

has_field 'cfo.cfm_id' => (
    type => 'PosInteger',
    do_label => 0,
);

1;

# vim: set tabstop=4 expandtab:
