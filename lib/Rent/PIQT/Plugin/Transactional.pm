package Rent::PIQT::Plugin::Transactional;

use Moo;

with 'Rent::PIQT::Plugin';

sub BUILD {
    my ($self) = @_;

    $self->controller->register('commit', 'commit;',
        sub {
            my ($ctrl) = @_;
            if ($ctrl->db->commit) {
                $ctrl->output->ok('Transaction committed');
            } else {
                $ctrl->output->errorf('Transaction could not be committed: %s',
                    $ctrl->db->last_error,
                );
            }
        },
    );

    $self->controller->register('rollback', 'rollback;',
        sub {
            my ($ctrl) = @_;
            if ($ctrl->db->rollback) {
                $ctrl->output->ok('Transaction rolled back');
            } else {
                $ctrl->output->errorf('Transaction could not be rolled back: %s',
                    $ctrl->db->last_error,
                );
            }
        },
    );
}

1;
