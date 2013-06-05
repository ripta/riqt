package Rent::PIQT::DB::Oracle;

use DBI;
use List::Util qw/max/;
use Moo;

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
            'LongReadLen' => 1024,
            'LongTruncOk' => 1,
            'RaiseError'  => 1,
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
