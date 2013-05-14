package Rent::PIQT::Output::TSV;

use Moo;
use String::Escape qw/backslash/;

with 'Rent::PIQT::Output';


sub start {
    my ($self, $fields) = @_;
    $self->out->print(join("\t", map { backslash($_{'name'}) } @$fields) . "\n");
}

sub finish {
    my ($self) = @_;
    # NOOP
}

sub record {
    my ($self, $values) = @_;
    $self->out->print(join("\t", map { backslash($_) } @$values) . "\n");
}

1;
