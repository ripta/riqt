package RIQT::Output::CSV;

use Moo;
use String::Escape qw/printable quote/;

with 'RIQT::Output';


sub start {
    my ($self, $fields) = @_;
    $self->out->print(join(",", map { quote printable $_->{'name'} } @$fields) . "\n");
}

sub finish {
    my ($self) = @_;
    # NOOP
}

sub record {
    my ($self, $values) = @_;
    $self->out->print(join(",", map { quote printable $_ } @$values) . "\n");
}

1;

=head1 NAME

RIQT::Output::CSV - CSV output driver for RIQT

=head1 SYNOPSIS

The first line of the output will be the CSV header, containing the list of
column names (quoted). Subsequent lines will be the records resulting from the
query, if any; one record per line of output.

    "object_id","object_tp","name"
    "1","Property","Test property by rent.com"

=head1 AUTHOR

Ripta Pasay <rpasay@rent.com>

=cut
