# Minimal static file server for verifying the STAR Kidz apps.
# Serves the project root over http://localhost:8765 so both HTML apps
# share one real origin (localStorage + storage events work like production).
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot   # project root (parent of .claude)
$port = if ($env:PORT) { $env:PORT } else { '8765' }
$prefix = "http://localhost:$port/"
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($prefix)
$listener.Start()
Write-Host "Serving $root at $prefix (PORT=$port)"

$mime = @{
  '.html'='text/html; charset=utf-8'; '.js'='application/javascript; charset=utf-8';
  '.json'='application/json; charset=utf-8'; '.svg'='image/svg+xml'; '.txt'='text/plain; charset=utf-8';
  '.png'='image/png'; '.ico'='image/x-icon'
}

while ($listener.IsListening) {
  try {
    $ctx = $listener.GetContext()
    $rel = [System.Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath.TrimStart('/'))
    if ([string]::IsNullOrWhiteSpace($rel)) { $rel = 'index.html' }
    $path = Join-Path $root $rel
    if (Test-Path $path -PathType Leaf) {
      $bytes = [System.IO.File]::ReadAllBytes($path)
      $ext = [System.IO.Path]::GetExtension($path).ToLower()
      if ($mime.ContainsKey($ext)) { $ctx.Response.ContentType = $mime[$ext] }
      $ctx.Response.StatusCode = 200
      $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    } else {
      $ctx.Response.StatusCode = 404
      $msg = [System.Text.Encoding]::UTF8.GetBytes("404: $rel")
      $ctx.Response.OutputStream.Write($msg, 0, $msg.Length)
    }
    $ctx.Response.OutputStream.Close()
  } catch { }
}
