package Rent::PIQT::Output::Columnar;

use Moo;
use Text::Table;

with 'Rent::PIQT::Output';

has sep => (is => 'lazy');
sub _build_sep {
    return {
        is_sep => 1,
        title  => " \x{2503} ",
        body   => " \x{2502} "
    };
}

has table => (is => 'rw');

sub start {
    my ($self, $fields) = @_;

    my @headings = map { ($_->{'name'}, $self->sep) } @$fields;
    pop @headings if @headings;

    $self->debugf("Adding heading: (%s)", join(', ', @headings));
    $self->table(Text::Table->new(@headings));
}

sub finish {
    my ($self) = @_;
    my $t = $self->table;

    $self->debugf("Printing output table with %d lines", $t->body_height);
    $self->println;

    foreach ($t->title) {
        $self->print($_);
    }
    $self->print($t->rule("\x{2501}", "\x{2547}"));
    foreach ($t->body) {
        $self->print($_);
    }

    $self->table(undef);
}

sub record {
    my ($self, $values) = @_;
    $self->debugf("Added new record with %d values", scalar(@$values));
    $self->table->add(@$values);
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
