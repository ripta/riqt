package Rent::PIQT::Config;

use Moo::Role;

with 'Rent::PIQT::Component';

requires qw/load save/;


sub AUTOLOAD {
    my ($self, @args) = @_;

    our $AUTOLOAD;
    my $name = $AUTOLOAD;
    $name =~ s/.*:://;

    $self->{'_'} ||= { };

    if (scalar(@args) == 0) {
        return $self->{'_'}->{$name} && ref($self->{'_'}->{$name}) eq 'ARRAY'
            ? wantarray
                ? @{$self->{'_'}->{$name}}
                : $self->{'_'}->{$name}->[0]
            : wantarray
                ? ()
                : undef;
    } else {
        if ($self->controller) {
            $self->controller->output->debug("SET $name " . join(' ', @args));
        }

        $self->{'_'}->{$name} = \@args;
        return 1;
    }
}


1;
