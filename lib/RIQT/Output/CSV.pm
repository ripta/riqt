package Rent::PIQT::Output::CSV;

use Moo;
use String::Escape qw/printable quote/;

with 'Rent::PIQT::Output';


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

Rent::PIQT::Output::CSV - CSV output driver for PIQT

=head1 SYNOPSIS

The first line of the output will be the CSV header, containing the list of
column names (quoted). Subsequent lines will be the records resulting from the
query, if any; one record per line of output.

    "object_id","object_tp","name"
    "1","Property","Test property by rent.com"

=head1 AUTHOR

Ripta Pasay <rpasay@rent.com>

=cut
