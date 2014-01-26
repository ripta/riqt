package RIQT::Output::HTML;

use HTML::Entities;
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
    return encode_entities($value);
}

sub start {
    my ($self, $fields) = @_;

    $self->println(q{<table>});
    $self->println('    <tr>');
    foreach my $field (@$fields) {
        $self->println('        <th><span class="sql-key-name">' . $self->_escape($field->{'name'}) . '</span></th>');
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
            my $escaped = $self->_escape($values->[$idx]);
            if ($escaped eq $values->[$idx]) {
                $self->print('<span class="sql-value-raw">' . $escaped . '</span>');
            } else {
                $self->print('<span class="sql-value-escaped">' . $escaped . '</span>');
            }
        } else {
            $self->print('<span class="sql-value-null">(null)</span>');
        }
        $self->println('</td>');
    }
    $self->println(q{    </tr>});
}

1;
