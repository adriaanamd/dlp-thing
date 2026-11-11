$ErrorActionPreference = "Stop"

$root = [System.IO.Path]::GetFullPath((Split-Path -Parent $MyInvocation.MyCommand.Path))
$port = 8765
$listener = [System.Net.Sockets.TcpListener]::new(
  [System.Net.IPAddress]::Loopback,
  $port
)

function Get-ContentType([string] $path) {
  switch ([System.IO.Path]::GetExtension($path).ToLowerInvariant()) {
    ".html" { return "text/html; charset=utf-8" }
    ".js" { return "text/javascript; charset=utf-8" }
    ".css" { return "text/css; charset=utf-8" }
    ".json" { return "application/json; charset=utf-8" }
    ".wasm" { return "application/wasm" }
    ".data" { return "application/octet-stream" }
    ".binarypb" { return "application/octet-stream" }
    default { return "application/octet-stream" }
  }
}

function Send-Response(
  [System.IO.Stream] $stream,
  [int] $statusCode,
  [string] $statusText,
  [string] $contentType,
  [byte[]] $body
) {
  $header = "HTTP/1.1 $statusCode $statusText`r`n" +
    "Content-Type: $contentType`r`n" +
    "Content-Length: $($body.Length)`r`n" +
    "Cache-Control: no-store`r`n" +
    "Connection: close`r`n`r`n"
  $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
  $stream.Write($headerBytes, 0, $headerBytes.Length)
  if ($body.Length -gt 0) {
    $stream.Write($body, 0, $body.Length)
  }
}

$rootWithSlash = $root.TrimEnd([System.IO.Path]::DirectorySeparatorChar) +
  [System.IO.Path]::DirectorySeparatorChar

try {
  $listener.Start()
  $url = "http://localhost:$port/HEAD%20TILT.html"
  Write-Host "Opening Head Tilt at $url"
  Write-Host "Leave this window open while the game is running. Press Ctrl+C to stop."
  Start-Process $url

  while ($true) {
    $client = $listener.AcceptTcpClient()
    try {
      $stream = $client.GetStream()
      $reader = [System.IO.StreamReader]::new(
        $stream,
        [System.Text.Encoding]::ASCII,
        $false,
        1024,
        $true
      )
      $requestLine = $reader.ReadLine()
      while (($line = $reader.ReadLine()) -ne "" -and $null -ne $line) { }

      if ($requestLine -notmatch "^GET\s+(\S+)") {
        Send-Response $stream 405 "Method Not Allowed" "text/plain; charset=utf-8" @()
        continue
      }

      $requestPath = $Matches[1].Split("?")[0]
      $relativePath = [System.Uri]::UnescapeDataString($requestPath).TrimStart("/")
      if ([string]::IsNullOrWhiteSpace($relativePath)) {
        $relativePath = "HEAD TILT.html"
      }

      $filePath = [System.IO.Path]::GetFullPath(
        (Join-Path $root ($relativePath.Replace("/", [System.IO.Path]::DirectorySeparatorChar)))
      )
      if (-not $filePath.StartsWith($rootWithSlash, [System.StringComparison]::OrdinalIgnoreCase)) {
        Send-Response $stream 403 "Forbidden" "text/plain; charset=utf-8" @()
        continue
      }
      if (-not [System.IO.File]::Exists($filePath)) {
        Send-Response $stream 404 "Not Found" "text/plain; charset=utf-8" @()
        continue
      }

      $body = [System.IO.File]::ReadAllBytes($filePath)
      Send-Response $stream 200 "OK" (Get-ContentType $filePath) $body
    } catch {
      if ($client.Connected) {
        try {
          Send-Response $client.GetStream() 500 "Internal Server Error" "text/plain; charset=utf-8" @()
        } catch { }
      }
    } finally {
      if ($reader) { $reader.Dispose() }
      if ($stream) { $stream.Dispose() }
      $client.Dispose()
      $reader = $null
      $stream = $null
    }
  }
} finally {
  $listener.Stop()
}
