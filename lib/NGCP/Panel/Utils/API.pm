package NGCP::Panel::Utils::API;

use strict;
use warnings;

use File::Find::Rule;
use JSON qw();


sub get_collections {
    my @files = @{get_collections_files()};
    my(@collections, @packages, @modules);
    foreach my $mod(@files) {
        # extract file base from path (e.g. Foo from lib/something/Foo.pm)
        $mod =~ s/^.+\/([a-zA-Z0-9_]+)\.pm$/$1/;
        my $package = 'NGCP::Panel::Controller::API::'.$mod;
        my $rel = lc $mod;
        $mod = 'NGCP::Panel::Controller::API::'.$mod;
        push @modules, $mod;
        push @packages, $package;
        push @collections, $rel;
    }
    return \@files, \@packages, \@collections, \@modules;
}

sub get_collections_files {
    my($library,$libpath) = @_;
    if(!$libpath){
        # figure out base path of our api modules
        $library ||= "NGCP/Panel/Controller/API/Root.pm";
        $libpath = $INC{$library};
        $libpath =~ s/\/[^\/]+$/\//;
    }
    # find all modules not called Root.pm and *Item.pm
    # (which should then be just collections)
    my $rootrule = File::Find::Rule->new->name('Root.pm');
    my $itemrule = File::Find::Rule->new->name('*Item.pm');
    my $rule = File::Find::Rule->new
        ->mindepth(1)
        ->maxdepth(1)
        ->name('*.pm')
        ->not($rootrule)
        ->not($itemrule);
    my @colls = $rule->in($libpath);

    return \@colls;
}

