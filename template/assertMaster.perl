use IO::Socket::INET;
use POSIX qw{setsid};

use strict;
use warnings;

# names of primary and backup message routers
my $primaryName = "primary";
my $backupName  = "backup";

sub encodeBase64
{
    my $s = shift ;
    my $r = '';
    while( $s =~ /(.{1,45})/gs ) {
        chop( $r .= substr(pack("u",$1),1) );
    }
    my $pad=(3-length($s)%3)%3;
    $r =~ tr|` -_|AA-Za-z0-9+/|; 
    $r=~s/.{$pad}$/"="x$pad/e if $pad; 
    $r; 
} 

my $attemptCount = 0;

sub post {
    my ($host, $port, $request, $data) = @_;

   # auto-flush on socket
   $| = 1;

    my $socket = new IO::Socket::INET (
        PeerHost => $host,
        PeerPort => $port,
        Proto => 'tcp',
    );
    if (!$socket) {
        print "Cannot connect to the message broker $host:$port, attempt # $attemptCount\n";
        return 0;
    }
    print "Checking if message broker $host:$port is ready, attempt # $attemptCount\n";

    my $timeout = pack("qq", 5, 0);
    $socket->sockopt(SO_RCVTIMEO, $timeout);
    
    my $len = length($data);
    my $httpReq = "POST $request HTTP/1.1\r\n" .
                  "Host: $host:$port\r\n" .
                  "Authorization: Basic " . encodeBase64("$ENV{ADMIN_USERNAME}:$ENV{ADMIN_PASSWORD}") . "\r\n" .
                  "Content-Length: $len\r\n\r\n$data";
    my $size = $socket->send($httpReq);
    #print "sent data:\n$httpReq\nof length $size\n";

    # notify server that request has been sent
    shutdown($socket, 1);
 
    # receive a response of up to 1024 characters from server
    my $response = "";
    $socket->recv($response, 1024);
    #print "received response: $response\n";
    
    $socket->close();    
    return ($response =~ /200 OK/);
}

sub addHaProxyListen {
    my ($fh, $name, $port) = @_;

    print $fh "listen $name\n" .
              "  bind *:$port\n" .
              "  server $primaryName $primaryName:$port track semp_servers/$primaryName\n" .
              "  server $backupName $backupName:$port track semp_servers/$backupName\n\n"
}

# Create haproxy configuration file
my $proxyErrorFile = '/usr/local/etc/haproxy/errors/503-custom.http';
my $proxyConfig    = '/usr/local/etc/haproxy/haproxy.cfg';
open(my $fh, '>', $proxyConfig) or die "Could not open file '$proxyConfig' $!";

my $baseConfig = <<'BASE_CONFIG';
global
  log 127.0.0.1 local0
  log 127.0.0.1 local1 notice
  log-send-hostname
  maxconn 4096
  pidfile /var/run/haproxy.pid
  daemon
  stats socket /var/run/haproxy.stats level admin
  ssl-default-bind-options no-sslv3
  ssl-default-bind-ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA384:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA:AES128-GCM-SHA256:AES128-SHA256:AES128-SHA:AES256-GCM-SHA384:AES256-SHA256:AES256-SHA:DHE-DSS-AES128-SHA:DES-CBC3-SHA
defaults
  balance roundrobin
  log global
  mode tcp
  option redispatch
  option dontlognull
  timeout connect 5000
  timeout client 50000
  timeout server 50000
listen stats
  bind :1936
  mode http
  stats enable
  timeout connect 10s
  timeout client 1m
  timeout server 1m
  stats hide-version
  stats realm Haproxy\ Statistics
  stats uri /
BASE_CONFIG
  
my $frontEndConfig = <<'FRONT_END_CONFIG';

frontend semp_in
  bind *:8080
  default_backend semp_servers
  mode http
backend semp_servers
  mode http
  option httpchk GET /health-check/direct-active
  http-check expect status 200
  default-server inter 3s fall 3 rise 2 
  errorfile 503 /usr/local/etc/haproxy/errors/503-custom.http  

FRONT_END_CONFIG

print $fh $baseConfig;
print $fh "  stats auth $ENV{ADMIN_USERNAME}:$ENV{ADMIN_PASSWORD}\n";
print $fh $frontEndConfig;
print $fh "  server $primaryName $primaryName:8080 check port 5550\n";
print $fh "  server $backupName $backupName:8080 check port 5550\n\n";

addHaProxyListen($fh, 'semp_tls_in',       1943);
addHaProxyListen($fh, 'smf_in',            55555);
addHaProxyListen($fh, 'smf_compressed_in', 55003);
addHaProxyListen($fh, 'smf_tls_in',        55443);
addHaProxyListen($fh, 'web_in',            8008);
addHaProxyListen($fh, 'web_tls_in',        1443);
addHaProxyListen($fh, 'mqtt_in',           1883);
addHaProxyListen($fh, 'mqtt_tls_in',       8883);
addHaProxyListen($fh, 'mqtt_web_in',       8000);
addHaProxyListen($fh, 'mqtt_web_tls_in',   8443);
addHaProxyListen($fh, 'amqp_in',           5672);
addHaProxyListen($fh, 'amqp_tls_in',       5671);
addHaProxyListen($fh, 'rest_in',           9000);
addHaProxyListen($fh, 'rest_tls_in',       9443);

close $fh;

# Set up a custom haproxy error file for 503
my $errorFileContents = <<'ERROR_FILE';
HTTP/1.0 503 Service Unavailable
Cache-Control: no-cache
Connection: close
Content-Type: text/html

<html> 
  <head>
    <title>Startup in Progress</title>
  </head> 
  <body>
    <h2>Solace administration portal will become available once message broker is up, please try again later.</h2>
  </body> 
</html>
ERROR_FILE

open($fh, '>', $proxyErrorFile) or die "Could not open file '$proxyErrorFile' $!";
print $fh $errorFileContents;
close $fh;

# Launch haproxy
my $pid = fork();
if ($pid == 0) {
  POSIX::setsid();   # this takes care of controlling terminals
  exec("haproxy -W -db -f $proxyConfig");
} elsif (!defined($pid)) {
    die "could not fork to start haproxy";
}

# assert master on active message broker if not one once before
my $filename = '/assert_master_done.txt';
if (-e $filename) {
    print "Assert master already complete\n";
} else {
    my $done = 0;
    do {
        $attemptCount += 1;
        $done = post("127.0.0.1",8080,
                     '/SEMP', 
                     '<rpc semp-version="soltr/8_10VMR">' .
                     '<admin><config-sync>' .
                     '<assert-master><router></router></assert-master>' .
                     '</config-sync></admin>' .
                     '</rpc>');
        if ($done) {
            print "Assert master admin operation completed, attempt # $attemptCount\n";
            open TMPFILE, '>', $filename and close TMPFILE
            or die "File error with $filename: $!";
        } else {
            sleep(5);
        }
    } while (!$done);
}

while (wait() != -1) {}

0;

