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
        if (uc $value eq 'ON' || uc $value eq 'YES') {
            $value = 1;
        } elsif (uc $value eq 'OFF' || uc $value eq 'NO') {
            $value = 0;
        }

        if (exists($self->{'kv'}->{$name})) {
            return if $self->{'kv'}->{$name} eq $value;

            unless ($self->options_for($name, 'write')) {
                die "Read-only: configuration '$name' cannot be written to";
            }
        }

        my @hook_args = (
            $self,
            $name,
            exists($self->{'kv'}->{$name}) ? $self->{'kv'}->{$name} : undef,
            $value,
        );
        $self->controller->output->debugf("Setting config value for %s to %s with hook arguments: %s",
            quote(printable($name)),
            quote(printable($value)),
            '(' . join(", ", map { quote(printable($_)) } @hook_args) . ')',
        );

        $self->{'pending_hooks'}->{$name} = \@hook_args;
        $self->run_pending_hooks;

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

    $self->{'opts'}     ||= { };
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

    $self->is_modified(0);
    $self->run_pending_hooks;

    $self->controller->register('set', {
        signature => '%s <name> <value>',
        help => q{
            Set a configuration parameter <name> to the value <value>. The <name> parameter
            is case-insensitive, but the <value> is case-sensitive.

            The value can be specified as-is for simple values, e.g.:

                SET ECHO ON
                SET VERBOSE 4

            while complex values containing whitespace must be single-quoted, e.g.:

                SET date_format 'YYYY-MM-DD HH24:MI:SS'
        },
        code => sub {
            my ($ctrl, $name, $value, @rest) = @_;
            die "Configuration variable <name> is required." unless $name;

            my $o = $ctrl->output;

            if (@rest) {
                $o->errorf("Invalid <value> for parameter %s:\n\t%s",
                    quote($name),
                    "Is the <value> a string that contains whitespaces? See 'HELP SET'.",
                );
            } elsif (defined $value) {
                $name = lc $name;
                $name =~ s/\s/_/g;

                my $clean_value = normalize_single_quoted($value);
                $o->info("SET $name $value");
                $self->$name($clean_value);
            } else {
                $o->errorf("'SET %s' requires a value", $name);
            }

            return 1;
        }
    });

    $self->controller->register('show',
        sub {
            my ($self, $name) = @_;
            my $c = $self->config;
            my $o = $self->output;
            my $rows = 0;

            $o->start_timing;
            $o->start(
                [
                    {name => "Name",  type => "str", length => 255},
                    {name => "Modes", type => "str", length => 3},
                    {name => "Readable", type => "bool", length => 1},
                    {name => "Writeable", type => "bool", length => 1},
                    {name => "Persistable", type => "bool", length => 1},
                    {name => "Value", type => "str", length => 4000},
                ]
            );
            if ($name) {
                if (my $value = $c->$name) {
                    my $opts = $c->options_for($name);
                    $o->record([$name, $opts->{'only'}, $opts->{'read'}, $opts->{'write'}, $opts->{'persist'}, $value]);
                    $rows++;
                } else {
                    foreach my $key (sort $c->KEYS) {
                        next unless $key =~ /\Q$name\E/i;
                        $rows++;

                        my $opts = $c->options_for($key);
                        $o->record([$key, $opts->{'only'}, $opts->{'read'}, $opts->{'write'}, $opts->{'persist'}, $c->$key]);
                    }
                }
            } else {
                foreach my $key (sort $c->KEYS) {
                    $rows++;

                    my $opts = $c->options_for($key);
                    $o->record([$key, $opts->{'only'}, $opts->{'read'}, $opts->{'write'}, $opts->{'persist'}, $c->$key]);
                }
            }
            $o->finish;
            $o->finish_timing($rows);

            return 1;
        }
    );
}

sub options_for {
    my ($self, $name, $key) = @_;
    $name = lc $name;

    my $opts = exists $self->{'opts'}->{$name} ? $self->{'opts'}->{$name} : {};

    $opts->{'catch_up'} = 1 unless exists $opts->{'catch_up'};
    $opts->{'only'}   ||= 'fio';
    $opts->{'persist'}  = 1 unless exists $opts->{'persist'};
    $opts->{'read'}     = 1 unless exists $opts->{'read'};
    $opts->{'write'}    = 1 unless exists $opts->{'write'};

    return $key ? $opts->{$key} : { %$opts };
}

# register($command, $hook);
# register($command, hook => $hook, only => 'fio');
# where 'fio' = 'file', 'interactive', and 'one-off'
sub register {
    my ($self, @args) = @_;
    my $command = lc shift @args;
    my $hook    = undef;
    my %opts    = ();

    @args = @{$args[0]} if ref $args[0] eq 'ARRAY';
    $hook = shift @args if ref $args[0] eq 'CODE';

    if (scalar(@args) % 2 == 0) {
        %opts = @args;
        if (exists $opts{'hook'}) {
            die "Cannot specify both a CODEREF and 'hook' option for config setting '$command'" if $hook;
            $hook = delete $opts{'hook'};
        }
    }

    my ($c_pkg, $c_file, $c_line) = caller;
    $self->{'opts'}->{$command} = {
        %opts,
        caller_package  => $c_pkg,
        caller_file     => $c_file,
        caller_line     => $c_line,
    };

    return unless $hook;

    $self->controller->output->debugf("Registering config hook for %s => %s with options (%s)",
        quote($command),
        $hook,
        join(", ", map { $_ . ' => ' . $opts{$_} } sort keys %opts),
    );

    $self->{'hooks'}->{$command} ||= [ ];
    push @{ $self->{'hooks'}->{$command} }, $hook;

    $self->run_pending_hooks;
}

sub run_pending_hooks {
    my ($self) = @_;

    foreach my $name (keys %{$self->{'pending_hooks'}}) {
        unless ($self->options_for($name, 'catch_up')) {
            $self->controller->output->debugf("Skipping pending config hooks for %s (catch_up => 0)",
                quote($name),
            );
            return;
        }

        if (exists $self->{'hooks'}->{$name} && ref $self->{'hooks'}->{$name} eq 'ARRAY') {
            $self->controller->output->debugf("Running %s for %s",
                pluralize(scalar(@{ $self->{'hooks'}->{$name} }), 'pending config hook', 'pending config hooks'),
                quote($name),
            );

            my $args = delete $self->{'pending_hooks'}->{$name};
            foreach my $hook (@{ $self->{'hooks'}->{$name} }) {
                $hook->(@$args);
            }
        }
    }

    return 1;
}

1;