sub generate_swagger_datastructure {
    my ($collections, $user_role) = @_;

    my %paths;
    my %schemas;
    my %responses = (
        ErrorResponse => {
            description => 'An error',
            content => {
                "application/json" => {
                    "schema" => {
                        type => "object",
                        properties => {
                            code => { type => "integer" },
                            message => { type => "string" },
                        }
                    }
                }
            }
        }
    );
    my %parameters = (
        PageParameter => {
            name => 'page',
            in => 'query',
            description => 'Pagination page which should be displayed (default: 1)',
            example => 1,
            schema => {type => 'integer'}, # schema is required
        },
        RowsParameter => {
            name => 'rows',
            in => 'query',
            description => 'Number of rows in one pagination page (default: 10)',
            example => 10,
            schema => {type => 'integer'}, # schema is required
        },
        ItemIdParameter => {
            "name" => "id",
            "in" => "path",
            "required" => JSON::true,
            "schema" => { type => "integer" },
        },
    );
    my %requestBodies = (
        PatchBody => {
            description => "A JSON patch document specifying modifications",
            required => JSON::true,
            content => {
                'application/json-patch+json' => {
                    schema => {
                        # '$ref' => 'http://json.schemastore.org/json-patch.json#/',
                        # "$ref": "https://raw.githubusercontent.com/fge/sample-json-schemas/master/json-patch/json-patch.json"
                        '$ref' => '/js/schemas/json-patch.json#/',
                        # type => 'array',
                        # items => {
                        #     type => 'object',
                        # }
                    }
                }
            }
        }
    );

    my @chapters = sort (keys %{ $collections });

    for my $chapter (@chapters) {
        my $col = $collections->{$chapter};
        my $p = {}; # Path Item Object
        my $item_p = {}; # Path Item Object for "NGCP Item"
        my $title = $col->{name};
        my $entity = $col->{entity_name};

        if (grep {m/^GET$/} @{ $col->{actions} }) {
            $p->{get} = {
                summary => "Get $entity items",
                tags => ['Collection Get'],
                responses => {
                    "200" => {
                        description => "$title",
                        content => {
                            "application/json" => {
                                schema => {
                                    type => "array", # I want an Array to $entity objects here
                                    items => {
                                        '$ref' => "#/components/schemas/$entity",
                                    }
                                }
                            },
                        },
                    }
                }
            };

            for my $query_param (@{ $col->{query_params} // [] }) {
                push @{$p->{get}{parameters} }, {
                    name => $query_param->{param},
                    description => $query_param->{description},
                    in => 'query',
                    schema => {type => 'string'}, # schema is required
                };
            }
            if ($col->{sorting_cols} && @{ $col->{sorting_cols} }) {
                push @{$p->{get}{parameters} }, {
                        name => 'order_by',
                        description => 'Order collection by a specific attribute.',
                        in => 'query',
                        schema => {
                            type => 'string',
                            enum => [ @{ $col->{sorting_cols} } ],
                        }
                    },{
                        name => 'order_by_direction',
                        description => 'Direction which the collection should be ordered by. Possible values are: asc (default), desc.',
                        in => 'query',
                        example => 'asc',
                        schema => {
                            type => 'string',
                            enum => [ 'asc', 'desc' ],
                        }
                    };
            }
            push @{ $p->{get}{parameters} }, {
                    '$ref' => '#/components/parameters/PageParameter',
                },{
                    '$ref' => '#/components/parameters/RowsParameter',
                };
        }

        if (grep {m/^POST$/} @{ $col->{actions} }) {
            $p->{post} = {
                # description => "Creates a new item of $title",
                summary => "Create a new $entity",
                tags => ['Collection Post'],
                requestBody => {
                    required => JSON::true,
                    content => {
                        "application/json" => {
                            schema => {
                                '$ref' => "#/components/schemas/$entity",
                            }
                        }
                    }
                },
                responses => {
                    "201" => {
                        description => "The newly created item or empty",
                        content => {
                            "application/json" => {
                                schema => {
                                    type => "array",
                                    items => {
                                        '$ref' => "#/components/schemas/$entity",
                                    }
                                }
                            },
                            # "*/*" => {
                            #     schema => { type => "string", maxLength => 0 }
                            # }
                        },
                        headers => {
                            "Location" => {
                                "description" => "Location of the newly created item (as a relative path)",
                                "schema" => {
                                    "type" => "string",
                                }
                            }
                        }
                    },
                    "422" => { '$ref' => "#/components/responses/ErrorResponse" },
                }
            };
        }

        if (grep {m/^GET$/} @{ $col->{item_actions} }) {
            $item_p->{get} = {
                summary => "Get a specific $entity",
                tags => ['Item Get'],
                responses => {
                    "200" => {
                        description => "$title",
                        content => {
                            "application/json" => {
                                schema => {
                                    '$ref' => "#/components/schemas/$entity",
                                }
                            },
                        },
                    }
                }
            };
        }

        if (grep {m/^PUT$/} @{ $col->{item_actions} }) {
            $item_p->{put} = {
                summary => "Replace/change a specific $entity",
                tags => ['Item Put'],
                requestBody => {
                    required => JSON::true,
                    content => {
                        "application/json" => {
                            schema => {
                                '$ref' => "#/components/schemas/$entity",
                            }
                        }
                    }
                },
                responses => {
                    "200" => {
                        description => "$title",
                        content => {
                            "application/json" => {
                                schema => {
                                    '$ref' => "#/components/schemas/$entity",
                                }
                            },
                        },
                    },
                    "204" => {
                        description => "Put successful",
                        # empty content
                    },
                }
            };
        }

        if (grep {m/^PATCH$/} @{ $col->{item_actions} }) {
            $item_p->{patch} = {
                summary => "Change a specific $entity",
                tags => ['Item Patch'],
                requestBody => {
                    '$ref' => '#/components/requestBodies/PatchBody',
                },
                responses => {
                    "200" => {
                        description => "$title",
                        content => {
                            "application/json" => {
                                schema => {
                                    '$ref' => "#/components/schemas/$entity",
                                }
                            },
                        },
                    },
                    "204" => {
                        description => "Patch successful",
                        # empty content
                    },
                }
            };
        }

        if (grep {m/^DELETE$/} @{ $col->{item_actions} }) {
            $item_p->{delete} = {
                summary => "Delete a specific $entity",
                tags => ['Item Delete'],
                responses => {
                    "204" => {
                        description => "Deletion successful",
                        # empty content
                    },
                }
            };
        }

        # common description for all methods
        $p->{description} = $col->{description};

        #push @paths, $p;
        $paths{'/'.$chapter.'/'} = $p;
        if (keys %{ $item_p }) {
            $item_p->{description} = $col->{description};
            $item_p->{parameters} = [
                { '$ref' => '#/components/parameters/ItemIdParameter' },
            ];
            $paths{'/'.$chapter.'/{id}'} = $item_p;
        }


        # ---------------------------------------------

        my $e = {
            type => "object",
            properties => {},
            required => [],
        };

        # possible values for types: null, (select options), Number, Boolean, Array, Object, String
        for my $f (@{ $col->{fields} }) {
            my $p = {};
            if ($f->{type_original} eq "Select" ||
                ($f->{type_original} =~ m/\+NGCP::Panel::Field::.*Select$/ && $f->{enum})) {
                $p->{type} = "string";
                $p->{enum} = [ map {$_->{value}} @{ $f->{enum} // [] } ];
            } elsif ($f->{type_original} eq 'IntRange') {
                $p->{type} = "number";
                $p->{enum} = [ map {$_->{value}} @{ $f->{enum} // [] } ];
            } elsif ($f->{type_original} eq "Boolean") {
                $p->{type} = "boolean";
            } elsif (grep {m/^Number$/} @{$f->{types}}) {
                $p->{type} = "number";
            } elsif ($f->{type_original} eq '+NGCP::Panel::Field::EmailList' ||
                     $f->{type_original} eq 'Email') {
                $p->{type} = "string";
                $p->{format} = "email"; # not the same as emaillist but that's nit-picky
            } elsif ($f->{type_original} eq '+NGCP::Panel::Field::DateTime') {
                $p->{type} = "string";
                $p->{format} = "date-time"; # actually a slightly different format
            } elsif ($f->{type_original} eq "Text" || grep {m/^String$/} @{$f->{types}}) {
                $p->{type} = "string";
            } elsif ($f->{type_original} eq "Repeatable" || grep {m/^Array$/} @{$f->{types}}) {
                $p->{type} = "array";
                $p->{items}{type} = "object"; # content of array basically unspecified
            } else {
                $p->{type} = "object"; # object or uncategorizable
            }

            $p->{description} = $f->{description};
            if (grep {m/^null$/} @{ $f->{types} // [] }) {
                push @{ $e->{required} }, $f->{name};
            }

            $e->{properties}{$f->{name}} = $p;
        }
        unless (@{ $e->{required} }) {
            delete $e->{required}; # empty required is not allowed
        }
        unless (keys %{ $e->{properties} }) {
            delete $e->{properties}; # try delete empty properties (then it's a valid Free Form Object)
        }

        $schemas{$entity} = $e;
    }

    my $role = "".$user_role;
    my $result = {
        "openapi" => "3.0.0",
        "info"    => {
            "title"       => "NGCP API",
            "description" => "Sipwise NGCP API (role $role)",
            "version"     => "1.0.1",
        },
        "servers" => [ { "url" => "/api" } ],

        "paths" => \%paths,
        "components" => {
            "schemas" => \%schemas,
            "responses" => \%responses,
            "parameters" => \%parameters,
            "requestBodies" => \%requestBodies,
        },
    };

    return $result;
}

1;

=head1 NAME

NGCP::Panel::Utils::API

=head1 DESCRIPTION

A helper to manipulate REST API related data

=head1 METHODS

=head1 AUTHOR

Irina Peshinskaya

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
# vim: set tabstop=4 expandtab:
