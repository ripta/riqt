package Rent::PIQT::Plugin::Print;

use Moo;

with 'Rent::PIQT::Plugin';

sub BUILD {
    my ($self) = @_;

    $self->controller->register('print',
        sub {
            my ($ctrl, $args) = @_;
            $ctrl->output->println(unquote_or_die($args));
            return 1;
        },
    );
}

1;
