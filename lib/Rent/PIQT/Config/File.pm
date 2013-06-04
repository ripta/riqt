package Rent::PIQT::Config::File;

use Moo;

extends 'Rent::PIQT::Config';

has 'filename' => (is => 'rw', required => 1);

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

sub DEMOLISH {
    my ($self) = @_;
    return 1 unless $self->is_modified;

    open my $fh, $self->filename or do {
        warn "Cannot save configuration into " . $self->filename . ": " . $!;
        return;
    };

    print { $fh } "# Last-Modified: " . time() . "\n";
    foreach my $key (keys %{$self->{'kv'}}) {
        printf { $fh } "SET %s %s\n", $key, $self->{'kv'}->{$key};
        $self->controller->output->debugf("SET %s %s", $key, $self->{'kv'}->{$key}) if $self->controller;
    }

    close $fh;
    return 1;
}

around POSTBUILD => sub {
    my ($orig, $self) = (shift, shift);
    $self->$orig(@_);

    unless (-e $self->filename) {
        $self->controller->output->warnf("Configuration file '%s' does not exist.", $self->filename);
        $self->controller->output->warnf("One will be created automatically upon exiting.");
        return;
    }

    open(my $fh, $self->filename) or do {
        $self->controller->output->errorf("Cannot open '%s': %s", $self->filename, $!);
        return;
    };

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
            "Unknown command '%s' in %s line %d",
            $line,
            $self->filename,
            $lineno,
        );
    }
};


1;
