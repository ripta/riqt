package RIQT::Output::HTML;

use Moo;

with 'RIQT::Output';

sub _escape {
    my ($self, $value) = @_;
    return $value;
}

sub start {
    my ($self, $fields) = @_;

    $self->println(q{<html><body>});
    $self->println(q{<table>});
    $self->print('<tr><th>');
    $self->print(join '</th><th>', map { $self->_escape($_->{'name'}) } @$fields);
    $self->print('</th></tr>');
}

sub finish {
    my ($self) = @_;
    $self->println(q{</table></body></html>});
}

sub record {
    my ($self, $values) = @_;

    $self->println(q{<tr>});
    foreach my $idx (0..$#$values) {
        $self->print('<td>');
        if (defined $values->[$idx]) {
            $self->print($self->_escape($values->[$idx]));
        } else {
            $self->print('<em>(null)</em>');
        }
        $self->print('</td>');
    }
    $self->println(q{</tr>});
}

1;
