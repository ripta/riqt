package Rent::PIQT::Output::JSON;

use Moo;
use String::Escape qw/qqbackslash/;

with 'Rent::PIQT::Output';

has 'field_names', (is => 'rw');
has 'record_number', (is => 'rw');

sub start {
    my ($self, $fields) = @_;

    $self->field_names([ map { $_->{'name'} } @$fields ]);
    $self->record_number(0);
    $self->print('{"records":[');
}

sub finish {
    my ($self) = @_;
    $self->print(']}');
}

sub record {
    my ($self, $values) = @_;
    my $names = $self->field_names;

    $self->print(',') if $self->record_number > 0;
    $self->record_number($self->record_number + 1);

    $self->print('{');
    foreach my $idx (0..$#$values) {
        $self->print(',') if $idx > 0;
        $self->print(qqbackslash($names->[$idx]) . ':');
        if (defined $values->[$idx]) {
            $self->print(qqbackslash($values->[$idx]));
        } else {
            $self->print('null');
        }
    }
    $self->print('}');
}

1;
