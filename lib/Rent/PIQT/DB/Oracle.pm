package Rent::PIQT::DB::Oracle;

use DBI;
use List::Util qw/max/;
use Moo;

with "Rent::PIQT::DB";

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

sub BUILDARGS {
    my ($class, $database, $username, $password) = @_;
    return $database if ref $database eq 'HASH';
    return {
        database => $database,
        username => $username,
        password => $password,
    };
}

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

sub query_is_plsql_block {
    my ($self, $query) = @_;
    return 1 if $query =~ /^\s*(BEGIN|DECLARE)\s+/i;
    return 1 if $query =~ /^\s*CREATE(\s+OR\s+REPLACE)?\s+(FUNCTION|PACKAGE|PACKAGE\s+BODY|PROCEDURE|TRIGGER|TYPE)/i;
    return 1 if $query =~ /\b(RETURN|TYPE)\s+\S+\s+IS\b/i;
    return 0;
}

sub sanitize {
    my ($self, $query) = @_;
    return $query if $self->query_is_plsql_block($query);

    $query =~ s#[;/]\s*$##g;
    return $query;
}

1;
