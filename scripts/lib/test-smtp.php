<?php
// Send ONE test message through the transport OJS builds for its `smtp` mailer (Laravel's Symfony Mailer, from [email] in config.inc.php),
// so the test covers the connection and login the site really uses. Run ON THE HOST from the web root, the script on php's standard input:
//   cd WEBROOT && php -- ADDRESS < test-smtp.php
// Prints one line: `OK ...` or `FAILED ...`. Never prints a credential (the password is masked in any error text).
if (PHP_SAPI !== 'cli' || empty($argv[1]) || !filter_var($argv[1], FILTER_VALIDATE_EMAIL)) {
    fwrite(STDERR, "usage: php -- ADDRESS < test-smtp.php\n");
    exit(2);
}
$to = $argv[1];
$cfg = parse_ini_file('config.inc.php', true, INI_SCANNER_RAW);
$e = $cfg['email'] ?? [];
$q = function ($v) { return trim((string) $v, "\" "); };
$default = $q($e['default'] ?? '');
$pass = $q($e['smtp_password'] ?? '');
$user = $q($e['smtp_username'] ?? '');
$host = $q($e['smtp_server'] ?? '');
$port = $q($e['smtp_port'] ?? '');
$auth = $q($e['smtp_auth'] ?? '');
if ($default !== 'smtp') {
    echo "FAILED: [email] default is '$default', not smtp: OJS would not use the SMTP settings (PHP's own mail is capped at 100 a day on this host)\n";
    exit(1);
}
if ($host === '' || $port === '' || $user === '' || $pass === '') {
    echo "FAILED: smtp_server, smtp_port, smtp_username or smtp_password is empty in config.inc.php\n";
    exit(1);
}
$mask = function ($t) use ($pass) { return $pass === '' ? $t : str_replace($pass, '***', (string) $t); };
try {
    require 'tools/bootstrap.php';
    // OJS's own mailer wrapper reports an SMTP error by printing it and then returns normally, so success and failure look alike.
    // Take the SAME configured transport (host, port, encryption, login, certificate check, all from [email]) and send through it
    // directly: it throws on any error.
    $transport = \Illuminate\Support\Facades\Mail::mailer('smtp')->getSymfonyTransport();
    $mail = (new \Symfony\Component\Mime\Email())
        ->from(new \Symfony\Component\Mime\Address($user, 'World Open Research Journal (SMTP test)'))
        ->to($to)
        ->subject('WORJ SMTP test ' . gmdate('Y-m-d H:i:s') . ' UTC')
        ->text("This is a test message from the World Open Research Journal test site.\nIf you can read it, the site can send mail through $host.\nNothing needs to be done.");
    $transport->send($mail);
    echo "OK: accepted by $host:$port ($auth) from $user to $to\n";
} catch (Throwable $ex) {
    echo 'FAILED: ' . $mask($ex->getMessage()) . "\n";
    exit(1);
}
