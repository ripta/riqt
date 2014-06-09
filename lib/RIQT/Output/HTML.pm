package RIQT::Output::HTML;

use Data::Dumper;
use HTML::Entities;
use Moo;

with 'RIQT::Output';

has fields => (is => 'rw');

sub BUILD {
    my ($self) = @_;
    1;
}

sub DEMOLISH {
    my ($self, $is_global) = @_;
    1;
}

sub _escape {
    my ($self, $value) = @_;
    return encode_entities($value);
}

sub colorize {
    my ($self, $msg, $color) = @_;
    return $msg;
}

sub start {
    my ($self, $fields) = @_;
    $self->fields($fields);

    # $self->println('<pre>' . Dumper($fields) . '</pre>');
    $self->println(q{<table>});
    $self->println('    <tr>');
    foreach my $field (@$fields) {
        $self->println('        <th class="sql-type-' . $field->{'type'} . '"><span class="sql-key-name">' . $self->_escape($field->{'name'}) . '</span></th>');
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
        $self->print('        <td class="sql-type-' . $self->fields->[$idx]->{'type'} . '">');
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
