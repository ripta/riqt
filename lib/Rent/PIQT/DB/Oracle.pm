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

sub POSTBUILD {
    my ($self) = @_;
    return unless $self->driver;

    my $date_fmt = $self->controller->config->date_format;
    $date_fmt ||= $self->controller->config->full_dates
            ? 'DD-MON-YYYY HH24:MI:SS'
            : 'DD-MON-YYYY';

    $self->controller->output->infof("Date format is '%s'", $date_fmt);
    $self->driver->do("ALTER SESSION SET NLS_DATE_FORMAT = '" . $date_fmt ."'");
}

around describe_object => sub {
    my ($orig, $self, $name) = @_;
    my @infos = $self->$orig($name);
    return unless @infos;

    use Data::Dumper;
    print STDERR Dumper(\@infos), "\n";

    my $o = $self->controller->output;
    $o->data_set(
        [
            {name => 'Column Name', type => 'str', length => max(11, map { length $_->{'name'} } @infos)},
            {name => 'Type',        type => 'str', length => max( 4, map { length $_->{'type'} . $_->{'precision_scale'} } @infos)},
            {name => 'Nullable',    type => 'str', length => max( 8, map { length $_->{'null'} } @infos)},
        ],
        map {
            [
                $_->{'name'},
                ($_->{'type_id'} == -2 ? 'RAW' : $_->{'type'}) . $_->{'precision_scale'},
                $_->{'null'},
            ]
        } @infos,
    );
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
