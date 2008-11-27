package Method::Cached;

use strict;
use warnings;
use Attribute::Handlers;
use Carp qw/croak confess/;
use UNIVERSAL::require;
use Method::Cached::KeyRule;

our $VERSION = '0.04';

my %_DOMAINS;
my %_METHOD_INFO;
my $_DEFAULT_DOMAIN = {
    storage_class => 'Cache::FastMmap',
    storage_args  => [],
    # key_rule    => 'LIST', # default 'LIST' at KeyRule.pm
};

sub UNIVERSAL::Cached :ATTR(CODE) {
    my ($pkg, $symbol, $code, $options) = @_[0 .. 2, 4];
    $options = [ $options || () ] unless ref $options eq 'ARRAY';
    my $name = $pkg . '::' . *{$symbol}{NAME};
    my ($dname, $expires, $key_rule) = _parse_option(@{ $options });
    my $info = _note_method_info($name, $code, $dname, $expires, $key_rule);
    no strict 'refs';
    no warnings 'redefine';
    *{$name} = sub { unshift @_, ($info, wantarray); goto &_wrapper };
}

sub import {
    my ($class, %args) = @_;
    if (exists $args{-domains} && defined $args{-domains}) {
        my $domains = $args{-domains};
        ref $domains eq 'HASH'
            || confess '-domains option should be a hash reference';
        $class->set_domain(%{ $domains });
    }
    if (exists $args{-default} && defined $args{-default}) {
        my $default = $args{-default};
        ref $default eq 'HASH'
            || confess '-default option should be a hash reference';
        $class->default_domain($default);
    }
    else {
        _inspect_storage_class($_DEFAULT_DOMAIN->{storage_class});
    }
}

sub delete {
    my ($class, $namespace) = splice @_, 0, 2;
    unless (exists $_METHOD_INFO{$namespace}) {
        if ($namespace =~ /^(.*)::([^:]*)$/) {
            my ($package, $method) = ($1, $2);
            $package->require || confess "Can't load module: $package";
        }
    }
    if (exists $_METHOD_INFO{$namespace}) {
        my $info    = $_METHOD_INFO{$namespace};
        my $dname   = $info->{domain};
        my $domain  = $_DOMAINS{$dname} ? $_DOMAINS{$dname} : $_DEFAULT_DOMAIN;
        my $rule    = $info->{key_rule} || $domain->{key_rule};
        my $key     = Method::Cached::KeyRule::regularize($rule, $info->{name}, [ @_ ]);
        my $storage = _storage($domain);
        my $dmethod = $storage->can('delete') || $storage->can('clear');
        $dmethod->($storage, $key . $_) for qw/ :l :s /;
    }
}

sub default_domain {
    my ($class, $args) = @_;
    if ($args) {
        exists $args->{key_rule} && delete $args->{key_rule};
        $_DEFAULT_DOMAIN = {
            %{ $_DEFAULT_DOMAIN },
            %{ $args },
        };
        _inspect_storage_class($_DEFAULT_DOMAIN->{storage_class});
    }
    return $_DEFAULT_DOMAIN;
}

sub set_domain {
    my ($class, %args) = @_;
    for my $name (keys %args) {
        my $args = $args{$name};
        if (exists $_DOMAINS{$name}) {
            warn 'This domain has already been defined: ' . $name;
            next;
        }
        $_DOMAINS{$name} = $args;
        _inspect_storage_class($_DOMAINS{$name}->{storage_class});
    }
}

sub get_domain {
    my ($class, $dname) = @_;
    return $_DOMAINS{$dname};
}

sub _parse_option {
    my $dname    = q{};
    my $expires  = 0;
    my $key_rule = undef;
    if (0 < @_) {
        if ((! defined $_[0]) || ($_[0] !~ /^?\d+$/)) {
            $dname = shift;
        }
    }
    $dname ||= q{};
    if (0 < @_) {
        $expires  = ($_[0] =~ /^\d+$/) ? shift @_ : confess
            'The first argument or the second argument should be a numeric value.';
        $key_rule = shift if 0 < @_;
    }
    return ($dname, $expires, $key_rule);
}

