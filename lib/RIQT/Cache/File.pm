package RIQT::Cache::File;

use Moo;

use File::Copy;
use Storable qw/nstore retrieve/;

extends 'RIQT::Cache';

has 'filename' => (is => 'rw', required => 1);

sub BUILD {
    my ($self) = @_;

    # Try the regular cache file
    if (-e $self->filename) {
        $self->{'kv'} = eval { retrieve $self->filename };

        if ($@) {
            # Try a backup file if one exists
            if (-e $self->backup_filename) {
                $self->{'kv'} = eval { retrieve $self->backup_filename };

                if ($@) {
                    warn sprintf("Cannot load cache from %s: %s\n",
                        $self->backup_filename,
                        $@,
                    );
                    $self->{'kv'} = {};
                }
            } else {
                warn sprintf("Cannot load cache from %s: %s\n",
                    $self->filename,
                    $@,
                );
                $self->{'kv'} = {};
            }
        }
    } else {
        $self->{'kv'} = {};
    }
};

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

around POSTBUILD => sub {
    my ($orig, $self) = @_;
    $self->$orig;
    $self->controller->config->cache_device($self->filename);
    $self->controller->config->register('cache_device',
        write => 0,
        persist => 0
    );
};

around save => sub {
    my ($orig, $self) = @_;

    # Call the original method first, in case it needs to do clean up
    $self->$orig;

    # Bail out if there's nothing to save
    return 1 unless $self->{'kv'};

    # If a config already exists, back it up first before overwriting
    if (-e $self->filename) {
        # Delete backup if one exists
        if (-e $self->backup_filename) {
            unlink $self->backup_filename or do {
                warn "Could not unlink " . $self->backup_filename . ": $!";
                return 0;
            };
        }

        # Copy the original to the backup
        unless (copy($self->filename, $self->backup_filename)) {
            warn "Could not create a backup of " . $self->filename . ": $!";
            return 0;
        }
    }

    # Save the new file, overwriting if one already exists
    nstore $self->{'kv'}, $self->filename if $self->{'kv'};
    return 1;
};

sub backup_filename {
    return $_[0]->filename . '.bak';
}

1;
