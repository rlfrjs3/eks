<?php
// DB connection info
$dbHost = getenv('DB_HOST') ?: 'mysql';
$dbUser = getenv('DB_USER') ?: 'root';
$dbPass = getenv('DB_PASSWORD') ?: '';
$dbName = getenv('DB_NAME') ?: 'test';

$dbStatus = 'Disconnected';
$mysqlVersion = 'N/A';

try {
    $mysqli = new mysqli($dbHost, $dbUser, $dbPass, $dbName);

    if ($mysqli->connect_errno) {
        throw new Exception($mysqli->connect_error);
    }

    $dbStatus = 'Connected';

    $result = $mysqli->query("SELECT VERSION() AS version");

    if ($result) {
        $row = $result->fetch_assoc();
        $mysqlVersion = $row['version'];
    }

    $mysqli->close();
} catch (Throwable $e) {
    $dbStatus = 'Disconnected';
}

// Apache version
$apacheVersion = apache_get_version();

// PHP version
$phpVersion = PHP_VERSION;
?>

<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Shopping Mall</title>

    <style>
        body {
            font-family: Arial, sans-serif;
            background: #f4f6f8;
            margin: 0;
            padding: 40px;
            color: #222;
        }

        .container {
            max-width: 800px;
            margin: 0 auto;
            background: #fff;
            padding: 40px;
            border-radius: 12px;
            box-shadow: 0 4px 20px rgba(0,0,0,0.08);
        }

        h1 {
            margin-top: 0;
        }

        .subtitle {
            color: #666;
            margin-bottom: 30px;
        }

        .status {
            font-size: 18px;
            margin-bottom: 30px;
        }

        .connected {
            color: green;
            font-weight: bold;
        }

        .disconnected {
            color: red;
            font-weight: bold;
        }

        .info {
            border-top: 1px solid #ddd;
            padding-top: 20px;
        }

        .info p {
            margin: 10px 0;
        }

        .label {
            font-weight: bold;
        }
    </style>
</head>

<body>

<div class="container">

    <h1>Shopping Mall</h1>

    <div class="subtitle">
        Apache + PHP + MySQL Container Application
    </div>

    <div class="status">
        <strong>Database Status :</strong>

        <?php if ($dbStatus === 'Connected'): ?>
            <span class="connected">Connected</span>
        <?php else: ?>
            <span class="disconnected">Disconnected</span>
        <?php endif; ?>
    </div>

    <div class="info">
        <p>
            <span class="label">Apache Version :</span>
            <?= htmlspecialchars($apacheVersion) ?>
        </p>

        <p>
            <span class="label">PHP Version :</span>
            <?= htmlspecialchars($phpVersion) ?>
        </p>

        <p>
            <span class="label">MySQL Version :</span>
            <?= htmlspecialchars($mysqlVersion) ?>
        </p>
    </div>

</div>

</body>
</html>
