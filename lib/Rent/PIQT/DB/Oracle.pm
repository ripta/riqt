package Rent::PIQT::DB::Oracle;

use DBI;
use List::Util qw/max/;
use Moo;
use String::Escape qw/singlequote/;

with "Rent::PIQT::DB";

# Lazily connect to the driver. This also disables auto-commits, and some
# default connection parameters.
sub _build_driver {
    my ($self) = @_;

    return DBI->connect(
        'dbi:Oracle:' . $self->database,
        $self->username,
        $self->password,
        {
            'AutoCommit'  => 0,
            'LongReadLen' => 8 * 1024,
            'LongTruncOk' => 1,
            'RaiseError'  => 0,
            'PrintError'  => 0,
        }
    ) or die DBI->errstr;
}

# Transforms Oracle->new($db, $user, $pass) into Oracle->new(\%opts).
sub BUILDARGS {
    my ($class, $database, $username, $password) = @_;
    return $database if ref $database eq 'HASH';
    return {
        database => $database,
        username => $username,
        password => $password,
    };
}

# Register any driver-specific configuration parameters here.
around POSTBUILD => sub {
    my ($orig, $self) = @_;
    $self->$orig;

    $self->controller->config->register('date_format',
        sub {
            my ($config, $name, $old_value, $new_value) = @_;

            return unless $self->driver;
            $self->driver->do("ALTER SESSION SET NLS_DATE_FORMAT = '" . $new_value ."'");
            $self->controller->output->okf("Session has been altered to format dates as '%s'", $new_value);
        },
    );

    $self->controller->config->register('full_dates',
        sub {
            my ($config, $name, $old_value, $new_value) = @_;
            $config->date_format($new_value ? 'DD-MON-YYYY HH24:MI:SS' : 'DD-MON-YYYY');
        },
    );

    $self->controller->register('date', 'time',
        sub {
            my ($ctrl, @rest) = @_;
            die "Syntax error: command takes no arguments" if @rest;

            my $tick = int($ctrl->tick * 1000);
            my $sql = qq{
                SELECT 'database' origin, TO_CHAR(SYSDATE) value FROM DUAL
                UNION
                SELECT 'piqt_tick', TO_CHAR($tick) FROM DUAL
            };

            if ($self->do($sql)) {
                $self->display($ctrl->output);
            } else {
                $ctrl->output->error($self->last_error);
            }

            return 1;
        },
    );

    $self->controller->register('explain', 'explain plan', 'explain plan for', {
        signature => "%s <query>*",
        help => q{
            Calculate and display the execution plan for <query>. The <query> should be
            presented as-is, e.g.:

                EXPLAIN SELECT * FROM test;
        },
        code => sub {
            my ($ctrl, @rest) = @_;
            my $query = join ' ', @rest;
            my $rows;

            my $stmt_id = sprintf('%s:%02d%04d', $ENV{'USER'}, $$ % 100, time % 10000);
            $ctrl->output->info("Statement will be planned as $stmt_id");

            $rows = $self->driver->do(qq{DELETE FROM plan_table WHERE statement_id = '$stmt_id'});
            return $ctrl->output->error($self->driver->errstr) unless $rows;

            $rows = $self->driver->do(qq{
                EXPLAIN PLAN
                SET
                    statement_id = '$stmt_id'
                FOR
                    $query
            });
            return $ctrl->output->error($self->driver->errstr) unless $rows;

            my $cost_sql = qq{
                SELECT
                    SUM(cost)
                FROM
                    plan_table
                WHERE
                    statement_id = '$stmt_id'
            };

            my $cost_sth = $self->driver->prepare($cost_sql);
            return $ctrl->output->error($self->driver->errstr) unless $cost_sth;

            $cost_sth->execute or do {
                $ctrl->output->error($cost_sth->errstr);
                return;
            };

            my ($cost) = $cost_sth->fetchrow_array;
            die "Could not calculate EXPLAIN cost. Internal error?" unless $cost;

            $ctrl->output->okf(
                "TOTAL COST: %s",
                $cost,
            );

            my $retrieve_sql = qq{
                SELECT
                    LPAD(' ', LEVEL - 1) || DECODE(options,
                        NULL,
                        operation,
                        operation || ' (' || options || ')'
                    ) operation,
                    object_name,
                    cardinality num_rows,
                    cost
                FROM
                    plan_table
                START WITH
                    id = 0
                AND statement_id = '$stmt_id'
                CONNECT BY
                    PRIOR id = parent_id
                AND PRIOR statement_id = statement_id
            };

            $self->display($ctrl->output) if $self->do($retrieve_sql);
            return 1;
        },
    });

    $self->controller->register('show create', {
        signature => [
            '%s FUNCTION <object_name>',
            '%s MATERIALIZED VIEW <object_name>',
            '%s PROCEDURE <object_name>',
            '%s TABLE <object_name>',
            '%s VIEW <object_name>',
        ],
        help => q{
            Print the creation DDL for a database object. DDL retrieval may take a while.
            For a faster alternative, if all you need is the definition of the object and
            not a well-formed DDL, try 'SHOW SOURCE'.

            If <object_name> is surrounded by double-quotes, it is treated as-is.
            Otherwise, it is treated as all uppercased.
        },
        code => sub {
            my ($ctrl, @args) = @_;

            my $obj = pop @args;
            my $type = join ' ', @args;

            die "Object type is missing." unless $type;
            die "Object name is missing." unless $obj;

            if (is_double_quoted($obj)) {
                $obj = unquote_or_die $obj;
            } else {
                $obj = uc $obj;
            }

            my @fn_args = ();
            if ($obj =~ m{\.}) {
                my ($schema, $name) = split /\./, $obj;
                @fn_args = ($type, $name, $schema);
            } else {
                @fn_args = ($type, $obj);
            }

            my $sql = sprintf("SELECT DBMS_METADATA.GET_DDL('%s') FROM DUAL", join("', '", @fn_args));
            $ctrl->with_output('text',
                sub {
                    if ($self->do($sql)) {
                        my $rows = $self->display($ctrl->output);
                        $ctrl->output->warnf("Object %s of type %s does not exist", quote($obj), $type) unless $rows;
                    }
                },
            );

            return 1;
        },
    });

    $self->controller->register('show errors', {
        signature => [
            "%s",
            "%s LIKE '%%criteria%%'",
        ],
        code => sub {
            my ($ctrl, $mode, $like_name) = @_;
            die "Syntax error: unexpected $mode, expected LIKE" if $mode && uc $mode ne 'LIKE';

            my @where_clauses = ();

            if ($like_name) {
                if (is_single_quoted($like_name)) {
                    push @where_clauses, "name LIKE " . uc($like_name);
                } else {
                    die "Syntax error: expected LIKE to be followed by a single-quoted string";
                }
            }

            my $where_clause = @where_clauses ? "AND " . join("\nAND ", @where_clauses) : "";
            my $sql = qq{
                SELECT
                    attribute,
                    owner,
                    name,
                    type,
                    line,
                    position,
                    message_number,
                    text
                FROM
                    all_errors
                WHERE
                    1 = 1
                    $where_clause
                ORDER BY
                    sequence ASC
            };

            $self->do_and_display($sql, $ctrl->output);
            return 1;
        },
    });

    $self->controller->register('show invalid', {
        signature => "%s [TABLE|VIEW|FUNCTION|PROCEDURE] [LIKE '%%criteria%%']",
        code => sub {
            my ($ctrl, $type, $mode, $like_name) = @_;
            die "Syntax error: unexpected $mode, expected LIKE" if $mode && uc $mode ne 'LIKE';

            my @where_clauses = ();
            push @where_clauses, "object_type = " . singlequote(uc($type)) if $type;

            if ($like_name) {
                if (is_single_quoted($like_name)) {
                    push @where_clauses, "object_name LIKE " . uc($like_name);
                } else {
                    die "Syntax error: expected LIKE to be followed by a single-quoted string";
                }
            }

            my $where_clause = @where_clauses ? "AND " . join("\nAND ", @where_clauses) : "";
            my $sql = qq{
                SELECT
                    owner,
                    object_name,
                    object_type,
                    status
                FROM
                    dba_objects
                WHERE
                    status <> 'VALID'
                AND owner NOT IN ('SYSTEM', 'SYS', 'XDB')
                    $where_clause
            };

            $self->do_and_display($sql, $ctrl->output);
            return 1;
        },
    });

    $self->controller->register('show sessions', {
        code => sub {
            my ($ctrl, @args) = @_;

            my $sql = q{ SELECT * FROM gv$session };
            $sql .= join ' ', @args if @args;

            $self->do_and_display($sql, $ctrl->output);
            return 1;
        },
    });

    $self->controller->register('show trans', 'show transactions', {
        code => sub {
            my ($ctrl, @args) = @_;

            my $sql = q{ SELECT * FROM gv$transaction };
            $sql .= join ' ', @args if @args;

            $self->do_and_display($sql, $ctrl->output);
            return 1;
        },
    });

    $self->controller->register('show locks', {
        code => sub {
            my ($ctrl, @rest) = @_;
            die "Syntax error: command takes no arguments" if @rest;

            my $sql = q{
                SELECT
                    s.sid || ',' || s.serial# || '@' || s.inst_id AS session_id,
                    s.status AS session_status,
                    s.machine AS session_machine,
                    s.program AS session_program,
                    s.type AS session_type,
                    s.schemaname AS session_schemaname,
                    s.osuser AS session_osuser,
                    d.owner || '.' || d.object_name AS dba_object,
                    d.object_type AS dba_object_type,
                    DECODE(l.block, 0, 'Not Blocking', 1, 'Blocking', 2, 'Global') AS lock_block,
                    l.ctime AS lock_ctime,
                    DECODE(
                        v.locked_mode,
                        0, 'None',
                        1, 'Null',
                        2, 'Row-Share (Conc. Read)',
                        3, 'Row-Exclusive (Conc. Write)',
                        4, 'Share (Prot. Read)',
                        5, 'Share Row-X (Prot. Write)',
                        6, 'Exclusive',
                        'Other: ' || TO_CHAR(v.locked_mode)
                    ) AS lock_mode,
                    q.sql_text AS sql
                FROM gv$locked_object v
                    JOIN gv$lock l ON (l.id1 = v.object_id)
                    LEFT JOIN dba_objects d ON (d.object_id = v.object_id)
                    LEFT JOIN gv$session s ON (s.sid = v.session_id)
                    LEFT JOIN gv$sql q ON (q.sql_id = s.sql_id)
                ORDER BY
                    l.ctime DESC,
                    session_id
            };

            $self->do_and_display($sql, $ctrl->output);
            return 1;
        },
    });

    $self->controller->register('kill', {
        signature => '%s <sid>',
        help => q{
            Kill an Oracle session. The <sid> must be a string in the form of a session ID
            and session serial#. For example:

                SCOTT> KILL '123,98';
        },
        code => sub {
            my ($ctrl, $sid, @rest) = @_;
            die "Syntax error: too many arguments: @rest" if @rest;

            my $sql = sprintf("ALTER SYSTEM KILL SESSION %s",
                singlequote(unquote_or_die($sid)),
            );
            $self->do_and_display($sql, $ctrl->output);
            return 1;
        },
    });

    $self->controller->register('tblstat', 'tblstatus', {
        signature => [
            '%s <name>',
            '%s <owner>.<name>',
        ],
        help => q{
            Retrieve information about a specific table. Arguments should not be quoted.

            If an owner is specified, this command will search for a table that the
            current user has access to. Otherwise, the current user is searched.

            Information displayed covers:
            - the validity of the table, creation date, and owner data;
            - indexes defined for the table and all its columns and expressions;
            - constraints defined for the table and its rules; and
            - triggers defined for the table.
        },
        code => sub {
            my ($ctrl, $object) = @_;
            my $o = $ctrl->output;

            my $table = uc($object);
            my $owner = $table =~ s/(\w+)\.// ? $1 : undef;
            my $scope = $owner ? 'all' : 'user';
            my $owner_clause = $owner ? "AND owner = '$owner'" : '';
            my $select_owner = $owner ? "owner, " : '';

            my $object_type_sql = qq[
                SELECT
                    owner,
                    status,
                    created
                FROM
                    all_objects
                WHERE
                    object_type = 'TABLE'
                AND object_name = '$table'
                $owner_clause
            ];
            unless ($self->do($object_type_sql)) {
                $o->error($self->last_error);
                return 1;
            }

            my $matches = $self->fetch_all_arrays;
            if (scalar(@$matches) == 0) {
                $o->errorf("Table %s doesn't exist", quote($table));
                return 1;
            } elsif (scalar(@$matches) > 1) {
                $o->warnf("There are %s matches for %s:", scalar(@$matches), quote($object));
                foreach (@$matches) {
                    $o->warnf("- %s.%s", $_->[0], $table);
                }
            }

            my $table_sql = qq[
                SELECT DISTINCT
                    $select_owner
                    table_name,
                    status,
                    tablespace_name,
                    num_rows,
                    avg_row_len,
                    last_analyzed
                FROM
                    ${scope}_tables
                WHERE
                    table_name = '$table'
                $owner_clause
            ];
            $self->do_and_display($table_sql, $o);

            my $indexes_sql = qq[
                SELECT
                    $select_owner
                    index_name,
                    index_type,
                    status,
                    uniqueness,
                    tablespace_name,
                    num_rows
                FROM
                    ${scope}_indexes
                WHERE
                    table_name = '$table'
                $owner_clause
                ORDER BY
                    index_name
            ];
            $self->do_and_display($indexes_sql, $o);

            # my $column_sql = qq{
            #     SELECT
            #         aic.column_name,
            #         atc.data_default,
            #         aic.descend
            #     FROM
            #         all_ind_columns aic,
            #         all_tab_cols atc
            #     WHERE
            #         aic.index_name = ?
            #     AND aic.table_owner = atc.owner
            #     AND aic.table_name = atc.table_name
            #     AND aic.column_name = atc.column_name
            #     ORDER BY
            #         aic.column_position
            # };
            # my $column_sub = sub {
            #     my ($db, $row) = @_;

            #     $sth->execute($row->[0]);
            #     print "             COLUMNS: ", lc join(', ', map { ($_->[0] =~ /\$$/ ? $_->[1] : $_->[0]) . " $_->[2]" } @{$sth->fetchall_arrayref}), "\n";
            # };

            # print "INDEXES:\n\n";
            # $self->display_function(\&DatabaseManager::_format_data_mysql);
            # $self->process_query(qq{
            #     SELECT
            #         index_name,
            #         index_type,
            #         status,
            #         uniqueness "unique",
            #         tablespace_name,
            #         num_rows
            #     FROM
            #         all_indexes
            #     WHERE
            #         table_name = '$table'
            #     ORDER BY
            #         index_name
            # }, {
            #     POST_REC => $column_sub
            # });
            # print "\n";

            # $sth = $self->connection->prepare_cached(q{
            #     SELECT /* PIQT::table_status::indexes */
            #         ct.constraint_type,
            #         ct.index_name,
            #         ct.r_constraint_name,
            #         ct.search_condition,
            #         ct2.table_name fk_table
            #     FROM
            #         all_constraints ct
            #     LEFT JOIN all_constraints ct2 ON ct.r_constraint_name = ct2.constraint_name
            #     WHERE ct.constraint_name = ?
            # });
            # $column_sub = sub {
            #     my ($db, $row) = @_;

            #     $sth->execute($row->[0]);
            #     my ($type, $index, $ref, $sc, $fktbl) = $sth->fetchrow_array;
            #     print "             REFERENCES ",
            #           $type eq 'P' ? "INDEX     : $index"
            #         : $type eq 'R' ? "PK        : of $fktbl ($ref)"
            #         :                "CONDITION : $sc", "\n";
            #     $sth->finish;
            # };

            # print "CONSTRAINTS:\n\n";
            # $self->process_query(qq{
            # SELECT /* PIQT::table_status::constraints */
            #     ct.constraint_name,
            #     SUBSTR(
            #         DECODE(ct.constraint_type,
            #                 'P', 'Primary Key',
            #                 'R', 'Foreign Key',
            #                 'U', 'Unique',
            #                 'C', 'Check',
            #                      'Other'
            #         ),
            #     1, 11) as "type",
            #     ct.validated,
            #     ct.status,
            #     ct.deferred,
            #     ct.deferrable
            # FROM
            #     all_constraints ct
            # WHERE
            #     ct.table_name = '$table'
            # ORDER BY
            #     DECODE(ct.constraint_type,
            #             'P', 1,
            #             'R', 2,
            #             'U', 3,
            #             'C', 4,
            #             5
            #     ),
            #     ct.constraint_name
            # }, {
            #     POST_REC => $column_sub
            # });
            # print "\n";

            # $column_sub = sub {
            # };

            # print "TRIGGERS:\n\n";
            # $self->process_query(qq{
            # SELECT /* PIQT::table_status::triggers */
            #     tg.trigger_name,
            #     tg.trigger_type || ', ' || tg.triggering_event as "trigger_type",
            #     tg.status,
            #     tg.action_type
            # FROM
            #     all_triggers tg
            # WHERE
            #     tg.table_name = '$table'
            # ORDER BY
            #     trigger_name
            # }, {
            #     POST_REC => $column_sub
            # });

            # $self->display_function($prev_dispfunc);
            return 1;
        }
    });
};

