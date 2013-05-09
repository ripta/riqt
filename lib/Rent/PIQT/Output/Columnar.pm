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
