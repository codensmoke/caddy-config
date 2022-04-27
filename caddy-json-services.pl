#!/usr/bin/env perl 
use strict;
use warnings;

use utf8;

=encoding UTF8

=head1 NAME

caddy-json-services.pl - Script to generate Caddy webserver configuration JSON file based on services

=head1 SYNOPSIS

Write JSON output to a file.
Example
    bin/caddy-json-services.pl -o /tmp/output.json -e production

You can use output directly to be sent to Caddy API directly too
Example
    curl localhost:2019/load -X POST -H "Content-Type: application/json" -d "$(bin/caddy-json-services.pl -e production)"

=head1 DESCRIPTION

This script parse the needed network routing information from the available Services
then it transform them to the required Caddy webserver configuration settings
generating a JSON structure to be consumed by Caddy API to load settings.

=cut

=head1 OPTIONS

=over 4

=item B<-b> I</app/>, B<--base-path>=I<./>

Base path where services directory located.
Default is current path: ./

=item B<-c> I<0>, B<--console-output>=I<1>

Whether to have generated JSON printed to console or not.
Default is set to: 1

=item B<-e> I<dev>, B<--environment>=I<production>

Select which environment to generate configuration for.
Default is set to: dev

=item B<-o> I</tmp/output.json>, B<--output-file>=I<path>

Path to file to write JSON output to. If left empty no file will be written.
Default will not write to file.

=item B<-l> I<debug>, B<--log-level>=I<info>

Log level for script.
Default is: info

=back

=cut

use Pod::Usage;
use Getopt::Long;
use Syntax::Keyword::Try;
use YAML::XS qw(LoadFile);
use Log::Any qw($log);
use Path::Tiny;
use JSON::MaybeUTF8 qw(:v1);
use Sys::Hostname;
use Dotenv -load;

GetOptions(
    'b|base-path=s'      => \(my $base_path      = './'),
    'c|config-file=s'    => \(my $config_path = './config.yml'),
    'i|console-output=i' => \(my $console_output = 1),
    'e|environment=s'    => \(my $env            = 'dev'),
    'o|output-file=s'    => \(my $output_file),
    'l|log-level=s'      => \(my $log_level      = 'info'),
    'h|help'             => \my $help,
);

require Log::Any::Adapter;
Log::Any::Adapter->set( qw(Stdout), log_level => $log_level );

pod2usage(
    {
        -verbose  => 99,
        -sections => "NAME|SYNOPSIS|DESCRIPTION|OPTIONS",
    }
) if $help;


my $config = {};
my $users = [];
my $server;

=head1 METHODS

=cut

sub add_certificate_authority {
    my ($name, $crt, $key) = @_;
    $config->{apps}{pki}{certificate_authorities}{$name.'CA'} = {
        name => $name,
        root => {
            certificate => $crt,
            private_key => $key
        },
    };
}

sub add_http_server {
    my $hostname = shift // hostname;
    $config->{apps}{http}{servers}{$hostname} = {
        listen => [':443'],
        routes => [],
    };
    $server = $config->{apps}{http}{servers}{$hostname};
}

sub add_auth_users {
    my $u = shift;
    # We expect passwords, and passwords hashs
    # are maintained in .env variables
    push @$users, {
        username => $_->{username},
        password => $ENV{$_->{username}.'_password_hash'} // $ENV{'auth_password_hash'},
    } for @$u;


}

sub add_app {
    my %args = @_;
    my ($type, $name, $port, $hostname, $path, $tls, $root, $basic_auth) = map { $args{$_} } qw(type name port hostname path tls root basic_auth);
    ($name, $port) = split ':', $args{container} if exists $args{container};
    die ('Please add HTTP server before adding an App') unless defined $server;
    my $handles = [];
    my $matchers = [];
    push @$handles, basic_auth_handler() if $basic_auth;
    push @$handles,
        $type eq 'service' ? reverse_proxy_handler($name, $port, $tls // 0) : (),
        $type eq 'content' ? file_server_handler($root) : ();
    push @$matchers, matcher($hostname, $path //= ["/*"]);
    push $server->{routes}->@*, {
        group => $name,
        handle => $handles,
        match => $matchers
    };

}

sub basic_auth_handler {
    return {
        handler => "authentication",
        providers => {
            http_basic => {
                accounts => $users,
                hash => { algorithm => 'bcrypt'},
            }
        }
    };
}

sub reverse_proxy_handler {
    my ($name, $port, $tls) = @_;
    return {
        handler => "reverse_proxy",
        upstreams => [{dial => "$name:$port"}],
        headers => { request => { set => { 
                    host => ["{http.reverse_proxy.upstream.hostport}"],
                    'x-forwarded-host' => ["{http.request.host}"]
                }}},
        $tls ? () : (),
    };
}

sub file_server_handler {
    my $root = shift;
    return {
        handler => "file_server",
        root => $root,
    };
}

sub matcher {
    my ($hostname, $path) = @_;
    return {
        host => [$hostname],
        protocol => "https",
        path => $path
    };
}

my $config_file = LoadFile($config_path);
add_http_server();
add_auth_users($config_file->{user});
for my $type (qw (service content)) {
    add_app(type => $type, $_->%*) for $config_file->{$type}->@*;
}

use Data::Dumper;
$log->infof('Done | %s | %s | %s', Dumper($config), encode_json_text($config), Dumper($users));
