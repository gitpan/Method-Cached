package Method::Cached::KeyRule;

use strict;
use warnings;
use Digest::SHA;
use JSON::XS;
use Storable;
use Scalar::Util;

{
    no strict 'refs';

    sub regularize {
        my $key_rule = shift;
        my $ref = ref $key_rule;
        $ref || return &{$key_rule || 'LIST'}(@_);
        $ref eq 'CODE' && return $key_rule->(@_);
        my $key;
        for my $rule (@{$key_rule}) {
            $key = ref $rule ? $rule->(@_) : &{$rule}(@_);
        }
        return $key;
    }
}

sub SELF_SHIFT {
    my ($method_name, $args) = @_;
    shift @{$args};
    return;
}

sub SELF_CODED {
    my ($method_name, $args) = @_;
    our $ENCODER ||= JSON::XS->new->convert_blessed(1);
    *UNIVERSAL::TO_JSON = sub { Storable::nfreeze \@_ };
    my $json = $ENCODER->encode($args->[0]);
    undef *UNIVERSAL::TO_JSON;
    $args->[0] = Digest::SHA::sha1_base64($json);
    return;
}

sub PER_OBJECT {
    my ($method_name, $args) = @_;
    $args->[0] = Scalar::Util::refaddr $args->[0];
    return;
}

sub LIST {
    my ($method_name, $args) = @_;
    local $^W = 0;
    $method_name . join chr(28), @{$args};
}

sub HASH {
    my ($method_name, $args) = @_;
    local $^W = 0;
    my ($ser, %hash) = (q{}, @{$args});
    map {
        $ser .= chr(28) . $_ . (defined $hash{$_} ? '=' . $hash{$_} : q{})
    } sort keys %hash;
    $method_name . $ser;
}

sub SERIALIZE {
    my ($method_name, $args) = @_;
    local $^W = 0;
    our $ENCODER ||= JSON::XS->new->convert_blessed(1);
    *UNIVERSAL::TO_JSON = sub { Storable::nfreeze \@_ };
    my $json = $ENCODER->encode($args);
    undef *UNIVERSAL::TO_JSON;
    $method_name . Digest::SHA::sha1_base64($json);
}

1;

__END__
