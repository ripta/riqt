package Rent::PIQT::Config;

use Moo;

with 'Rent::PIQT::Component';

has 'is_modified' => (is => 'rw', 'default' => 0);

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

        if (exists($self->{'kv'}->{$name})) {
            return if $self->{'kv'}->{$name} eq $value;
        }

        my @hook_args = (
            $self,
            $name,
            exists($self->{'kv'}->{$name}) ? $self->{'kv'}->{$name} : undef,
            $value,
        );

        if (exists $self->{'hooks'}->{$name} && ref $self->{'hooks'}->{$name} eq 'ARRAY') {
            foreach my $hook (@{ $self->{'hooks'}->{$name} }) {
                $hook->(@hook_args);
            }
        } else {
            $self->{'pending_hooks'}->{$name} = \@hook_args;
        }

        $self->{'kv'}->{$name} = $value;
        $self->is_modified(1);
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

    $self->{'kv'}               ||= { };
    $self->{'hooks'}            ||= { };
    $self->{'pending_hooks'}    ||= { };
}

sub KEYS {
    my ($self) = @_;
    die ref($self) . "->KEYS must be called in array context" unless wantarray;
    return keys %{$self->{'kv'}} if $self->{'kv'};
    return ();
}

sub POSTBUILD {
    my ($self) = @_;
    $self->run_pending_hooks;

    $self->controller->register('set',
        sub {
            my ($self, $arg) = @_;
            my ($name, $value) = split /\s+/, $arg, 2;

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
            if ($name) {
                if (my $value = $c->$name) {
                    $o->record([$name, $value]);
                } else {
                    foreach my $key (sort $c->KEYS) {
                        $o->record([$key, $c->$key]) if $key =~ /$name/i;
                    }
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

    die "Hook for config setting '$command' cannot be empty" unless $hook;

    unless (ref $hook eq 'CODE') {
        $hook = sub {
            die "Read-only: the config setting '$command' cannot be modified from the console";
        };
        delete $self->{'pending_hooks'}->{$command};
    }

    $self->{'hooks'}->{$command} ||= [ ];
    push @{ $self->{'hooks'}->{$command} }, $hook;

    $self->run_pending_hooks;
}

sub run_pending_hooks {
    my ($self) = @_;

    foreach my $name (keys %{$self->{'pending_hooks'}}) {
        my $args = $self->{'pending_hooks'}->{$name};
        if (exists $self->{'hooks'}->{$name} && ref $self->{'hooks'}->{$name} eq 'ARRAY') {
            $self->controller->output->debugf("Running %s for %s",
                pluralize(scalar(@{ $self->{'hooks'}->{$name} }), 'pending hook', 'pending hooks'),
                quote($name),
            );
            foreach my $hook (@{ $self->{'hooks'}->{$name} }) {
                $hook->(@$args);
            }

            delete $self->{'pending_hooks'}->{$name};
        }
    }

    return 1;
}

1;
