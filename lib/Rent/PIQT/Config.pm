package Rent::PIQT::Config;

use Moo;

with 'Rent::PIQT::Component';

sub AUTOLOAD {
    my ($self, @args) = @_;

    our $AUTOLOAD;
    my $name = lc $AUTOLOAD;    # Normalize the method name by lower-casing it,
    $name =~ s/.*:://;          # and removing its package

    if (scalar(@args) == 0) {
        return exists($self->{'kv'}->{$name}) ? $self->{'kv'}->{$name} : undef;
    } elsif (scalar(@args) == 1) {
        my $value = $args[0];
        if (uc $value eq 'ON') {
            $value = 1;
        } elsif (uc $value eq 'OFF') {
            $value = 0;
        }

        if (exists $self->{'hooks'}->{$name} && ref $self->{'hooks'}->{$name} eq 'ARRAY') {
            foreach my $hook (@{ $self->{'hooks'}->{$name} }) {
                $hook->(
                    $self,
                    $name,
                    exists($self->{'kv'}->{$name}) ? $self->{'kv'}->{$name} : undef,
                    $value,
                );
            }
        }

        $self->{'kv'}->{$name} = $value;
        return 1;
    } else {
        $self->controller->output->errorf(
            "Multiple (%d) values were provided for configuration parameter '%s'",
            scalar(@args),
            $name,
        );
    }
}

sub BUILD {
    my ($self) = @_;

    $self->{'kv'}    ||= { };
    $self->{'hooks'} ||= { };
}

sub KEYS {
    my ($self) = @_;
    die ref($self) . "->KEYS must be called in array context" unless wantarray;
    return keys %{$self->{'kv'}} if $self->{'kv'};
    return ();
}

sub POSTBUILD {
    my ($self) = @_;

    $self->controller->register('set',
        sub {
            my ($self, $name, $value) = @_;
            if (defined $value) {
                $name = lc $name;
                $name =~ s/\s/_/g;

                $self->output->info("SET $name $value");
                $self->config->$name($value);
            } else {
                $self->output->errorf("'SET %s' requires a value", $name);
            }

            return 1;
        }
    );

    $self->controller->register('show',
        sub {
            my ($self, $name) = @_;
            my $c = $self->config;
            my $o = $self->output;

            $o->start(
                [
                    {name => "Name",  type => "string", length => 255},
                    {name => "Value", type => "string", length => 4000},
                ]
            );
            if (defined $name) {
                if (my $value = $c->$name) {
                    $o->record([$name, $value]);
                } else {
                    $o->record([$name, undef]);
                }
            } else {
                foreach my $key (sort $c->KEYS) {
                    $o->record([$key, $c->$key]);
                }
            }
            $o->finish;

            return 1;
        }
    );
}

sub register {
    my ($self, $command, $hook) = @_;
    $command = lc $command;

    $self->{'hooks'}->{$command} ||= [ ];
    push @{ $self->{'hooks'}->{$command} }, $hook;
}

1;
