package RIQT::DB::Oracle;

use DBI;
use List::Util qw/max/;
use Moo;
use String::Escape qw/singlequote/;

our $VERSION = '0.1.3';

our $LOCKVIEW_SQL = q<
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
        NUMTODSINTERVAL(l.ctime, 'second') AS lock_ctime,
        NUMTODSINTERVAL(SYSDATE - TO_DATE(qa.first_load_time, 'YYYY-MM-DD/HH24:MI:SS'), 'second') AS elapsed_time,
        qa.rows_processed AS rows_processed,
        TRUNC(qa.rows_processed / (SYSDATE - TO_DATE(qa.first_load_time, 'YYYY-MM-DD/HH24:MI:SS'))) AS rps,
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
        LEFT JOIN gv$sqlarea qa ON (qa.sql_id = s.sql_id)
>;

with "RIQT::DB";

# Lazily connect to the driver. This also disables auto-commits, and some
# default connection parameters.
sub _build_driver {
    my ($self) = @_;

    my $handle = DBI->connect(
        'dbi:Oracle:' . $self->database,
        $self->username,
        $self->password,
        {
            'AutoCommit'  => 0,
            'LongReadLen' => 1 * 1024 * 1024,
            'LongTruncOk' => 1,
            'RaiseError'  => 0,
            'PrintError'  => 0,
        }
    );

    return $handle if $handle;
    die "Invalid connection information: " . $DBI::errstr;
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

    $self->controller->config->register('server_output', 
        persist => 1,
        hook => sub {
            my ($config, $name, $old_value, $new_value) = @_;
            my $output = $self->controller->output;
            return unless $self->driver;

            $new_value = 20_000 if $new_value == 1;
            die "Unknown value '$new_value'; expected 'on', 'off', or an integer" if $new_value =~ /\D/;

            if ($new_value > 0) {
                if ($self->driver->func($new_value, 'dbms_output_enable')) {
                    $output->okf("DBMS_OUTPUT will now buffer %d lines", $new_value);
                } else {
                    $output->error("Could not activate DBMS_OUTPUT module");
                }
            } else {
                if ($self->driver->func('dbms_output_disable')) {
                    $output->ok("DBMS_OUTPUT buffer has been disabled");
                } else {
                    $output->error("Could not disable DBMS_OUTPUT module");
                }
            }
        },
    );

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

    $self->controller->config->register('iso_dates',
        sub {
            my ($config, $name, $old_value, $new_value) = @_;
            $config->date_format($new_value ? 'YYYY-MM-DD HH24:MI:SS' : 'DD-MON-YYYY');
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
                SELECT 'riqt_tick', TO_CHAR($tick) FROM DUAL
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
        slurp => 1,
        code => sub {
            my ($ctrl, $query, $has_ended) = @_;
            my $rows;

            unless ($has_ended) {
                $ctrl->output->debugf(
                    "Deferring EXPLAIN PLAN until the full query is received. %s bytes in buffer so far.",
                    length($query),
                );
                return 0;
            }

            my $stmt_id = sprintf('%s:%02d%04d', $ENV{'USER'}, $$ % 100, time % 10000);
            $ctrl->output->println;
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
            '%s PACKAGE <object_name>',
            '%s PROCEDURE <object_name>',
            '%s TABLE <object_name>',
            '%s VIEW <object_name>',
        ],
        help => q{
            Print the creation DDL for a database object. DDL retrieval may take a while.
            For a faster alternative, if all you need is the definition of the object and
            not a well-formed DDL, try 'SHOW SOURCE', which takes the same arguments as
            this command.

            If <object_name> is surrounded by double-quotes, it is treated as-is.
            Otherwise, it is treated as all uppercased.
        },
        code => sub {
            my ($ctrl, @args) = @_;

            my $obj = pop @args;
            my $type = uc join ' ', @args;

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
                    my ($o) = @_;
                    $o->start_timing;
                    if ($self->do($sql)) {
                        my $rows = $self->display($ctrl->output);
                        if ($rows) {
                            $o->finish_timing($rows);
                        } else {
                            $o->warnf("Object %s of type %s does not exist", quote($obj), $type) unless $rows;
                        }
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

    $self->controller->register('show source', {
        signature => [
            '%s FUNCTION <object_name>',
            '%s MATERIALIZED VIEW <object_name>',
            '%s PACKAGE <object_name>',
            '%s PROCEDURE <object_name>',
            '%s TABLE <object_name>',
            '%s VIEW <object_name>',
        ],
        help => q{
            Print the source of the object, as originally created. The source may not
            necessarily be compileable. For a well-formed DDL, try 'SHOW CREATE', which
            takes the same arguments as this command.

            If <object_name> is surrounded by double-quotes, it is treated as-is.
            Otherwise, it is treated as all uppercased.
        },
        code => sub {
            my ($ctrl, @args) = @_;

            my $obj = pop @args;
            my $type = uc join ' ', @args;

            die "Object type is missing." unless $type;
            die "Object name is missing." unless $obj;

            if (is_double_quoted($obj)) {
                $obj = unquote_or_die $obj;
            } else {
                $obj = uc $obj;
            }

            my @fn_args = ();
            my $sql     = '';

            if ($obj =~ m{\.}) {
                my ($schema, $name) = split /\./, $obj;
                $sql = 'SELECT text FROM all_source WHERE type = ? AND name = ? AND owner = ? ORDER BY line ASC';
                @fn_args = ($type, $name, $schema);
            } else {
                $sql = 'SELECT text FROM user_source WHERE type = ? AND name = ? ORDER BY line ASC';
                @fn_args = ($type, $obj);
            }

            $ctrl->with_output('text',
                sub {
                    my ($o) = @_;
                    $o->start_timing;
                    if ($self->do($sql, @fn_args)) {
                        my $rows = $self->display($ctrl->output);
                        if ($rows) {
                            $o->finish_timing($rows);
                        } else {
                            $o->warnf("Object %s of type %s does not exist", quote($obj), $type) unless $rows;
                        }
                    }
                },
            );

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

    $self->controller->register('show lock', 'show locks', {
        signature => [
            '%s',
            '%s ACTIVE',
            '%s STATS',
            '%s STATISTICS',
            '%s WHERE <where_clause>',
        ],
        help => q{
            Show all locked objects and sessions accessing or locking those objects across
            all nodes in the cluster.

            By default, the command shows all sessions having anything to do with all the
            locked objects. When ACTIVE is specified, only active sessions, i.e., those
            actively locking the objects, will be shown. This is a shortcut to the following
            SHOW LOCKS WHERE command:

                SHOW LOCKS WHERE session_status = 'ACTIVE'

            The SHOW LOCKS WHERE can also be used to specify arbitrary WHERE clauses.
        },
        code => sub {
            my ($ctrl, @rest) = @_;

            my $o               = $ctrl->output;
            my $stats           = 0;
            my $where_clause    = '';

            if (@rest) {
                if ($rest[0] =~ /^stats|statistics$/i) {
                    $stats = 1;
                } elsif ($rest[0] =~ /^active$/i) {
                    $where_clause = "WHERE session_status = 'ACTIVE'";
                } elsif ($rest[0] =~ /^where$/i) {
                    $where_clause = join(" ", @rest);
                } else {
                    die "Syntax error: unexpected " . $rest[0] . ", expected ACTIVE, STATS, STATISTICS, or WHERE";
                }
            }

            if ($stats) {
                my $sql = qq{
                SELECT
                    session_id,
                    session_status,
                    session_machine,
                    session_type,
                    session_schemaname,
                    session_osuser,
                    dba_object,
                    lock_block,
                    lock_ctime,
                    lock_mode
                FROM (
                    $LOCKVIEW_SQL
                )
                $where_clause
                ORDER BY
                    elapsed_time DESC,
                    lock_ctime DESC,
                    session_id
                };

                if ($self->do($sql)) {
                    my $aggregate = { };
                    while (my $row = $self->fetch_hash) {
                        foreach my $col (sort keys %$row) {
                            next if $col eq 'LOCK_CTIME';
                            $aggregate->{$col} ||= { };
                            $aggregate->{$col}->{ $row->{$col} } ||= 0;
                            $aggregate->{$col}->{ $row->{$col} }++;
                        }
                    }

                    foreach my $col (sort keys %$aggregate) {
                        my $stats = $aggregate->{$col};
                        $o->printlnf("Column %s", $col);

                        my @sorted_cols = sort {
                            $col eq 'LOCK_CTIME'
                                ? $b <=> $a
                                : $stats->{$b} <=> $stats->{$a} || $a cmp $b
                        } keys %$stats;

                        foreach my $val (@sorted_cols) {
                            $o->printlnf("  | %-35s | %-10d |", $val, $stats->{$val});
                        }

                        $o->println;
                    }
                } else {
                    $o->errorf($self->last_error);
                }
            } else {
                my $sql = qq{
                SELECT
                    *
                FROM (
                    $LOCKVIEW_SQL
                )
                $where_clause
                ORDER BY
                    elapsed_time DESC,
                    lock_ctime DESC,
                    session_id
                };

                $o->start_timing;
                my $row_num = $self->do_and_display($sql, $o);
                $o->finish_timing($row_num);
            }

            return 1;
        },
    });

    $self->controller->register('kill', {
        signature => [
            '%s <sid>',
            '%s ACTIVE',
        ],
        help => q{
            Kill an Oracle session. The <sid> must be a string in the form of a session ID
            and session serial#. For example:

                SCOTT> KILL '123,98';
        },
        code => sub {
            my ($ctrl, $sid, @rest) = @_;
            die "Syntax error: too many arguments: @rest" if @rest;
            die "Expected <sid> or ACTIVE" unless $sid;

            my $o = $ctrl->output;

            if (lc $sid eq 'active') {
                my $sql = qq{
                SELECT
                    session_id
                FROM (
                    $LOCKVIEW_SQL
                )
                WHERE
                    session_status = 'ACTIVE'
                };

                $self->do($sql);
                while (my ($sid) = $self->fetch_array) {
                    my $kill_sql = sprintf("ALTER SYSTEM KILL SESSION %s",
                        singlequote($sid),
                    );
                    if ($self->do($kill_sql)) {
                        $o->infof("Killed session %s", $sid);
                    } else {
                        $o->errorf("Could not kill session %s: %s",
                            $sid,
                            $self->last_error,
                        );
                    }
                }
            } else {
                my $sql = sprintf("ALTER SYSTEM KILL SESSION %s",
                    singlequote(unquote_or_die($sid)),
                );
                $self->do_and_display($sql, $o);
            }

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
            $o->start_timing;

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
                    num_rows AS number_of_rows,
                    avg_row_len AS average_row_length,
                    last_analyzed
                FROM
                    ${scope}_tables
                WHERE
                    table_name = '$table'
                $owner_clause
            ];
            $self->do_and_display($table_sql, $o);

            my $inner_owner_clause = $owner ? "ic.table_owner = tc.owner" : "1 = 1";
            my $indexes_sql = qq[
                SELECT
                    $select_owner
                    i.index_name,
                    i.index_type,
                    i.status,
                    i.uniqueness,
                    i.tablespace_name,
                    i.num_rows,
                    (
                        SELECT
                            LISTAGG(
                                ic.column_name || ' ' || ic.descend,
                                ',\n'
                            ) WITHIN GROUP (ORDER BY ic.column_position)
                        FROM
                            ${scope}_ind_columns ic,
                            ${scope}_tab_columns tc
                        WHERE
                            ic.index_name = i.index_name
                        AND $inner_owner_clause
                        AND ic.table_name = tc.table_name
                        AND ic.column_name = tc.column_name
                    ) columns,
                    column_expression expression
                FROM
                    ${scope}_indexes i
                LEFT JOIN ${scope}_ind_expressions ie ON ie.index_name = i.index_name
                WHERE
                    i.table_name = '$table'
                $owner_clause
                ORDER BY
                    index_name
            ];
            $self->do_and_display($indexes_sql, $o);

            my $constraints_sql = qq[
                SELECT
                    ct.constraint_name,
                    SUBSTR(
                        DECODE(
                            ct.constraint_type,
                            'P', 'PRIMARY',
                            'R', 'FOREIGN',
                            'U', 'UNIQUE',
                            'C', 'CHECK',
                            ct.constraint_type
                        ),
                        1, 7
                    ) constraint_type,
                    ct.validated,
                    ct.status,
                    ct.deferred,
                    ct.deferrable,
                    (
                        'REFERENCES ' ||
                        (CASE ct.constraint_type
                        WHEN 'P' THEN 'INDEX ' || ct.index_name
                        WHEN 'R' THEN 'PRIMARY KEY OF ' || ct2.table_name || '.' || ct.r_constraint_name
                        ELSE          'CONDITION (...)' -- || TO_LOB(ct.search_condition)
                        END)
                    ) extra
                FROM
                    ${scope}_constraints ct
                LEFT JOIN ${scope}_constraints ct2
                    ON ct.r_constraint_name = ct2.constraint_name
                WHERE
                    ct.table_name = '$table'
                ORDER BY
                    DECODE(ct.constraint_type, 'P', 1, 'R', 2, 'U', 3, 'C', 4, 5),
                    ct.constraint_name
            ];
            $self->do_and_display($constraints_sql, $o);

            my $triggers_sql = qq[
                SELECT
                    trigger_name,
                    trigger_type,
                    triggering_event,
                    status,
                    action_type,
                    trigger_body
                FROM
                    ${scope}_triggers
                WHERE
                    table_name = '$table'
                ORDER BY
                    trigger_name
            ];
            $self->do_and_display($triggers_sql, $o);

            $o->finish_timing(0);
            return 1;
        }
    });
};

# Retrieve the contents of the DBMS_OUTPUT buffer, and display it as an
# indented warning to the end user. This option must be activated using:
#
#   SET server_output ON;
around cleanup_query => sub {
    my ($orig, $self, $success) = @_;
    my $output = $self->controller->output;

    $success = $self->$orig($success);

    if ($self->controller->config->server_output) {
        my @buffer = $self->driver->func('dbms_output_get');
        if (@buffer) {
            $output->debugf("Retrieved %d lines from DBMS_OUTPUT", scalar(@buffer));
            $output->warn();
            $output->warn("  $_") for @buffer;
        } else {
            $output->debug("No lines in DBMS_OUTPUT buffer");
        }
    }

    return $success;
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

RIQT::DB::Oracle - Oracle-specific database driver for RIQT

=head1 SYNOPSIS

   my $driver = RIQT::DB::Oracle->new(
        database => 'VQA',
        username => 'VIVA',
        password => '...',
        controller => $repl,
    );

=head1 AUTHOR

Ripta Pasay <rpasay@rent.com>

=cut
