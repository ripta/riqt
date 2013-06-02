package Rent::PIQT::Plugin::DescribeObject;

use Moo;

with 'Rent::PIQT::Plugin';

sub BUILD {
    my ($self) = @_;

    $self->controller->register('desc', 'describe',
        sub {
            my ($ctrl, $object_name) = @_;
            $ctrl->db->describe_object($object_name);
            return 1;
        },
    );
}

1;