sub _note_method_info {
    my ($name, $code, $dname, $expires, $key_rule) = @_;
    $_METHOD_INFO{$name} = {
        name     => $name,
        code     => $code,
        domain   => $dname,
        expires  => $expires,
        key_rule => $key_rule,
    };
}

sub _storage {
    my $domain = shift;
    $domain->{_storage_instance} && return $domain->{_storage_instance};
    my $st_class = $domain->{storage_class} || croak 'storage_class is necessary';
    my $st_args  = $domain->{storage_args}  || undef;
    $domain->{_storage_instance} = $st_class->new(@{ $st_args || [] });
}

sub _inspect_storage_class {
    my $any_class = shift;
    my $invalid;
    $any_class->require || confess "Can't load module: $any_class";
    $any_class->can($_) || $invalid++ for qw/new set get/;
    $any_class->can('delete') || $any_class->can('remove') || $invalid++;
    $invalid && croak
        'storage_class needs the following methods: new, set, get, delete or remove';
}

sub _wrapper {
    my ($info, $warray) = splice @_, 0, 2;
    my $dname   = $info->{domain};
    my $domain  = $_DOMAINS{$dname} ? $_DOMAINS{$dname} : $_DEFAULT_DOMAIN;
    my $rule    = $info->{key_rule} || $domain->{key_rule};
    my $key     = Method::Cached::KeyRule::regularize($rule, $info->{name}, [ @_ ]);
    my $key_af  = $key . ($warray ? ':l' : ':s');
    my $storage = _storage($domain);
    my $ret     = $storage->get($key_af);
    unless ($ret) {
        $ret = [ $warray ? $info->{code}->(@_) : scalar $info->{code}->(@_) ];
        $storage->set($key_af, $ret, $info->{expires} || 0);
    }
    return $warray ? @{ $ret } : $ret->[0];
}

1;

__END__

=head1 NAME

Method::Cached - The return value of the method is cached to your storage

=head1 SYNOPSIS

  package Foo;
   
  use Method::Cached;
   
  sub message :Cached(5) { join ':', @_, time, rand }
  
  package main;
  use Perl6::Say;
  
  say Foo::message(1); # 1222333848
  sleep 1;
  say Foo::message(1); # 1222333848
  
  say Foo::message(5); # 1222333849

=head1 DESCRIPTION

Method::Cached offers the following mechanisms:

The return value of the method is stored in storage, and
the value stored when being execute it next time is returned.

=head2 SETTING OF CACHED DOMAIN

In beginning logic or the start-up script:

  use Method::Cached;
  
  Method::Cached->default_domain({
      storage_class => 'Cache::FastMmap',
  });
  
  Method::Cached->set_domain(
      'some-namespace' => {
          storage_class => 'Cache::Memcached::Fast',
          storage_args  => [
              {
                  # Parameter of constructor of class that uses it for cashe
                  servers => [ '192.168.254.2:11211', '192.168.254.3:11211' ],
                  ...
              },
          ],
      },
  );

=head2 DEFINITION OF METHODS

This function is mounting used as an attribute of the method. 

=over 4

=item B<:Cached ( DOMAIN_NAME, EXPIRES, [, KEY_RULE, ...] )>

The cached rule is defined specifying the domain name.

  sub message :Cached('some-namespace', 60 * 5, LIST) { ... }

=item B<:Cached ( EXPIRES, [, KEY_RULE, ...] )>

When the domain name is omitted, the domain of default is used.

  sub message :Cached(60 * 30, LIST) { ... }

=back

=head2 RULE TO GENERATE KEY

=over 4

=item B<LIST>

=item B<HASH>

=item B<SELF_SHIFT>

=item B<PER_OBJECT>

=back

=head2 OPTIONAL, RULE TO GENERATE KEY

  use Method::Cached;
  use Method::Cached::KeyRule::Serialize;

=over 4

=item B<SERIALIZE>

=item B<SELF_CODED>

=back

=head1 METHODS

=over 4

=item B<default_domain ($setting)>

=item B<set_domain (%domain_settings)>

=item B<get_domain ($domain_name)>

=back

=head1 AUTHOR

Satoshi Ohkubo E<lt>s.ohkubo@gmail.comE<gt>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
