package Rent::PIQT::Output::XML;

use Moo;

with 'Rent::PIQT::Output';

has 'field_names', (is => 'rw');

sub _escape_name {
    my ($self, $name) = @_;
    $name =~ s/[^0-9A-Za-z-]/-/g;
    $name = 'x' . $name if $name =~ /^[^A-Za-z_]/;
    return $name;
}

sub _escape_value {
    my ($self, $value) = @_;
    $value =~ s/&/&amp;/g;
    $value =~ s/"/&quot;/g;
    $value =~ s/'/&apos;/g;
    $value =~ s/</&lt;/g;
    $value =~ s/>/&gt;/g;
    return $value;
}

sub start {
    my ($self, $fields) = @_;

    $self->field_names([ map { $self->_escape_name($_->{'name'}) } @$fields ]);
    $self->println(q{<?xml version="1.0" encoding="UTF-8" ?>});
    $self->print(q{<records>});
}

sub finish {
    my ($self) = @_;
    $self->print(q{</records>});
}

sub record {
    my ($self, $values) = @_;
    my $names = $self->field_names;

    $self->print('<record>');
    foreach my $idx (0..$#$values) {
        if (defined $values->[$idx]) {
            $self->printf('<%s>%s</%s>',
                $names->[$idx],
                $self->_escape_value($values->[$idx]),
                $names->[$idx]
            );
        } else {
            $self->printf('<%s/>', $names->[$idx]);
        }
    }
    $self->print('</record>');
}

1;
