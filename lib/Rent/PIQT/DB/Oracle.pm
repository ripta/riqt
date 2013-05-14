package Rent::PIQT::DB::Oracle;

use DBI;
use Moo;

with "Rent::PIQT::DB";

sub _build_driver {
    my ($self) = @_;
    return DBI->connect(
        'dbi:Oracle:' . $self->database,
        $self->username,
        $self->password
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

sub sanitize {
    my ($self, $query) = @_;
    $query =~ s#[;/]\s*$##g;
    return $query;
}

1;
