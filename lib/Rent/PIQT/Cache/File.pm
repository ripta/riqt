package Rent::PIQT::Cache::File;

use Moo;
use Storable qw/nstore retrieve/;

extends 'Rent::PIQT::Cache';

has 'filename' => (is => 'rw', required => 1);

sub BUILD {
    my ($self) = @_;

    if (-e $self->filename) {
        $self->{'kv'} = eval { retrieve $self->filename };
        if ($@) {
            warn sprintf("Cannot load cache from %s: %s\n",
                $self->filename,
                $@,
            );
            $self->{'kv'} = {};
        }
    } else {
        $self->{'kv'} = {};
    }
    # print "Loaded Cache::File (", join(', ', keys %{$self->{'kv'}}), ")\n";
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

around save => sub {
    my ($orig, $self) = @_;
    $self->$orig;
    nstore $self->{'kv'}, $self->filename if $self->{'kv'};
    # print "Saved (", join(', ', keys %{$self->{'kv'}}), ") into ", $self->filename, "\n";
};

1;
