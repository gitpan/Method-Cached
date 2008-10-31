package Method::Cached::KeyRule;

use strict;
use warnings;
use Digest::SHA qw/sha1_base64/;
use JSON::XS;
use Storable qw/freeze/;
use Scalar::Util qw/refaddr/;

sub regularize {
    my $key_rule = shift;
    no strict 'refs';
    my $ref = ref $key_rule;
    $ref || return &{$key_rule || 'LIST'}(@_);
    $ref eq 'CODE' && return $key_rule->(@_);
    my $key;
    for my $rule (@{$key_rule}) {
        $key = '';
        $key = ref $rule ? $rule->(@_) : &{$rule}(@_);
    }
    return $key;
}

sub SELF_SHIFT {
    my ($method_name, $args) = @_;
    shift @{$args};
    return;
}

sub SELF_CODED {
    my ($method_name, $args) = @_;
    our $ENCODER ||= JSON::XS->new->convert_blessed(1);
    *UNIVERSAL::TO_JSON = sub { freeze \@_ };
    my $json = $ENCODER->encode($args->[0]);
    undef *UNIVERSAL::TO_JSON;
    $args->[0] = sha1_base64($json);
    return;
}

sub PER_OBJECT {
    my ($method_name, $args) = @_;
    $args->[0] = refaddr $args->[0];
    return;
}

sub LIST {
    my ($method_name, $args) = @_;
    local $^W = 0;
    $method_name . join chr(28), @{$args};
}

sub SERIALIZE {
    my ($method_name, $args) = @_;
    local $^W = 0;
    our $ENCODER ||= JSON::XS->new->convert_blessed(1);
    *UNIVERSAL::TO_JSON = sub { freeze \@_ };
    my $json = $ENCODER->encode($args);
    undef *UNIVERSAL::TO_JSON;
    $method_name . sha1_base64($json);
}

1;

__END__
