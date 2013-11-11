package RIQT::Output::Vertical;

use Moo;

with 'RIQT::Output';


sub start {
    my ($self, $fields) = @_;

    my $max_length = 0;
    foreach my $field (@$fields) {
        $max_length = length($field->{'name'}) if length($field->{'name'}) > $max_length;
    }
    $self->{'_fmt'} = '%-' . $max_length . 's' . " %-s\n";

    $self->{'_fields'} = $fields;
}

sub finish {
    my ($self) = @_;
    # NOOP
}

sub record {
    my ($self, $values) = @_;
    my $fields = $self->{'_fields'};

    foreach my $idx (0..$#$fields) {
        my $field = $fields->[$idx];
        my $value = $values->[$idx];

        $self->printf($self->{'_fmt'}, $field->{'name'}, defined($value) ? $value : '(null)');
    }
    $self->println;
}

1;

=head1 NAME

RIQT::Output::Vertical - Vertical output driver for RIQT

=head1 SYNOPSIS

Each record is printed in its own block. Each field is printed on its own line.

    object_id   1
    object_tp   Property
    name        Test property by rent.com

=head1 AUTHOR

Ripta Pasay <rpasay@rent.com>

=cut
