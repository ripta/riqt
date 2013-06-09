package Rent::PIQT::Plugin::EditQuery;

use File::Temp qw/tempfile/;
use Moo;

with 'Rent::PIQT::Plugin';

sub BUILD {
    my ($self) = @_;

    $self->controller->register('\e',
        sub {
            my ($ctrl, $args) = @_;

            my $editor = $ctrl->config->editor || $ENV{'EDITOR'} || do {
                $ctrl->output->errorf("Neither the 'editor' config or the EDITOR environment variable is set.");
                $ctrl->output->errorf("You'll need to issue 'SET EDITOR <path-to-editor>', or set your environment variable.");
                return 1;
            };

            if (my $query = $ctrl->db->last_query) {
                my ($fh, $fname) = tempfile();
                print $fh $query;
                print $fh ';' unless $query =~ /;$/;
                close $fh;

                system("$editor $fname");

                open $fh, $fname or do {
                    $ctrl->output->errorf(
                        "Cannot re-open temporary file %s for reading",
                        quote($fname),
                    );
                    return 1;
                };

                local $/ = undef;
                $query = <$fh>;
                close $fh;

                $ctrl->run_query($query) if $query;
            } else {
                $ctrl->output->error("There is no previous query to edit.");
            }

            return 1;
        },
    );
}

1;
