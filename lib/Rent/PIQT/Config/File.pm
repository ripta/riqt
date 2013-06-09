package Rent::PIQT::Config::File;

use Moo;

extends 'Rent::PIQT::Config';

has 'filename' => (is => 'rw', required => 1);

# Transform File->new($filename) into File->new(filename => $filename) after
# massaging the filename into something more useful.
sub BUILDARGS {
    my ($class, $filename) = @_;

    # Trust the filename if the file already exists as-is, or if it's an
    # absolute pathname
    return { filename => $filename } if -e $filename;
    return { filename => $filename } if $filename =~ m#^/#;

    # Expand ~ to the home directory if one exists
    return { filename => $filename } if $filename =~ s#~/#$ENV{'HOME'} . '/'#e && defined($ENV{'HOME'});

    # Relative names should be constructed against the home directory
    return { filename => $ENV{'HOME'} . '/' . $filename } if defined($ENV{'HOME'});
    return { filename => "/home/" . $ENV{'LOGNAME'} . "/" . $filename } if defined($ENV{'LOGNAME'});
    return { filename => "/home/" . $ENV{'USER'} . "/" . $filename } if defined($ENV{'USER'});

    # Last-resort fallback
    return {
        filename => $filename
    };
}

# Save out the configuration file upon exit, if the configuration has been
# modified during the session.
sub DEMOLISH {
    my ($self) = @_;
    return 1 unless $self->is_modified;

    open my $fh, '>', $self->filename or do {
        warn "Cannot save configuration into " . $self->filename . ": " . $!;
        return;
    };

    # Output the configuration lines
    print { $fh } "# Last-Modified: " . time() . "\n";
    foreach my $key (sort keys %{$self->{'kv'}}) {
        printf { $fh } "SET %s %s\n", $key, $self->{'kv'}->{$key};
        $self->controller->output->debugf("SET %s %s", $key, $self->{'kv'}->{$key}) if $self->controller;
    }

    close $fh;
    return 1;
}

# During POSTBUILD phase, any existing configuration files should be loaded
# into memory.
around POSTBUILD => sub {
    my ($orig, $self, @args) = @_;

    # Output a warning if the configuration file doesn't exist
    unless (-e $self->filename) {
        $self->controller->output->warnf("Configuration file '%s' does not exist.", $self->filename);
        $self->controller->output->warnf("One will be created automatically upon exiting.");
        $self->is_modified(1);
        return;
    }

    open(my $fh, $self->filename) or do {
        $self->controller->output->errorf("Cannot open '%s': %s", $self->filename, $!);
        return;
    };

    # Process the configuration file, looking for lines starting with 'SET'
    # The $self->controller->execute cannot be called here, because POSTBUILD
    # in the base config needs to run after settings are loaded, but that's
    # where internal commands are usually registered
    my $lineno = 0;
    while (my $line = <$fh>) {
        $lineno++;
        chomp $line;

        next if $line =~ m{^\s*#};

        if ($line =~ m{^\s*SET\s+(\S+)\s+(.+?)(\#.*)?$}i) {
            $self->$1($2);
            next;
        }

        $self->controller->output->warnf(
            "Unknown command '%s' in %s line %d; ignoring",
            $line,
            $self->filename,
            $lineno,
        );
    }

    $self->$orig(@args);
};


1;
