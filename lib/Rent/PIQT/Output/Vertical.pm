package Rent::PIQT::Output::Vertical;

use Moo;

with 'Rent::PIQT::Output';


sub start {
    my ($self, $fields) = @_;

    my $max_length = 0;
    foreach my $field (@$fields) {
        $max_length = length($field->{'name'}) if length($field->{'name'}) > $max_length;
    }
    $self->{'_fmt'} = '%' . $max_length . 's' . "\n";

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

        $self->out->print($self->{'_fmt'}, $field->{'name'}, $value);
    }
}

1;
