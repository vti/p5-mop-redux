package mop::traits;

use v5.16;
use warnings;

our $VERSION   = '0.01';
our $AUTHORITY = 'cpan:STEVAN';

our @AVAILABLE_TRAITS = qw[
    rw
    ro
    required
    weak_ref
    lazy
    abstract
    overload
    extending_non_mop
    repr
];

sub rw {
    my ($attr) = @_;

    die "rw trait is only valid on attributes"
        unless $attr->isa('mop::attribute');

    my $meta = $attr->associated_meta;
    $meta->add_method(
        $meta->method_class->new(
            name => $attr->key_name,
            body => sub {
                my $self = shift;
                $attr->store_data_in_slot_for($self, shift) if @_;
                $attr->fetch_data_in_slot_for($self);
            }
        )
    );
}

sub ro {
    my ($attr) = @_;

    die "ro trait is only valid on attributes"
        unless $attr->isa('mop::attribute');

    my $meta = $attr->associated_meta;
    $meta->add_method(
        $meta->method_class->new(
            name => $attr->key_name,
            body => sub {
                my $self = shift;
                die "Cannot assign to a read-only accessor" if @_;
                $attr->fetch_data_in_slot_for($self);
            }
        )
    );
}

sub required {
    my ($attr) = @_;

    die "required trait is only valid on attributes"
        unless $attr->isa('mop::attribute');

    die "in '" . $attr->name . "' attribute definition: "
      . "'required' trait is incompatible with default value"
        if $attr->has_default;

    $attr->set_default(sub { die "'" . $attr->name . "' is required" });
}

sub abstract {
    my ($class) = @_;

    die "abstract trait is only valid on classes"
        unless $class->isa('mop::class');

    $class->make_class_abstract;
}

sub overload {
    my ($method, $operator) = @_;

    die "overload trait is only valid on methods"
        unless $method->isa('mop::method');

    my $method_name = $method->name;

    # NOTE:
    # This installs the methods into the package
    # directly, rather than going through the
    # mop. This is because overload methods
    # (with their weird names) should probably
    # not show up in the list of methods and such.

    overload::OVERLOAD(
        $method->associated_meta->name,
        $operator,
        sub {
            my $self = shift;
            $self->$method_name(@_)
        },
        fallback => 1
    );
}

sub weak_ref {
    my ($attr) = @_;

    die "weak_ref trait is only valid on attributes"
        unless $attr->isa('mop::attribute');

    $attr->bind('after:STORE_DATA' => sub {
        my (undef, $instance) = @_;
        $attr->weaken_data_in_slot_for($instance);
    });
}

sub lazy {
    my ($attr) = @_;

    die "lazy trait is only valid on attributes"
        unless $attr->isa('mop::attribute');

    my $default = $attr->clear_default;
    $attr->bind('before:FETCH_DATA' => sub {
        my (undef, $instance) = @_;
        if ( !$attr->has_data_in_slot_for($instance) ) {
            $attr->store_data_in_slot_for($instance, do {
                local $_ = $instance;
                $default->()
            });
        }
    });
}

sub extending_non_mop {
    my ($class, $constructor_name) = @_;

    die "extending_non_mop trait is only valid on classes"
        unless $class->isa('mop::class');

    state $BUILDALL = mop::meta('mop::object')->get_method('BUILDALL');

    $constructor_name //= 'new';
    my $super_constructor = join '::' => $class->superclass, $constructor_name;

    $class->add_method(
        $class->method_class->new(
            name => $constructor_name,
            body => sub {
                my $class = shift;
                my $self  = $class->$super_constructor( @_ );
                mop::internals::util::register_object( $self );

                my %attributes = map {
                    if (my $m = mop::meta($_)) {
                        %{ $m->attribute_map }
                    }
                    else {
                        ()
                    }
                } reverse @{ mro::get_linear_isa($class) };

                foreach my $attr (values %attributes) {
                    $attr->store_default_in_slot_for( $self );
                }

                $BUILDALL->execute( $self, [ @_ ] );
                $self;
            }
        )
    );
}

sub repr {
    my ($class, $instance) = @_;

    die "repr trait is only valid on classes"
        unless $class->isa('mop::class');

    my $generator;
    if (ref $instance && ref $instance eq 'CODE') {
        $generator = $instance;
    }
    elsif (!ref $instance) {
        if ($instance eq 'SCALAR') {
            $generator = sub { \(my $anon) };
        }
        elsif ($instance eq 'ARRAY') {
            $generator = sub { [] };
        }
        elsif ($instance eq 'HASH') {
            $generator = sub { {} };
        }
        elsif ($instance eq 'GLOB') {
            $generator = sub { select select my $fh; %{*$fh} = (); $fh };
        }
        else {
            die "unknown instance generator type $instance";
        }
    }
    else {
        die "unknown instance generator $instance";
    }

    $class->set_instance_generator($generator);
}

1;

__END__

=pod

=head1 NAME

mop::traits - collection of traits for the mop

=head1 DESCRIPTION

=head1 BUGS

All complex software has bugs lurking in it, and this module is no
exception. If you find a bug please either email me, or add the bug
to cpan-RT.

=head1 AUTHOR

Stevan Little <stevan@iinteractive.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2013 by Infinity Interactive.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut



