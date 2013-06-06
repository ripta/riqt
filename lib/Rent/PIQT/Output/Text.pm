package Rent::PIQT::Output::Text;

use Moo;
use String::Escape qw/printable/;
use Time::HiRes qw/gettimeofday tv_interval/;

with 'Rent::PIQT::Output';

has 'field_names', (is => 'rw');

sub start {
    my ($self, $fields) = @_;
    $self->field_names([map { $_->{'name'} } @$fields]);
}

sub finish {
    my ($self) = @_;
}

sub record {
    my ($self, $values) = @_;
    foreach my $idx (0..$#$values) {
        # $self->printlnf("%s:", $self->field_names->[$idx]);

        if (defined $values->[$idx]) {
            foreach my $line (split /\n/, $values->[$idx]) {
                $self->println('    ' . $line);
            }
        } else {
            $self->println('    (null)');
        }

        $self->println;
    }
}

1;

=head1 NAME

Rent::PIQT::Output::Text - Text output driver for PIQT

=head1 SYNOPSIS

Each column name is displayed in its own line, then the contents of that column,
then the next column and next record. Nothing is escaped.

    object_id
        1

    object_tp
        Property

    name
        Test property by rent.com


=head1 AUTHOR

Ripta Pasay <rpasay@rent.com>

=cut
