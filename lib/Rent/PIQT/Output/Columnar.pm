package Rent::PIQT::Output::Columnar;

use Moo;

with 'Rent::PIQT::Output';


sub start {
    my ($self, $fields) = @_;

    foreach my $field (@$fields) {
        my ($name, $type, $len) = @$field{qw/name type length/};
    }
}

sub finish {
    my ($self) = @_;
}

sub record {
    my ($self, $values) = @_;
}

1;

=head1 NAME

Rent::PIQT::Output::Columnar - Column-oriented output driver for PIQT

=head1 SYNOPSIS

Output like tabular, except each column containing a newline is formatted
in the same column.

    object_id   1
    object_tp   Property
    name        Test property by rent.com

=head1 AUTHOR

Ripta Pasay <rpasay@rent.com>

=cut
