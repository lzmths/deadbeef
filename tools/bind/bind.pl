#!/usr/bin/env perl
use strict;
use warnings;

use FindBin qw'$Bin';
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/perl_lib";
BEGIN { $ENV{PERL_JSON_BACKEND} = 0 }
use JSON -support_by_pp;
use Data::Dumper;

open F,"<api.json" or die "failed to read api.json\n";
my $api;
{
    local $/;
    $api = <F>;
}
close F;

my $json = JSON->new;
$json->relaxed([1]);
$json->allow_singlequote([1]);
$json->allow_barekey([1]);

$api = $json->decode($api);
#print Dumper($api)."\n";
print "/* WARNING: autogenerated file */\n";
print "#include \"duktape.h\"\n";
print "#include \"../../deadbeef.h\"\n\n";
print "#include \"types.h\"\n";
print "#include \"bindings.h\"\n";
print "#include \"custombindings.h\"\n\n";
print "extern DB_functions_t *deadbeef;\n\n";

# int constants
print "void bind_int_constants (duk_context *ctx, int obj_idx) {\n";
my $int_constants = $api->{int_constants};
foreach my $c (keys %$int_constants) {
    print "    duk_push_int(ctx, $int_constants->{$c});\n";
    print "    duk_put_prop_string(ctx, obj_idx, \"$c\");\n";
}
print "}\n\n";

my %ret_converters = (
);

my $functions = $api->{functions};

# function impls
foreach my $c (keys %$functions) {
    my $f = $functions->{$c};
    if (!$f->{name}) {
        $f->{name} = $c;
    }
    next if $f->{custom};
    if (!$f->{ret}) {
        $f->{ret} = 'void';
    }
    if (!$f->{args}) {
        $f->{args} = 'void';
    }
    print "int\njs_impl_$f->{name} (duk_context *ctx) {\n";
    if (ref ($f->{args}) eq 'ARRAY') {
        my $realidx = 0;
        my $idx = 0;
        foreach my $type (@{$f->{args}}) {
            my $convname = $type;
            $convname =~ s/\*/_ptr/g;
            $convname =~ s/[^A-Za-z0-9_]/_/g;
            print "    $type arg$idx = js_init_" . $convname . "_argument (ctx, $idx);\n";
            if ($type eq 'jscharbuffer') {
                $idx++;
                print "    int arg$idx = js_init_" . $convname . "_size_argument (ctx, $realidx);\n";
            }
            $realidx++;
            $idx++;
        }
    }

    if ($f->{ret} ne 'void') {
        print "    $f->{ret} ret = ";
    }
    else {
        print "    ";
    }

    print "deadbeef->$c (";
    if (ref ($f->{args}) eq 'ARRAY') {
        my $idx = 0;
        foreach my $type (@{$f->{args}}) {
            print ', ' if $idx;
            print "arg$idx";
            if ($type eq 'jscharbuffer') {
                $idx++;
                print ', ' if $idx;
                print "arg$idx";
            }
            $idx++;
        }
    }
    elsif ($f->{args} ne 'void') {
        die "Invalid argument list: \n" . Dumper($f) . "\n";
    }
    print ");\n";


    if ($f->{ret} eq 'void') {
        print "    return 0;\n";
    }
    else {
        my $convname = $f->{ret};
        $convname =~ s/\*/_ptr/g;
        $convname =~ s/[^A-Za-z0-9_]/_/g;
        print '    js_return_' . $convname . "_value (ctx, ret);\n";
        print "    return 1;\n";
    }
    print "}\n\n";
}

# functions
print "void bind_functions (duk_context *ctx, int obj_idx) {\n";
foreach my $c (keys %$functions) {
    my $f = $functions->{$c};
    my $argcnt = $f->{args};

    if (ref ($f->{args}) eq 'ARRAY') {
        $argcnt = ~~@{$f->{args}};
    }
    else {
        $argcnt = 0;
    }
    print "    duk_push_c_function(ctx, js_impl_$f->{name}, $argcnt);\n";
    print "    duk_put_prop_string(ctx, obj_idx, \"$f->{name}\");\n";
}
print "}\n\n";

# util
print "void duktape_bind_all (duk_context *ctx) {\n";
print "    duk_push_global_object (ctx);\n";
print "    int obj_idx = duk_push_object (ctx);\n";
print "    bind_int_constants(ctx, obj_idx);\n";
print "    bind_functions(ctx, obj_idx);\n";
print "    duk_put_prop_string(ctx, -2, \"deadbeef\");\n";
print "    duk_pop(ctx);\n";
print "}\n\n";