# Transform the output of describe_object into something more palatable, which
# includes special handling of RAW columns in Oracle.
around describe_object => sub {
    my ($orig, $self, $name) = @_;
    my @infos = $self->$orig($name);

    return unless @infos;
    return map {
        $_->{'type'} = 'RAW' if $_->{'type_id'} == -2;
        $_->{'type'} = 'XMLTYPE' if $_->{'type_id'} == -9108;

        $_->{'type'} = $_->{'type'} . $_->{'precision_scale'};
        $_
    } @infos;

};

# Check whether the query provided is complete or not. Query completion here
# is defined as ending with a semicolon if the query isn't a PL/SQL block.
sub query_is_complete {
    my ($self, $query) = @_;

    # Strip leading and trailing whitespace
    $query =~ s/^\s+//s;
    $query =~ s/\s+$//s;

    # Strip comments
    $query =~ s/--.*?$//mg;

    # If query is a PL/SQL block, then query is never complete
    return 0 if $self->query_is_plsql_block($query);

    # If query ends with a semicolon (and not a PL/SQL block) assume it's the end
    return $query =~ /;\s*/ ? 1 : 0;
}

# Check whether the query provided is a PL/SQL block. Only very specific types
# of queries can contain PL/SQL blocks. Anonymous blocks start with BEGIN or
# DECLARE, while named blocks have to be part of a FUNCTION, PACKAGE, PACKAGE
# BODY, PROCEDURE, TRIGGER, or TYPE definition.
sub query_is_plsql_block {
    my ($self, $query) = @_;
    return 1 if $query =~ /^\s*(BEGIN|DECLARE)\s+/i;
    return 1 if $query =~ /^\s*CREATE(\s+OR\s+REPLACE)?\s+(FUNCTION|PACKAGE|PACKAGE\s+BODY|PROCEDURE|TRIGGER|TYPE)/i;
    return 1 if $query =~ /\b(RETURN|TYPE)\s+\S+\s+IS\b/i;
    return 0;
}

# Sanitize the query. PL/SQL blocks are not sanitized, while single-line SQL
# queries are sanitized by removing its trailing semicolon.
sub sanitize {
    my ($self, $query) = @_;
    return $query if $self->query_is_plsql_block($query);

    $query =~ s#[;/]\s*$##g;
    return $query;
}

1;

=head1 NAME

Rent::PIQT::DB::Oracle - Oracle-specific database driver for PIQT

=head1 SYNOPSIS

    my $driver = Rent::PIQT::DB::Oracle->new(
        database => 'VQA',
        username => 'VIVA',
        password => '...',
        controller => $repl,
    );

=head1 AUTHOR

Ripta Pasay <rpasay@rent.com>

=cut
