# Local preview of ./dist at http://localhost:8080 (Ctrl+C to stop)
param([int]$Port = 8080)

$dist = Join-Path $PSScriptRoot 'dist'
$types = @{
  '.html' = 'text/html; charset=utf-8'; '.css' = 'text/css; charset=utf-8'; '.js' = 'text/javascript; charset=utf-8'
  '.svg' = 'image/svg+xml'; '.png' = 'image/png'; '.jpg' = 'image/jpeg'; '.jpeg' = 'image/jpeg'; '.webp' = 'image/webp'
  '.ico' = 'image/x-icon'; '.xml' = 'application/xml'; '.txt' = 'text/plain; charset=utf-8'; '.woff2' = 'font/woff2'
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Host "Serving $dist on http://localhost:$Port/"

while ($listener.IsListening) {
  $ctx = $listener.GetContext()
  $rel = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath).TrimStart('/')
  $path = Join-Path $dist $rel
  if (Test-Path $path -PathType Container) { $path = Join-Path $path 'index.html' }
  $status = 200
  if (-not (Test-Path $path -PathType Leaf)) { $path = Join-Path $dist '404.html'; $status = 404 }

  $bytes = [IO.File]::ReadAllBytes($path)
  $ext = [IO.Path]::GetExtension($path).ToLower()
  $ctx.Response.StatusCode = $status
  $ctx.Response.ContentType = if ($types[$ext]) { $types[$ext] } else { 'application/octet-stream' }
  $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
  $ctx.Response.Close()
}
