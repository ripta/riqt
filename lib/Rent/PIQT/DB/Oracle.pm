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
    );
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
            my ($ctrl) = @_;
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
        signature => "%s <query>",
        help => q{
            Calculate and display the execution plan for <query>.
        },
        code => sub {
            my ($ctrl, $query) = @_;
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
            '%s TABLE <name>',
            '%s VIEW <name>',
            '%s FUNCTION <name>',
            '%s PROCEDURE <name>',
        ],
        help => q{
            Print the creation DDL for a database object.
        },
        code => sub {
            my ($ctrl, $arg) = @_;
            $arg = uc $arg;

            my ($type, $obj) = split /\s+/, $arg, 2;

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

    $self->controller->register('show invalid', {
        signature => "%s [TABLE|VIEW|FUNCTION|PROCEDURE] [LIKE '%%criteria%%']",
        code => sub {
            my ($ctrl, $args) = @_;
            my @where_clauses = ();

            my ($type, $like_name) = split /\s+LIKE\s+/i, $args, 2;

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

            if ($self->do($sql)) {
                $self->display($ctrl->output);
            } else {
                $ctrl->output->error($self->last_error);
            }

            return 1;
        },
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
