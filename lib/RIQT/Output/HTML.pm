package RIQT::Output::HTML;

use Moo;

with 'RIQT::Output';

sub BUILD {
    my ($self) = @_;
    $self->println(q{<html><body>});
}

sub DEMOLISH {
    my ($self, $is_global) = @_;
    $self->println(q{</body></html>});
}

sub _escape {
    my ($self, $value) = @_;
    return $value;
}

sub start {
    my ($self, $fields) = @_;

    $self->println(q{<table>});
    $self->println('    <tr>');
    foreach my $field (@$fields) {
        $self->println('        <th>' . $self->_escape($field->{'name'}) . '</th>');
    }
    $self->println('    </tr>');
}

sub finish {
    my ($self) = @_;
    $self->println(q{</table>});
}

sub record {
    my ($self, $values) = @_;

    $self->println(q{    <tr>});
    foreach my $idx (0..$#$values) {
        $self->print('        <td>');
        if (defined $values->[$idx]) {
            $self->print($self->_escape($values->[$idx]));
        } else {
            $self->print('<em>(null)</em>');
        }
        $self->println('</td>');
    }
    $self->println(q{    </tr>});
}

1;
