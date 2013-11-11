package Rent::PIQT::Plugin::EditQuery;

use File::Temp qw/tempfile/;
use Moo;

our $VERSION = '1.0.0';

with 'Rent::PIQT::Plugin';

sub BUILD {
    my ($self) = @_;

    $self->controller->register('\e', 'ed', 'vi', {
        signature => [
            '%s',
            '%s <filename>',
        ],
        help => q{
            Edit the last query in the buffer in your favorite editor, and run
            it.  Deleting the query in the buffer will cause nothing to be run,
            and the buffer to remain unchanged. Only one query at a time can be
            edited this way.

            If a <filename> was specified, the file will be edited directly,
            and then executed as an external script. After execution, the buffer
            will contain the last query executed in the file.

            The default editor is selected based on your EDITOR environment
            variable. If the EDITOR configuration variable is set, that value
            is used instead.
        },
        code => sub {
            my ($ctrl, $filename) = @_;
            my $c = $ctrl->config;
            my $o = $ctrl->output;

            my $editor = $c->editor || $ENV{'EDITOR'} || do {
                $o->errorf("Neither the 'editor' config or the EDITOR environment variable is set.");
                $o->errorf("You'll need to issue 'SET EDITOR <path-to-editor>', or set your environment variable.");
                return 1;
            };

            if ($filename) {
                system("$editor $filename");
                $ctrl->run_file($filename);
            } else {
                my $placeholder = "-- No previous query to edit. Replace this with your query.\n";
                my $query = $ctrl->db->last_query;
                if ($query) {
                    $query .= ';' unless $query =~ /;$/;
                } else {
                    $query = $placeholder;
                }

                my ($fh, $fname) = tempfile();
                print $fh $query;
                close $fh;

                system("$editor $fname");

                open $fh, $fname or do {
                    $o->errorf(
                        "Cannot re-open temporary file %s for reading",
                        quote($fname),
                    );
                    return 1;
                };

                local $/ = undef;
                $query = <$fh>;
                close $fh;

                if ($query) {
                    if ($query eq $placeholder) {
                        $o->warnf("Query placeholder was not overwritten.");
                    } else {
                        $ctrl->run_query($query);
                    }
                } else {
                    $o->warnf("No query to run.");
                }
            }

            return 1;
        },
    });
}

1;